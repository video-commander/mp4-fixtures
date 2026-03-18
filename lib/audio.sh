#!/usr/bin/env bash
# lib/audio.sh — audio variant fixtures
# Sourced by generate.sh; uses helpers from lib/helpers.sh.

DUR="$DEFAULT_DURATION"
RES="$DEFAULT_RESOLUTION"
FPS="$DEFAULT_FPS"
CRF="$DEFAULT_CRF"

_audio_enabled() { fixture_enabled audio "$1"; }

if _audio_enabled aac_lc; then
  bitrate=$(fixture_get audio aac_lc audio_bitrate)
  ff audio_aac_lc \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src "$DUR")" \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -b:a "$bitrate" \
    -t "$DUR"
fi

if _audio_enabled aac_he; then
  bitrate=$(fixture_get audio aac_he audio_bitrate)
  ff audio_aac_he \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src "$DUR")" \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -profile:a aac_he -b:a "$bitrate" \
    -t "$DUR"
fi

if _audio_enabled opus; then
  bitrate=$(fixture_get audio opus audio_bitrate)
  ff audio_opus \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src "$DUR")" \
    -c:v libx264 -crf "$CRF" \
    -c:a libopus -b:a "$bitrate" \
    -t "$DUR"
fi

if _audio_enabled ac3; then
  bitrate=$(fixture_get audio ac3 audio_bitrate)
  ff audio_ac3 \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src "$DUR")" \
    -c:v libx264 -crf "$CRF" \
    -c:a ac3 -b:a "$bitrate" \
    -t "$DUR"
fi

if _audio_enabled multichannel_51; then
  ff audio_multichannel_51 \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src "$DUR" 100)" \
    -f lavfi -i "$(audio_src "$DUR" 200)" \
    -f lavfi -i "$(audio_src "$DUR" 300)" \
    -f lavfi -i "$(audio_src "$DUR" 400)" \
    -f lavfi -i "$(audio_src "$DUR" 50)" \
    -f lavfi -i "$(audio_src "$DUR" 600)" \
    -filter_complex "[1][2][3][4][5][6]amerge=inputs=6,pan=5.1|c0=c0|c1=c1|c2=c2|c3=c3|c4=c4|c5=c5[aout]" \
    -map 0:v -map "[aout]" \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -b:a 320k \
    -t "$DUR"
fi

if _audio_enabled multi_track; then
  ff audio_multi_track \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src "$DUR" 440)" \
    -f lavfi -i "$(audio_src "$DUR" 880)" \
    -map 0:v -map 1:a -map 2:a \
    -c:v libx264 -crf "$CRF" \
    -c:a:0 aac -b:a:0 "$DEFAULT_AUDIO_BITRATE" \
    -c:a:1 aac -b:a:1 "$DEFAULT_AUDIO_BITRATE" \
    -metadata:s:a:0 language=eng -metadata:s:a:0 title="English" \
    -metadata:s:a:1 language=jpn -metadata:s:a:1 title="Japanese" \
    -t "$DUR"
fi

if _audio_enabled audio_only; then
  ff audio_only \
    -f lavfi -i "$(audio_src "$DUR")" \
    -c:a aac -b:a "$DEFAULT_AUDIO_BITRATE" \
    -t "$DUR"
fi

if _audio_enabled video_only; then
  ff video_only \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -c:v libx264 -crf "$CRF" -an \
    -t "$DUR"
fi
