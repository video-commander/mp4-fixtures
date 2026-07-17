#!/usr/bin/env bash
# lib/hdr.sh — HDR fixture variants
# Sourced by generate.sh; uses helpers from lib/helpers.sh.
#
# Enabled by default. HDR10, HLG and the sei-only-colr fixture need only
# ffmpeg; the bitstream-only fixture additionally needs MP4Box, HDR10+ needs
# hdr10plus_tool, and Dolby Vision needs dovi_tool + MP4Box — each skips
# cleanly if its extra tools are absent.
#
# These fixtures emit real colr / mdcv / clli ISOBMFF colour boxes, not just
# bitstream (VUI/SEI) signalling. ffmpeg only writes mdcv/clli from packet side
# data, which the libx265 wrapper does NOT export when the mastering metadata is
# passed through -x265-params. So we go two-step: encode a raw HEVC elementary
# stream carrying the SEI, then decode + re-encode it — the HEVC decoder
# surfaces the mastering-display / content-light SEI as frame side data, which
# flows through the second encode into the container as mdcv/clli (and colr from
# the VUI). A single-pass encode leaves the file with no colour boxes.

ABR="$DEFAULT_AUDIO_BITRATE"

_hdr_enabled() { fixture_enabled hdr "$1"; }

# _hdr_verify <out> <expected_transfer> [required side_data...]
# Confirms the file actually carries the colour signalling the recipe promises.
# ffmpeg can emit a perfectly valid MP4 with NO colour boxes (colr/mdcv/clli) —
# the exact silent failure a plain "did it produce a file" check misses — so we
# assert the transfer characteristic and any required side data (mdcv/clli/dvvC,
# surfaced by ffprobe as stream side_data). On mismatch, logs FAILED and deletes
# the output so the release/CI failure check catches it. Uses ffprobe only,
# which is always present alongside ffmpeg.
_hdr_verify() {
  local out="$1" want_trc="$2"; shift 2
  local trc sd want
  trc=$(ffprobe -hide_banner -loglevel error -select_streams v:0 \
    -show_entries stream=color_transfer -of default=nk=1:nw=1 "$out" 2>/dev/null)
  if [ "$trc" != "$want_trc" ]; then
    log "  FAILED (colour: color_transfer='$trc', expected '$want_trc' — colr box missing?)"
    rm -f "$out"
    return 1
  fi
  sd=$(ffprobe -hide_banner -loglevel error -select_streams v:0 \
    -show_entries stream_side_data=side_data_type -of default=nk=1:nw=1 "$out" 2>/dev/null)
  for want in "$@"; do
    if ! printf '%s\n' "$sd" | grep -qiF "$want"; then
      log "  FAILED (colour: missing '$want' — box not written)"
      rm -f "$out"
      return 1
    fi
  done
  return 0
}

# _hdr_boxes <file>
# Lists every ISOBMFF box type in the file (space-separated, sorted, unique)
# by walking the box tree with python — including inside stsd sample entries,
# where colr/mdcv/clli live. Lets ffmpeg-only fixtures assert box presence or
# absence without needing MP4Box.
_hdr_boxes() {
  python3 - "$1" <<'PY'
import struct, sys
CONTAINERS = {b'moov', b'trak', b'mdia', b'minf', b'stbl', b'dinf', b'edts',
              b'udta', b'mvex', b'moof', b'traf'}
SAMPLE_ENTRIES = {b'hvc1', b'hev1', b'avc1', b'dvh1', b'dvhe', b'av01', b'vp09', b'encv'}
def walk(buf, out):
    i, n = 0, len(buf)
    while i + 8 <= n:
        size, typ = struct.unpack('>I4s', buf[i:i+8]); hdr = 8
        if size == 1:
            if i + 16 > n: break
            size = struct.unpack('>Q', buf[i+8:i+16])[0]; hdr = 16
        elif size == 0:
            size = n - i
        if size < hdr or i + size > n: break
        out.add(typ)
        if typ in CONTAINERS:
            walk(buf[i+hdr:i+size], out)
        elif typ == b'stsd':                       # 4B version/flags + 4B count
            walk(buf[i+hdr+8:i+size], out)
        elif typ in SAMPLE_ENTRIES:                # 78B visual sample entry fields
            walk(buf[i+hdr+78:i+size], out)
        i += size
out = set()
walk(open(sys.argv[1], 'rb').read(), out)
print(' '.join(sorted(t.decode('latin1') for t in out)))
PY
}

