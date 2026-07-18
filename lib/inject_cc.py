#!/usr/bin/env python3
"""Inject A/53 (GA94) caption SEI NALs into an Annex-B H.264 stream.

Inserts one SEI NAL carrying a CEA-608 field-1 pair and a CEA-708 pair
before each slice NAL (types 1/5). With --skip-every N, every Nth frame is
left uncaptioned to simulate dropouts.
"""
import sys

# SEI NAL: header 0x06, payload type 4 (user_data_registered_itu_t_t35),
# size 17: B5 (US) 0031 (ATSC) "GA94" 03 (cc_data), flags|cc_count=2,
# em_data, 608-f1 EOC pair, 708 packet-start pair, marker. Trailing 0x80.
GA94 = bytes([0xB5, 0x00, 0x31, 0x47, 0x41, 0x39, 0x34, 0x03,
              0x42, 0xFF,
              0xFC, 0x94, 0x2C,
              0xFF, 0x02, 0x21,
              0xFF])
SEI_NAL = b"\x00\x00\x00\x01" + bytes([0x06, 0x04, len(GA94)]) + GA94 + b"\x80"


def split_annexb(data: bytes):
    """Yields (start_code_offset, nal_start) for each NAL."""
    i, n = 0, len(data)
    starts = []
    while i < n - 3:
        if data[i] == 0 and data[i + 1] == 0:
            if data[i + 2] == 1:
                starts.append((i, i + 3))
                i += 3
                continue
            if data[i + 2] == 0 and i < n - 4 and data[i + 3] == 1:
                starts.append((i, i + 4))
                i += 4
                continue
        i += 1
    return starts


def main():
    src, dst = sys.argv[1], sys.argv[2]
    skip_every = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    data = open(src, "rb").read()
    starts = split_annexb(data)
    out = bytearray()
    prev = 0
    frame = 0
    for k, (sc, ns) in enumerate(starts):
        out += data[prev:sc]
        nal_type = data[ns] & 0x1F
        if nal_type in (1, 5):
            frame += 1
            if not (skip_every and frame % skip_every == 0):
                out += SEI_NAL
        prev = sc
    out += data[prev:]
    open(dst, "wb").write(out)
    print(f"{frame} slice NALs, SEI injected into "
          f"{frame - (frame // skip_every if skip_every else 0)}")


if __name__ == "__main__":
    main()
