#!/usr/bin/env bash
# lib/drm.sh — CENC-encrypted fixtures for DRM inspection testing.
# Sourced by generate.sh; uses helpers from lib/helpers.sh.
#
# drm_cenc: video+audio encrypted with cenc-aes-ctr. ffmpeg writes the full
# sinf chain (encv/enca, frma, schm, tenc) but no pssh box — the shape of
# content whose license info is delivered out of band (e.g. in a DASH
# manifest).
#
# drm_cenc_kid_mismatch: drm_cenc plus an injected v1 Widevine pssh that
# advertises a DIFFERENT KID than tenc — the packaging bug where players
# can't match a license to the content. ffmpeg writes moov after mdat, so
# growing moov shifts no chunk offsets; the injector asserts that layout.
#
# The KID/key pair is fixture data, not a secret — it is deliberately
# stable so tests can assert on it.

RES="$DEFAULT_RESOLUTION"
FPS="$DEFAULT_FPS"
CRF="$DEFAULT_CRF"
ABR="$DEFAULT_AUDIO_BITRATE"
DUR="$DEFAULT_DURATION"

_drm_enabled() { fixture_enabled drm "$1"; }

DRM_KID="112233445566778899aabbccddeeff00"
DRM_KEY="00112233445566778899aabbccddeeff"
DRM_WRONG_KID="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

if _drm_enabled drm_cenc; then
  ff drm_cenc \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src "$DUR")" \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -b:a "$ABR" \
    -encryption_scheme cenc-aes-ctr \
    -encryption_kid "$DRM_KID" \
    -encryption_key "$DRM_KEY"
fi

if _drm_enabled drm_cenc_kid_mismatch; then
  if [[ ! -f "$OUTPUT_DIR/drm_cenc.$EXT" ]]; then
    log "→ drm_cenc_kid_mismatch"
    log "  SKIP (drm_cenc.$EXT not present; enable the drm_cenc fixture)"
  else
    log "→ drm_cenc_kid_mismatch"
    if python3 - "$OUTPUT_DIR/drm_cenc.$EXT" "$OUTPUT_DIR/drm_cenc_kid_mismatch.$EXT" "$DRM_WRONG_KID" <<'PYEOF' 2>>"$LOG"
import struct, sys

src, dst, wrong_kid_hex = sys.argv[1], sys.argv[2], sys.argv[3]

# v1 Widevine pssh: box-level KID list carrying the wrong KID, plus a
# minimal protobuf payload (field 3: provider) so payload decoding works.
system_id = bytes.fromhex("edef8ba979d64acea3c827dcd51d21ed")
wrong_kid = bytes.fromhex(wrong_kid_hex)
payload = bytes([0x1A, 0x0D]) + b"widevine_test"
body = (
    bytes([1, 0, 0, 0])            # FullBox: version 1, flags 0
    + system_id
    + struct.pack(">I", 1) + wrong_kid
    + struct.pack(">I", len(payload)) + payload
)
pssh = struct.pack(">I", 8 + len(body)) + b"pssh" + body

data = bytearray(open(src, "rb").read())

# Top-level box walk to locate moov and mdat.
pos, moov, mdat = 0, None, None
while pos + 8 <= len(data):
    size, typ = struct.unpack_from(">I4s", data, pos)
    if size == 1:
        size = struct.unpack_from(">Q", data, pos + 8)[0]
    elif size == 0:
        size = len(data) - pos
    if typ == b"moov":
        moov = (pos, size)
    elif typ == b"mdat":
        mdat = (pos, size)
    pos += size

assert moov is not None, "no moov box"
# Inserting into moov shifts every byte after it; stco offsets point into
# mdat, so mdat must precede moov (ffmpeg's default, non-faststart layout).
assert mdat is not None and mdat[0] < moov[0], "moov must follow mdat"

mpos, msize = moov
struct.pack_into(">I", data, mpos, msize + len(pssh))
data[mpos + 8 : mpos + 8] = pssh  # first child of moov
open(dst, "wb").write(bytes(data))
PYEOF
    then
      log "  OK  →  $OUTPUT_DIR/drm_cenc_kid_mismatch.$EXT"
    else
      log "  FAILED (see $LOG)"
      rm -f "$OUTPUT_DIR/drm_cenc_kid_mismatch.$EXT"
    fi
  fi
fi