# _hdr_frame_sd <file>
# Side-data types ffprobe surfaces on the first few decoded frames — where
# bitstream SEI (mastering display, content light, HDR10+) shows up. Reads
# several frames because with b-frames the decoder emits nothing for the
# first few packets.
_hdr_frame_sd() {
  ffprobe -hide_banner -loglevel error -select_streams v:0 \
    -show_entries frame_side_data=side_data_type -of default=nk=1:nw=1 \
    -read_intervals "%+#8" "$1" 2>/dev/null
}

# _hdr_stream_sd <file>
# Stream-level side-data types — container boxes (mdcv/clli/dvvC), never SEI.
_hdr_stream_sd() {
  ffprobe -hide_banner -loglevel error -select_streams v:0 \
    -show_entries stream_side_data=side_data_type -of default=nk=1:nw=1 "$1" 2>/dev/null
}

# _hdr_verify_sei_carried <out>
# Shared checks for the SEI-carrying fixtures: the bitstream must signal PQ
# (ffprobe reads the SPS VUI even with no colr box) and carry the
# mastering/content-light SEI (frame side data), while the container must NOT
# have mdcv/clli boxes (no static metadata in stream side data).
_hdr_verify_sei_carried() {
  local out="$1"
  local trc want
  trc=$(ffprobe -hide_banner -loglevel error -select_streams v:0 \
    -show_entries stream=color_transfer -of default=nk=1:nw=1 "$out" 2>/dev/null)
  if [ "$trc" != "smpte2084" ]; then
    log "  FAILED (colour: color_transfer='$trc', expected 'smpte2084' in bitstream)"
    rm -f "$out"
    return 1
  fi
  local frame_sd
  frame_sd=$(_hdr_frame_sd "$out")
  for want in "Mastering display metadata" "Content light level metadata"; do
    if ! printf '%s\n' "$frame_sd" | grep -qiF "$want"; then
      log "  FAILED (colour: '$want' SEI missing from bitstream)"
      rm -f "$out"
      return 1
    fi
  done
  # Captured to a variable first: piping ffprobe straight into grep -q makes
  # grep exit on the first match, ffprobe die with SIGPIPE, and the pipeline
  # fail under generate.sh's pipefail — exactly when it should succeed.
  local stream_sd
  stream_sd=$(_hdr_stream_sd "$out")
  if printf '%s\n' "$stream_sd" | grep -qi "Mastering display\|Content light"; then
    log "  FAILED (colour: container has mdcv/clli boxes — static metadata must be SEI-only)"
    rm -f "$out"
    return 1
  fi
  return 0
}

# _hdr_verify_bitstream_only <out>
# The inverse of _hdr_verify: HDR10 signalling must live in the bitstream
# (VUI + SEI) with the container fully silent — not even a colr box. Catches
# the failure mode where the muxer helpfully derives colour boxes from the
# bitstream, which would defeat the fixture.
_hdr_verify_bitstream_only() {
  local out="$1" boxes
  _hdr_verify_sei_carried "$out" || return 1
  boxes=$(_hdr_boxes "$out")
  if printf '%s\n' "$boxes" | grep -qwE "colr|mdcv|clli"; then
    log "  FAILED (colour: container has a colr/mdcv/clli box — should be bitstream-only)"
    rm -f "$out"
    return 1
  fi
  return 0
}

