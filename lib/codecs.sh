#!/usr/bin/env bash
# lib/codecs.sh — codec variant fixtures
# Sourced by generate.sh; uses helpers from lib/helpers.sh.

_codec_fixture() {
  local name="$1"; shift
  fixture_enabled codecs "$name" || { log "  skip: $name (disabled)"; return; }
  local dur; dur=$(fixture_get codecs "$name" duration)
  local res; res=$(fixture_get codecs "$name" resolution)
  local fps; fps=$(fixture_get codecs "$name" fps)
  ff "$name" \
    -f lavfi -i "$(video_src "$res" "$fps" "$dur")" \
    -f lavfi -i "$(audio_src "$dur")" \
    "$@" -t "$dur"
}

_codec_fixture h264_baseline \
  -c:v libx264 -profile:v baseline -level 3.0 \
  -crf "$(fixture_get codecs h264_baseline crf)" \
  -c:a aac -b:a "$DEFAULT_AUDIO_BITRATE"

_codec_fixture h264_main \
  -c:v libx264 -profile:v main \
  -crf "$(fixture_get codecs h264_main crf)" \
  -c:a aac -b:a "$DEFAULT_AUDIO_BITRATE"

_codec_fixture h264_high \
  -c:v libx264 -profile:v high \
  -crf "$(fixture_get codecs h264_high crf)" \
  -c:a aac -b:a "$DEFAULT_AUDIO_BITRATE"

_codec_fixture hevc_main \
  -c:v libx265 -preset fast \
  -crf "$(fixture_get codecs hevc_main crf)" \
  -c:a aac -b:a "$DEFAULT_AUDIO_BITRATE"

_codec_fixture hevc_main10 \
  -c:v libx265 -preset fast -pix_fmt yuv420p10le \
  -crf "$(fixture_get codecs hevc_main10 crf)" \
  -c:a aac -b:a "$DEFAULT_AUDIO_BITRATE"

_codec_fixture av1 \
  -c:v libaom-av1 -cpu-used 8 -b:v 0 \
  -crf "$(fixture_get codecs av1 crf)" \
  -c:a aac -b:a "$DEFAULT_AUDIO_BITRATE"

_codec_fixture vp9 \
  -c:v libvpx-vp9 -b:v 0 \
  -crf "$(fixture_get codecs vp9 crf)" \
  -c:a libopus -b:a "$DEFAULT_AUDIO_BITRATE"
