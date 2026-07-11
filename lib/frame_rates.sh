#!/usr/bin/env bash
# lib/frame_rates.sh — frame rate variant fixtures
# Sourced by generate.sh; uses helpers from lib/helpers.sh.

_fps_fixture() {
  local name="$1"
  fixture_enabled frame_rates "$name" || { log "  skip: $name (disabled)"; return; }
  local fps; fps=$(fixture_get frame_rates "$name" fps)
  local dur; dur=$(fixture_get frame_rates "$name" duration)
  local res; res=$(fixture_get frame_rates "$name" resolution)
  local crf; crf=$(fixture_get frame_rates "$name" crf)
  ff "$name" \
    -f lavfi -i "$(video_src "$res" "$fps" "$dur")" \
    -f lavfi -i "$(audio_src "$dur")" \
    -c:v libx264 -crf "$crf" \
    -c:a aac -b:a "$DEFAULT_AUDIO_BITRATE" \
    -t "$dur"
}

_fps_fixture fps_2397
_fps_fixture fps_24
_fps_fixture fps_25
_fps_fixture fps_2997
_fps_fixture fps_30
_fps_fixture fps_50
_fps_fixture fps_5994
_fps_fixture fps_60

# VFR — not in TOML (always generated when category is enabled)
# Cumulative stagger: every 3rd inter-frame gap is 0.05s longer, keeping
# timestamps monotonic. /TB converts seconds to timebase ticks, and
# -fps_mode passthrough stops the muxer from flattening it back to CFR.
log "→ vfr"
ff vfr \
  -f lavfi -i "$(video_src "$DEFAULT_RESOLUTION" "$DEFAULT_FPS" "$DEFAULT_DURATION")" \
  -f lavfi -i "$(audio_src "$DEFAULT_DURATION")" \
  -c:v libx264 -crf "$DEFAULT_CRF" \
  -c:a aac -b:a "$DEFAULT_AUDIO_BITRATE" \
  -vf "setpts='PTS+floor(N/3)*0.05/TB'" -fps_mode passthrough \
  -t "$DEFAULT_DURATION"