# _hdr_verify_sei_only_colr <out>
# colr box present, static metadata SEI-only: the container must have colr
# but NOT mdcv/clli, with the mastering/content-light SEI in the bitstream.
_hdr_verify_sei_only_colr() {
  local out="$1" boxes
  _hdr_verify_sei_carried "$out" || return 1
  boxes=$(_hdr_boxes "$out")
  if ! printf '%s\n' "$boxes" | grep -qw "colr"; then
    log "  FAILED (colour: colr box missing — ffmpeg no longer writes it on remux?)"
    rm -f "$out"
    return 1
  fi
  if printf '%s\n' "$boxes" | grep -qwE "mdcv|clli"; then
    log "  FAILED (colour: container has mdcv/clli — static metadata must be SEI-only)"
    rm -f "$out"
    return 1
  fi
  return 0
}

# _hdr_verify_hdr10plus <out>
# HDR10 base (PQ + static SEI, no mdcv/clli boxes) plus the ST 2094-40
# dynamic-metadata SEI ffprobe reports as HDR10+.
_hdr_verify_hdr10plus() {
  local out="$1" frame_sd
  _hdr_verify_sei_carried "$out" || return 1
  frame_sd=$(_hdr_frame_sd "$out")
  if ! printf '%s\n' "$frame_sd" | grep -qiF "SMPTE2094-40"; then
    log "  FAILED (colour: HDR10+ (ST 2094-40) SEI missing from bitstream)"
    rm -f "$out"
    return 1
  fi
  return 0
}

# _hdr10_raw <label> <raw_out>
# Single-pass encode of the shared HDR10 raw HEVC elementary stream: PQ/BT.2020
# VUI plus mastering-display (ST 2086) and MaxCLL/MaxFALL SEI, all in the
# bitstream. Reads crf/resolution/duration/fps from the fixture config. The
# caller has already logged the fixture label; this logs SKIP/FAILED itself
# and returns non-zero.
_hdr10_raw() {
  local label="$1" raw="$2"
  local crf res dur fps
  crf=$(fixture_get hdr "$label" crf)
  res=$(fixture_get hdr "$label" resolution)
  dur=$(fixture_get hdr "$label" duration)
  fps=$(fixture_get hdr "$label" fps)
  if ! "$FFMPEG" -hide_banner -loglevel error \
      -f lavfi -i "$(video_src "$res" "$fps" "$dur")" \
      -c:v libx265 -preset fast -crf "$crf" -pix_fmt yuv420p10le \
      -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc \
      -x265-params "hdr-opt=1:repeat-headers=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400" \
      -f hevc -y "$raw" 2>>"$LOG"; then
    if grep -q "Unknown encoder\|Encoder .* not found\|No such encoder" "$LOG" 2>/dev/null; then
      log "  SKIP (libx265 not available in this ffmpeg build)"
    else
      log "  FAILED (see $LOG)"
    fi
    rm -f "$raw"
    return 1
  fi
  return 0
}

