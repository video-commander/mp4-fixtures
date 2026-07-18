#!/usr/bin/env python3
"""Insert emsg boxes (SCTE-35 + ID3) before moof boxes in a fragmented MP4.

Safe for default-base-is-moof fragments: trun offsets are moof-relative, so
inserting top-level boxes doesn't break sample addressing.

Events written:
  before moof #1: emsg v1 urn:scte:scte35:2013:bin — splice_insert, OON,
                  pts 2s, 4s auto-return break
  before moof #1: emsg v0 ID3 scheme (non-SCTE passthrough coverage)
  before moof #2: emsg v1 urn:scte:scte35:2013:bin — time_signal at 6s with
                  a Provider Advertisement Start descriptor (4s)
"""
import struct
import sys


class Bits:
    def __init__(self):
        self.buf = bytearray()
        self.n = 0

    def push(self, value, width):
        for i in reversed(range(width)):
            if self.n % 8 == 0:
                self.buf.append(0)
            self.buf[-1] |= ((value >> i) & 1) << (7 - self.n % 8)
            self.n += 1

    def bytes(self):
        assert self.n % 8 == 0
        return bytes(self.buf)


def crc32_mpeg(data: bytes) -> int:
    crc = 0xFFFFFFFF
    for b in data:
        crc ^= b << 24
        for _ in range(8):
            crc = ((crc << 1) ^ 0x04C11DB7 if crc & 0x80000000 else crc << 1) & 0xFFFFFFFF
    return crc


def splice_section(command_type, command: bytes, descriptors: bytes = b"") -> bytes:
    w = Bits()
    section_length = 11 + len(command) + 2 + len(descriptors) + 4
    w.push(0xFC, 8)
    w.push(0, 1)              # section_syntax_indicator
    w.push(0, 1)              # private_indicator
    w.push(3, 2)              # sap_type: not specified
    w.push(section_length, 12)
    w.push(0, 8)              # protocol_version
    w.push(0, 1)              # encrypted_packet
    w.push(0, 6)              # encryption_algorithm
    w.push(0, 33)             # pts_adjustment
    w.push(0, 8)              # cw_index
    w.push(0xFFF, 12)         # tier
    w.push(len(command), 12)
    w.push(command_type, 8)
    body = w.bytes() + command
    body += struct.pack(">H", len(descriptors)) + descriptors
    return body + struct.pack(">I", crc32_mpeg(body))


def splice_insert(event_id, pts_90k, duration_90k) -> bytes:
    w = Bits()
    w.push(event_id, 32)
    w.push(0, 1)              # cancel
    w.push(0x7F, 7)
    w.push(1, 1)              # out_of_network
    w.push(1, 1)              # program_splice
    w.push(1, 1)              # duration_flag
    w.push(0, 1)              # splice_immediate
    w.push(0, 4)
    w.push(1, 1)              # time_specified
    w.push(0x3F, 6)
    w.push(pts_90k, 33)
    w.push(1, 1)              # auto_return
    w.push(0x3F, 6)
    w.push(duration_90k, 33)
    w.push(0x0101, 16)        # unique_program_id
    w.push(1, 8)              # avail_num
    w.push(1, 8)              # avails_expected
    return w.bytes()


def time_signal(pts_90k) -> bytes:
    w = Bits()
    w.push(1, 1)
    w.push(0x3F, 6)
    w.push(pts_90k, 33)
    return w.bytes()


def segmentation_descriptor(event_id, type_id, duration_90k) -> bytes:
    w = Bits()
    w.push(event_id, 32)
    w.push(0, 1)              # cancel
    w.push(0x7F, 7)
    w.push(1, 1)              # program_segmentation
    w.push(1, 1)              # duration_flag
    w.push(1, 1)              # delivery_not_restricted
    w.push(0x1F, 5)
    w.push(duration_90k, 40)
    w.push(0x0C, 8)           # upid_type: MPU()
    w.push(3, 8)
    for b in (0xAB, 0xCD, 0xEF):
        w.push(b, 8)
    w.push(type_id, 8)
    w.push(1, 8)              # segment_num
    w.push(1, 8)              # segments_expected
    payload = b"CUEI" + w.bytes()
    return bytes([0x02, len(payload)]) + payload


def emsg_v1(scheme, value, timescale, presentation_time, duration, event_id, message):
    payload = struct.pack(">IQII", timescale, presentation_time, duration, event_id)
    payload += scheme.encode() + b"\0" + value.encode() + b"\0" + message
    return struct.pack(">I", 12 + len(payload)) + b"emsg" + bytes([1, 0, 0, 0]) + payload


def emsg_v0(scheme, value, timescale, delta, duration, event_id, message):
    payload = scheme.encode() + b"\0" + value.encode() + b"\0"
    payload += struct.pack(">IIII", timescale, delta, duration, event_id)
    payload += message
    return struct.pack(">I", 12 + len(payload)) + b"emsg" + bytes([0, 0, 0, 0]) + payload


def top_level_boxes(data):
    pos = 0
    while pos + 8 <= len(data):
        size, typ = struct.unpack(">I4s", data[pos:pos + 8])
        if size == 1:
            size = struct.unpack(">Q", data[pos + 8:pos + 16])[0]
        elif size == 0:
            size = len(data) - pos
        yield pos, typ.decode("latin1"), size
        pos += size


def main():
    if sys.argv[1] == "--count":
        # Verify mode: print the number of top-level emsg boxes.
        data = open(sys.argv[2], "rb").read()
        print(sum(1 for _, typ, _ in top_level_boxes(data) if typ == "emsg"))
        return
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    moofs = [off for off, typ, _ in top_level_boxes(data) if typ == "moof"]
    if len(moofs) < 2:
        sys.exit(f"need ≥2 moof boxes, found {len(moofs)}")

    scte = "urn:scte:scte35:2013:bin"
    ev1 = emsg_v1(scte, "", 90000, 2 * 90000, 4 * 90000, 1,
                  splice_section(0x05, splice_insert(4001, 2 * 90000, 4 * 90000)))
    ev2 = emsg_v0("https://aomedia.org/emsg/ID3", "", 90000, 0, 0xFFFFFFFF, 2,
                  b"ID3fake-tag-payload")
    ev3 = emsg_v1(scte, "", 90000, 6 * 90000, 4 * 90000, 3,
                  splice_section(0x06, time_signal(6 * 90000),
                                 segmentation_descriptor(7001, 0x30, 4 * 90000)))

    out = data[:moofs[0]] + ev1 + ev2 + data[moofs[0]:moofs[1]] + ev3 + data[moofs[1]:]
    open(dst, "wb").write(out)
    print(f"inserted 3 emsg boxes before moofs at {moofs[0]} and {moofs[1]}")


if __name__ == "__main__":
    main()
