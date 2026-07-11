#!/usr/bin/env bash
# lib/gaps.sh — timeline gap fixtures for gap-detection testing
# Sourced by generate.sh; uses helpers from lib/helpers.sh.
#
# Video gaps are made by dropping frames with select + -fps_mode passthrough,
# which preserves the surviving timestamps: the muxer stretches the sample
# before each hole to cover it, exactly how real capture drops and recording
# interruptions land in stts. Coverage gaps are made by giving one track a
# shorter source than the other.

RES="$DEFAULT_RESOLUTION"
FPS="$DEFAULT_FPS"
CRF="$DEFAULT_CRF"
ABR="$DEFAULT_AUDIO_BITRATE"
DUR="$DEFAULT_DURATION"

_gaps_enabled() { fixture_enabled gaps "$1"; }

if _gaps_enabled video_gap; then
  gs=$(fixture_get gaps video_gap gap_start 4)
  ge=$(fixture_get gaps video_gap gap_end 6)
  ff video_gap \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src "$DUR")" \
    -vf "select='not(between(t,${gs},${ge}))'" -fps_mode passthrough \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -b:a "$ABR"
fi

if _gaps_enabled video_gap_multi; then
  ff video_gap_multi \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src "$DUR")" \
    -vf "select='not(between(t,2,3)+between(t,6,8))'" -fps_mode passthrough \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -b:a "$ABR"
fi

if _gaps_enabled audio_ends_early; then
  adur=$(fixture_get gaps audio_ends_early audio_duration 7)
  ff audio_ends_early \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src "$adur")" \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -b:a "$ABR"
fi

if _gaps_enabled video_ends_early; then
  vdur=$(fixture_get gaps video_ends_early video_duration 7)
  ff video_ends_early \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$vdur")" \
    -f lavfi -i "$(audio_src "$DUR")" \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -b:a "$ABR"
fi

if _gaps_enabled video_gap_many; then
  dur=$(fixture_get gaps video_gap_many duration 60)
  # Drop the last 0.5s of every 2s period: one stretched sample every 2s,
  # ~dur/2 gaps total. Audio is trimmed to the video's effective end so the
  # file exercises many duration gaps without a coverage finding.
  adur=$(python3 -c "print($dur - 0.5)")
  ff video_gap_many \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$dur")" \
    -f lavfi -i "$(audio_src "$adur")" \
    -vf "select='lt(mod(t,2),1.5)'" -fps_mode passthrough \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -b:a "$ABR"
fi

if _gaps_enabled gap_combo; then
  # One of everything: a mid-file video gap plus audio that ends early.
  ff gap_combo \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src 7)" \
    -vf "select='not(between(t,4,6))'" -fps_mode passthrough \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -b:a "$ABR"
fi
