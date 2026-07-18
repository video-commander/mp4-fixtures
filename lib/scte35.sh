#!/usr/bin/env bash
# lib/scte35.sh — SCTE-35 / emsg event-message fixtures
# Sourced by generate.sh; uses helpers from lib/helpers.sh.
#
# No common tool authors SCTE-35 emsg boxes, so lib/inject_emsg.py inserts
# hand-built ones into a fragmented (default-base-is-moof) MP4, where adding
# top-level boxes can't break sample addressing:
#   before fragment 1: emsg v1 urn:scte:scte35:2013:bin — splice_insert,
#                      out-of-network at 2s with a 4s auto-return break —
#                      plus an emsg v0 ID3 event (non-SCTE passthrough)
#   before fragment 2: emsg v1 — time_signal at 6s with a Provider
#                      Advertisement Start segmentation descriptor (4s)
# Needs only ffmpeg + python3.

RES="$DEFAULT_RESOLUTION"
FPS="$DEFAULT_FPS"
CRF="$DEFAULT_CRF"
DUR="$DEFAULT_DURATION"

_scte35_enabled() { fixture_enabled scte35 "$1"; }

if _scte35_enabled scte35_emsg; then
  _label=scte35_emsg
  out="${OUTPUT_DIR}/${_label}.${EXT}"
  base="$(mktemp /tmp/fixtures_frag_XXXXXX.mp4)"
  log "→ $_label"
  # One keyframe (= one fragment) per second so the 2s/6s events land
  # before real fragment boundaries.
  if "$FFMPEG" -hide_banner -loglevel error \
      -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
      -c:v libx264 -crf "$CRF" -g "$FPS" \
      -movflags empty_moov+default_base_moof+frag_keyframe \
      -y "$base" 2>>"$LOG" \
    && python3 "$SCRIPT_DIR/lib/inject_emsg.py" "$base" "$out" >>"$LOG" 2>&1; then
    emsg_count=$(python3 "$SCRIPT_DIR/lib/inject_emsg.py" --count "$out" 2>>"$LOG")
    if [[ "$emsg_count" == "3" ]]; then
      log "  OK  →  $out"
    else
      log "  FAILED (expected 3 emsg boxes, found ${emsg_count:-0})"
      rm -f "$out"
    fi
  else
    log "  FAILED (see $LOG)"
    rm -f "$out"
  fi
  rm -f "$base"
fi
