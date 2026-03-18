#!/usr/bin/env bash
# lib/resolutions.sh — resolution variant fixtures
# Sourced by generate.sh; uses helpers from lib/helpers.sh.

_res_fixture() {
  local name="$1"
  fixture_enabled resolutions "$name" || { log "  skip: $name (disabled)"; return; }
  local res;  res=$(fixture_get resolutions "$name" resolution)
  local dur;  dur=$(fixture_get resolutions "$name" duration)
  local fps;  fps=$(fixture_get resolutions "$name" fps)
  local crf;  crf=$(fixture_get resolutions "$name" crf)
  ff "$name" \
    -f lavfi -i "$(video_src "$res" "$fps" "$dur")" \
    -f lavfi -i "$(audio_src "$dur")" \
    -c:v libx264 -crf "$crf" \
    -c:a aac -b:a "$DEFAULT_AUDIO_BITRATE" \
    -t "$dur"
}

_res_fixture r360p
_res_fixture r480p
_res_fixture r720p
_res_fixture r1080p
_res_fixture r4k