# _hdr_hevc <label> <transfer> <encode_x265_params>
# transfer: a CICP transfer name (smpte2084 for HDR10, arib-std-b67 for HLG).
# encode_x265_params: extra x265 params for pass 1 (e.g. master-display/max-cll);
# may be empty.
_hdr_hevc() {
  local label="$1" trc="$2" xparams="$3"
  local crf res dur fps raw out
  crf=$(fixture_get hdr "$label" crf)
  res=$(fixture_get hdr "$label" resolution)
  dur=$(fixture_get hdr "$label" duration)
  fps=$(fixture_get hdr "$label" fps)
  raw="${OUTPUT_DIR}/${label}.hevc"
  out="${OUTPUT_DIR}/${label}.${EXT}"
  log "→ $label"

  local base_x265="repeat-headers=1:colorprim=bt2020:transfer=${trc}:colormatrix=bt2020nc"
  [ -n "$xparams" ] && base_x265="hdr-opt=1:${base_x265}:${xparams}"

  # Pass 1: raw HEVC elementary stream with the colour/mastering SEI.
  if ! "$FFMPEG" -hide_banner -loglevel error \
      -f lavfi -i "$(video_src "$res" "$fps" "$dur")" \
      -c:v libx265 -preset fast -crf "$crf" -pix_fmt yuv420p10le \
      -color_primaries bt2020 -color_trc "$trc" -colorspace bt2020nc \
      -x265-params "$base_x265" \
      -f hevc -y "$raw" 2>>"$LOG"; then
    if grep -q "Unknown encoder\|Encoder .* not found\|No such encoder" "$LOG" 2>/dev/null; then
      log "  SKIP (libx265 not available in this ffmpeg build)"
    else
      log "  FAILED (see $LOG)"
    fi
    rm -f "$raw"
    return
  fi

  # A mastering-display in the x265 params means this fixture must also carry
  # the mdcv/clli static-metadata boxes (HDR10); HLG has neither.
  local -a want_sd=()
  [ -n "$xparams" ] && want_sd=("Mastering display metadata" "Content light level metadata")

  # Pass 2: decode + re-encode so the mastering/content-light frame side data
  # is written as mdcv/clli boxes, and mux with audio.
  if "$FFMPEG" -hide_banner -loglevel error \
      -i "$raw" \
      -f lavfi -i "$(audio_src "$dur")" \
      -c:v libx265 -preset fast -crf "$crf" -pix_fmt yuv420p10le \
      -color_primaries bt2020 -color_trc "$trc" -colorspace bt2020nc \
      -c:a aac -b:a "$ABR" -tag:v hvc1 -t "$dur" \
      -y "$out" 2>>"$LOG"; then
    # ${arr[@]+…} guard: bash 3.2 under `set -u` treats an empty array
    # expansion as unbound, and HLG has no required side data.
    _hdr_verify "$out" "$trc" ${want_sd[@]+"${want_sd[@]}"} && log "  OK  →  $out"
  else
    log "  FAILED (see $LOG)"
    rm -f "$out"
  fi
  rm -f "$raw"
}

# HDR10: PQ transfer + BT.2020, with mastering-display (ST 2086) and
# content-light (MaxCLL/MaxFALL) metadata.
if _hdr_enabled hevc_hdr10; then
  _hdr_hevc hevc_hdr10 smpte2084 \
    "master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400"
fi

# HLG: hybrid log-gamma transfer + BT.2020. Display-agnostic, so no
# mastering-display / content-light metadata (just the colr box).
if _hdr_enabled hevc_hlg; then
  _hdr_hevc hevc_hlg arib-std-b67 ""
fi

# HDR10 signalled ONLY in the bitstream (SPS VUI + mastering/content-light
# SEI): the container has no colr, mdcv or clli boxes. Exercises inspectors'
# bitstream-fallback path — they must parse the elementary stream to detect
# HDR10 here. ffmpeg cannot produce this file: its MP4 muxer copies the VUI
# into a colr box on every mux, so the raw HEVC stream (the same pass-1 encode
# hevc_hdr10 uses) is muxed with MP4Box instead. Modern GPAC also derives
# colr/mdcv/clli from the bitstream on import, so those are explicitly
# suppressed with colr=none:hdr=none — container-only options that leave the
# VUI and SEI intact (unlike nosei, which would strip the payload we need).
# Video-only; skips cleanly if MP4Box is missing.
if _hdr_enabled hevc_hdr10_bitstream_only; then
  if ! command -v MP4Box >/dev/null 2>&1; then
    log "→ hevc_hdr10_bitstream_only"
    log "  SKIP (needs MP4Box on PATH)"
  else
    _label=hevc_hdr10_bitstream_only
    fps=$(fixture_get hdr "$_label" fps)
    raw="${OUTPUT_DIR}/${_label}.hevc"
    out="${OUTPUT_DIR}/${_label}.${EXT}"
    log "→ $_label"

    if _hdr10_raw "$_label" "$raw"; then
      if MP4Box -quiet -add "${raw}:fps=${fps}:colr=none:hdr=none" -new "$out" >>"$LOG" 2>&1; then
        _hdr_verify_bitstream_only "$out" && log "  OK  →  $out"
      else
        log "  FAILED (see $LOG)"
        rm -f "$out"
      fi
    fi
    rm -f "$raw"
  fi
