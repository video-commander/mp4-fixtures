#!/usr/bin/env bash
# lib/metadata.sh — metadata & rotation fixture variants
# Sourced by generate.sh; uses helpers from lib/helpers.sh.

DUR="$DEFAULT_DURATION"
RES="$DEFAULT_RESOLUTION"
FPS="$DEFAULT_FPS"
CRF="$DEFAULT_CRF"
ABR="$DEFAULT_AUDIO_BITRATE"

_metadata_enabled() { fixture_enabled metadata "$1"; }

for DEG in 90 180 270; do
  name="rotation_${DEG}"
  if _metadata_enabled "$name"; then
    ff "$name" \
      -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
      -f lavfi -i "$(audio_src "$DUR")" \
      -c:v libx264 -crf "$CRF" \
      -c:a aac -b:a "$ABR" \
      -metadata:s:v rotate="$DEG" \
      -t "$DUR"
  fi
done

if _metadata_enabled chapters; then
  CHAP_DUR=$(fixture_get metadata chapters duration)
  CHAP_META="$(mktemp /tmp/fixtures_chapters_XXXXXX.txt)"
  cat > "$CHAP_META" <<EOF
;FFMETADATA1
[CHAPTER]
TIMEBASE=1/1000
START=0
END=10000
title=Intro
[CHAPTER]
TIMEBASE=1/1000
START=10000
END=20000
title=Middle
[CHAPTER]
TIMEBASE=1/1000
START=20000
END=30000
title=Outro
EOF
  ff chapters \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$CHAP_DUR")" \
    -f lavfi -i "$(audio_src "$CHAP_DUR")" \
    -i "$CHAP_META" \
    -map_metadata 2 \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -b:a "$ABR" \
    -t "$CHAP_DUR"
  rm -f "$CHAP_META"
fi

if _metadata_enabled subtitle_track; then
  NOSUBS_TMP="$(mktemp /tmp/fixtures_nosubs_XXXXXX.mp4)"
  SUBS_TMP="$(mktemp /tmp/fixtures_subs_XXXXXX.srt)"

  "$FFMPEG" -hide_banner -loglevel error \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -f lavfi -i "$(audio_src "$DUR")" \
    -c:v libx264 -crf "$CRF" \
    -c:a aac -b:a "$ABR" \
    -t "$DUR" -y "$NOSUBS_TMP" 2>>"$LOG"

  printf "1\n00:00:01,000 --> 00:00:04,000\nTest subtitle line one\n\n2\n00:00:05,000 --> 00:00:09,000\nTest subtitle line two\n" > "$SUBS_TMP"

  ff subtitle_track \
    -i "$NOSUBS_TMP" \
    -i "$SUBS_TMP" \
    -c:v copy -c:a copy -c:s mov_text \
    -metadata:s:s:0 language=eng

  rm -f "$NOSUBS_TMP" "$SUBS_TMP"
fi
