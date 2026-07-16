#!/usr/bin/env bash
# lib/hdr.sh — HDR fixture variants
# Sourced by generate.sh; uses helpers from lib/helpers.sh.
#
# Enabled by default. HDR10 and HLG need only ffmpeg; the Dolby Vision fixture
# additionally needs dovi_tool + MP4Box and skips cleanly if either is absent.
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
    crf=$(fixture_get hdr "$_label" crf)
    res=$(fixture_get hdr "$_label" resolution)
    dur=$(fixture_get hdr "$_label" duration)
    fps=$(fixture_get hdr "$_label" fps)
    raw="${OUTPUT_DIR}/${_label}.hevc"
    rpu="${OUTPUT_DIR}/${_label}.rpu"
    dvhevc="${OUTPUT_DIR}/${_label}.dv.hevc"
    gen="${OUTPUT_DIR}/${_label}.dvgen.json"
    out="${OUTPUT_DIR}/${_label}.${EXT}"
    frames=$(awk "BEGIN{printf \"%d\", $dur * $fps}")
    log "→ $_label"

    if "$FFMPEG" -hide_banner -loglevel error \
        -f lavfi -i "$(video_src "$res" "$fps" "$dur")" \
        -c:v libx265 -preset fast -crf "$crf" -pix_fmt yuv420p10le \
        -color_primaries bt2020 -color_trc smpte2084 -colorspace bt2020nc \
        -x265-params "hdr-opt=1:repeat-headers=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400" \
        -f hevc -y "$raw" 2>>"$LOG"; then
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
    else
      log "  FAILED (see $LOG)"
    fi
    rm -f "$raw" "$rpu" "$dvhevc" "$gen"
  fi
fi