fi

# HDR10 with a colr box but SEI-only static metadata — the most common
# real-world HDR10 profile: exactly what ffmpeg produces when remuxing a
# single-pass x265 HDR10 encode (colr derived from the VUI on stream copy, but
# no mdcv/clli, because the libx265 wrapper never exports mastering metadata
# passed via -x265-params as packet side data). Inspectors should show the
# mastering-display section sourced "from bitstream SEI". Needs only ffmpeg.
if _hdr_enabled hevc_hdr10_sei_only_colr; then
  _label=hevc_hdr10_sei_only_colr
  dur=$(fixture_get hdr "$_label" duration)
  raw="${OUTPUT_DIR}/${_label}.hevc"
  out="${OUTPUT_DIR}/${_label}.${EXT}"
  log "→ $_label"

  if _hdr10_raw "$_label" "$raw"; then
    if "$FFMPEG" -hide_banner -loglevel error \
        -i "$raw" \
        -f lavfi -i "$(audio_src "$dur")" \
        -c:v copy -c:a aac -b:a "$ABR" -tag:v hvc1 -t "$dur" \
        -y "$out" 2>>"$LOG"; then
      _hdr_verify_sei_only_colr "$out" && log "  OK  →  $out"
    else
      log "  FAILED (see $LOG)"
      rm -f "$out"
    fi
  fi
  rm -f "$raw"
fi

# HDR10+ (SMPTE ST 2094-40): HDR10 base layer plus per-frame dynamic-metadata
# SEI. hdr10plus_tool has no `generate` (unlike dovi_tool), only `inject` from
# the JSON format its `extract` emits — so the recipe synthesises a minimal
# conformant profile-B metadata JSON (one scene, static values, one entry per
# frame) and injects it into the shared raw HDR10 stream, then remuxes with
# ffmpeg (which also yields the typical colr-but-no-mdcv/clli container).
# Skips cleanly if hdr10plus_tool is missing.
if _hdr_enabled hevc_hdr10plus; then
  if ! command -v hdr10plus_tool >/dev/null 2>&1; then
    log "→ hevc_hdr10plus"
    log "  SKIP (needs hdr10plus_tool on PATH)"
  else
    _label=hevc_hdr10plus
    dur=$(fixture_get hdr "$_label" duration)
    fps=$(fixture_get hdr "$_label" fps)
    raw="${OUTPUT_DIR}/${_label}.hevc"
    plus="${OUTPUT_DIR}/${_label}.plus.hevc"
    meta="${OUTPUT_DIR}/${_label}.hdr10plus.json"
    out="${OUTPUT_DIR}/${_label}.${EXT}"
    frames=$(awk "BEGIN{printf \"%d\", $dur * $fps}")
    log "→ $_label"

    if _hdr10_raw "$_label" "$raw"; then
      python3 - "$frames" > "$meta" <<'PY'
