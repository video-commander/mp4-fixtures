#!/usr/bin/env bash
# lib/container.sh — container variant fixtures
# Sourced by generate.sh; uses helpers from lib/helpers.sh.

DUR="$DEFAULT_DURATION"
RES="$DEFAULT_RESOLUTION"
FPS="$DEFAULT_FPS"
CRF="$DEFAULT_CRF"
ABR="$DEFAULT_AUDIO_BITRATE"

_container_enabled() { fixture_enabled container "$1"; }

if _container_enabled fragmented_fmp4; then
  ff fragmented_fmp4 \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src "$DUR")" \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -b:a "$ABR" \
    -movflags frag_keyframe+empty_moov+default_base_moof \
    -t "$DUR"
fi

if _container_enabled faststart; then
  ff faststart \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src "$DUR")" \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -b:a "$ABR" \
    -movflags +faststart \
    -t "$DUR"
fi

if _container_enabled moov_at_end; then
  ff moov_at_end \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src "$DUR")" \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -b:a "$ABR" \
    -t "$DUR"
    # No -movflags faststart: moov ends up at the end by default
fi

if _container_enabled edit_list; then
  ff edit_list \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src "$DUR")" \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -b:a "$ABR" \
    -video_track_timescale 90000 \
    -t "$DUR"
fi
