#!/usr/bin/env bash
# lib/hdr.sh — HDR fixture variants
# Sourced by generate.sh; uses helpers from lib/helpers.sh.
# Note: disabled by default in fixtures.toml (slow, large files).

ABR="$DEFAULT_AUDIO_BITRATE"

_hdr_enabled() { fixture_enabled hdr "$1"; }

if _hdr_enabled hevc_hdr10; then
  crf=$(fixture_get hdr hevc_hdr10 crf)
  res=$(fixture_get hdr hevc_hdr10 resolution)
  dur=$(fixture_get hdr hevc_hdr10 duration)
  fps=$(fixture_get hdr hevc_hdr10 fps)
  ff hevc_hdr10 \
    -f lavfi -i "$(video_src "$res" "$fps" "$dur")" \
    -f lavfi -i "$(audio_src "$dur")" \
    -c:v libx265 -preset fast -crf "$crf" \
    -pix_fmt yuv420p10le \
    -color_primaries bt2020 \
    -color_trc smpte2084 \
    -colorspace bt2020nc \
    -x265-params "hdr-opt=1:repeat-headers=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc:master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1):max-cll=1000,400" \
    -c:a aac -b:a "$ABR" \
    -t "$dur"
fi