import json, sys
n = int(sys.argv[1])
scene = {
    "AverageRGB": 1200,
    "BezierCurveData": {
        "Anchors": [102, 205, 307, 410, 512, 614, 717, 819, 922],
        "KneePointX": 205, "KneePointY": 205,
    },
    "LuminanceParameters": {
        "AverageRGB": 1200,
        "LuminanceDistributions": {
            "DistributionIndex": [1, 5, 10, 25, 50, 75, 90, 95, 99],
            "DistributionValues": [1000, 2000, 400, 4000, 14000, 30000, 50000, 3, 90],
        },
        "MaxScl": [17000, 16000, 14000],
    },
    "NumberOfWindows": 1, "SceneId": 0,
    "TargetedSystemDisplayMaximumLuminance": 400,
}
print(json.dumps({
    "JSONInfo": {"HDR10plusProfile": "B", "Version": "1.0"},
    "SceneInfo": [dict(scene, SceneFrameIndex=i, SequenceFrameIndex=i) for i in range(n)],
    "SceneInfoSummary": {"SceneFirstFrameIndex": [0], "SceneFrameNumbers": [n]},
    "ToolInfo": {"Tool": "mp4-fixtures", "Version": "1.0"},
}))
PY
      if hdr10plus_tool inject -i "$raw" -j "$meta" -o "$plus" >>"$LOG" 2>&1 \
         && "$FFMPEG" -hide_banner -loglevel error \
              -i "$plus" \
              -f lavfi -i "$(audio_src "$dur")" \
              -c:v copy -c:a aac -b:a "$ABR" -tag:v hvc1 -t "$dur" \
              -y "$out" 2>>"$LOG"; then
        _hdr_verify_hdr10plus "$out" && log "  OK  →  $out"
      else
        log "  FAILED (see $LOG)"
        rm -f "$out"
      fi
    fi
    rm -f "$raw" "$plus" "$meta"
  fi
fi

# Dolby Vision Profile 8.1 (single-layer, HDR10-compatible). Needs two extra
# tools beyond ffmpeg: dovi_tool (synthesises + injects the RPU) and GPAC's
# MP4Box (writes the dvvC configuration box). Skips cleanly if either is
# missing. The result is a real, playable DV stream: an HDR10 base layer
# (colr + mdcv/clli) plus a dvvC box advertising profile 8.1 / HDR10 base-layer
# compatibility, so non-DV players fall back to HDR10.
if _hdr_enabled hevc_dolby_vision_81; then
  if ! command -v dovi_tool >/dev/null 2>&1 || ! command -v MP4Box >/dev/null 2>&1; then
    log "→ hevc_dolby_vision_81"
    log "  SKIP (needs dovi_tool and MP4Box on PATH)"
  else
    _label=hevc_dolby_vision_81
    dur=$(fixture_get hdr "$_label" duration)
    fps=$(fixture_get hdr "$_label" fps)
    raw="${OUTPUT_DIR}/${_label}.hevc"
    rpu="${OUTPUT_DIR}/${_label}.rpu"
    dvhevc="${OUTPUT_DIR}/${_label}.dv.hevc"
    gen="${OUTPUT_DIR}/${_label}.dvgen.json"
    out="${OUTPUT_DIR}/${_label}.${EXT}"
    frames=$(awk "BEGIN{printf \"%d\", $dur * $fps}")
    log "→ $_label"

    if _hdr10_raw "$_label" "$raw"; then
      cat > "$gen" <<JSON
{ "cm_version": "V29", "profile": "8.1", "length": $frames,
  "level6": { "max_display_mastering_luminance": 1000, "min_display_mastering_luminance": 1,
              "max_content_light_level": 1000, "max_frame_average_light_level": 400 } }
JSON
      if dovi_tool generate -j "$gen" -o "$rpu" >>"$LOG" 2>&1 \
         && dovi_tool inject-rpu -i "$raw" -r "$rpu" -o "$dvhevc" >>"$LOG" 2>&1 \
         && MP4Box -quiet -add "${dvhevc}:dvp=8.1" -new "$out" >>"$LOG" 2>&1; then
        _hdr_verify "$out" smpte2084 "DOVI configuration record" \
          "Mastering display metadata" "Content light level metadata" \
          && log "  OK  →  $out"
      else
        log "  FAILED (see $LOG)"
        rm -f "$out"
      fi
    fi
    rm -f "$raw" "$rpu" "$dvhevc" "$gen"
  fi
fi
