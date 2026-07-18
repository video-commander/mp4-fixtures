#!/usr/bin/env bash
# lib/subtitles.sh — subtitle-track and embedded-caption fixtures
# Sourced by generate.sh; uses helpers from lib/helpers.sh.
#
# Three subtitle carriage formats plus CEA-608/708 embedded captions:
#   tx3g_utf8   3GPP timed text (mov_text) with multi-line + non-ASCII cues;
#               needs only ffmpeg. (metadata.sh's subtitle_track is the plain
#               ASCII variant — this one exercises UTF-8 and line breaks.)
#   wvtt        WebVTT-in-MP4 (ISO 14496-30) with a cue-settings block;
#               ffmpeg can't mux wvtt into MP4, so MP4Box imports the .vtt.
#   ttml        TTML/IMSC1 (stpp) — one XML document per sample carrying its
#               own cue times; MP4Box imports the .ttml.
#   cc_embedded CEA-608 + CEA-708 caption SEIs (A/53 "GA94") in the video
#               bitstream — no subtitle track at all. No common tool authors
#               these, so lib/inject_cc.py splices crafted SEI NALs into a raw
#               Annex-B H.264 stream before MP4Box muxes it.
#   cc_dropout  Same, but every Nth frame's SEI is omitted — caption dropouts
#               that continuity checks must flag.
#
# All cues end by 7.9s so the fixtures stay clean at the CI duration (8s).
# MP4Box-dependent fixtures skip cleanly when it's missing.

RES="$DEFAULT_RESOLUTION"
FPS="$DEFAULT_FPS"
CRF="$DEFAULT_CRF"
ABR="$DEFAULT_AUDIO_BITRATE"
DUR="$DEFAULT_DURATION"

_subs_enabled() { fixture_enabled subtitles "$1"; }
_subs_have_mp4box() { command -v MP4Box >/dev/null 2>&1; }

# ── Cue sources ───────────────────────────────────────────────────────────────
# Same content in all three formats: a plain cue, a two-line cue, and a
# UTF-8 cue (em dash + Japanese), timed 1.5–3 / 4–6.5 / 7–7.9 seconds.

_SUBS_SRT="$(mktemp /tmp/fixtures_subs_XXXXXX.srt)"
cat > "$_SUBS_SRT" <<'EOF'
1
00:00:01,500 --> 00:00:03,000
Hello there.

2
00:00:04,000 --> 00:00:06,500
Two lines here,
second line.

3
00:00:07,000 --> 00:00:07,900
Final cue — こんにちは.
EOF

_SUBS_VTT="$(mktemp /tmp/fixtures_subs_XXXXXX.vtt)"
cat > "$_SUBS_VTT" <<'EOF'
WEBVTT

00:00:01.500 --> 00:00:03.000 line:85%
Hello there.

00:00:04.000 --> 00:00:06.500
Two lines here,
second line.

00:00:07.000 --> 00:00:07.900
Final cue — こんにちは.
EOF

_SUBS_TTML="$(mktemp /tmp/fixtures_subs_XXXXXX.ttml)"
cat > "$_SUBS_TTML" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttp="http://www.w3.org/ns/ttml#parameter" ttp:frameRate="25" xml:lang="en">
  <body>
    <div>
      <p begin="00:00:01.500" end="00:00:03.000">Hello there.</p>
      <p begin="00:00:04.000" end="00:00:06.500">Two lines here,<br/>second line.</p>
      <p begin="7s" dur="0.9s">Final cue — こんにちは.</p>
    </div>
  </body>
</tt>
EOF

# ── Self-verification ─────────────────────────────────────────────────────────

# _subs_verify_tag <out> <fourcc>
# Asserts the sample-entry fourcc landed in the container. Checked across all
# streams because ffprobe classifies GPAC-muxed wvtt as a data stream.
_subs_verify_tag() {
  local out="$1" want="$2" tags
  # Captured to a variable first: piping ffprobe straight into grep -q makes
  # it exit 141 under pipefail when grep closes the pipe early.
  tags=$(ffprobe -hide_banner -loglevel error \
    -show_entries stream=codec_tag_string -of default=nw=1:nk=1 "$out" 2>>"$LOG")
  if ! printf '%s\n' "$tags" | grep -qw "$want"; then
    log "  FAILED (no ${want} sample entry in output)"
    rm -f "$out"
    return 1
  fi
  return 0
}

# _subs_verify_cc <out>
# Asserts ffmpeg's decoder surfaces A53 caption side data on early frames.
_subs_verify_cc() {
  local out="$1" sd
  sd=$(ffprobe -hide_banner -loglevel error -select_streams v:0 \
    -read_intervals "%+#5" -show_frames \
    -show_entries frame_side_data_list=side_data_type -of default=nw=1:nk=1 \
    "$out" 2>>"$LOG")
  if ! printf '%s\n' "$sd" | grep -q "A53"; then
    log "  FAILED (no A53 caption side data on decoded frames)"
    rm -f "$out"
    return 1
  fi
  return 0
}

# _subs_cc_raw <dst> — video-only Annex-B H.264 elementary stream.
_subs_cc_raw() {
  "$FFMPEG" -hide_banner -loglevel error \
    -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
    -c:v libx264 -crf "$CRF" -f h264 -y "$1" 2>>"$LOG"
}

# ── Subtitle tracks ───────────────────────────────────────────────────────────

if _subs_enabled tx3g_utf8; then
  _label=tx3g_utf8
  out="${OUTPUT_DIR}/${_label}.${EXT}"
  log "→ $_label"
  if "$FFMPEG" -hide_banner -loglevel error \
      -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
      -f lavfi -i "$(audio_src "$DUR")" \
      -i "$_SUBS_SRT" -map 0:v -map 1:a -map 2:s \
      -c:v libx264 -crf "$CRF" \
      -c:a aac -b:a "$ABR" \
      -c:s mov_text -metadata:s:s:0 language=eng \
      -y "$out" 2>>"$LOG"; then
    _subs_verify_tag "$out" tx3g && log "  OK  →  $out"
  else
    log "  FAILED (see $LOG)"
    rm -f "$out"
  fi
fi

for _fmt in wvtt ttml; do
  if _subs_enabled "$_fmt"; then
    if ! _subs_have_mp4box; then
      log "→ $_fmt"
      log "  SKIP (needs MP4Box on PATH)"
    else
      _label="$_fmt"
      out="${OUTPUT_DIR}/${_label}.${EXT}"
      base="$(mktemp /tmp/fixtures_subbase_XXXXXX.mp4)"
      src="$_SUBS_VTT"; tag="wvtt"
      if [[ "$_fmt" == "ttml" ]]; then src="$_SUBS_TTML"; tag="stpp"; fi
      log "→ $_label"
      if "$FFMPEG" -hide_banner -loglevel error \
          -f lavfi -i "$(video_src "$RES" "$FPS" "$DUR")" \
          -c:v libx264 -crf "$CRF" -y "$base" 2>>"$LOG" \
        && MP4Box -quiet -add "$base" -add "${src}:lang=en" -new "$out" >>"$LOG" 2>&1; then
        _subs_verify_tag "$out" "$tag" && log "  OK  →  $out"
      else
        log "  FAILED (see $LOG)"
        rm -f "$out"
      fi
      rm -f "$base"
    fi
  fi
done

# ── Embedded CEA-608/708 captions ─────────────────────────────────────────────

for _cc in cc_embedded cc_dropout; do
  if _subs_enabled "$_cc"; then
    if ! _subs_have_mp4box; then
      log "→ $_cc"
      log "  SKIP (needs MP4Box on PATH)"
    else
      _label="$_cc"
      out="${OUTPUT_DIR}/${_label}.${EXT}"
      raw="$(mktemp /tmp/fixtures_cc_XXXXXX.h264)"
      injected="$(mktemp /tmp/fixtures_ccsei_XXXXXX.h264)"
      skip=0
      if [[ "$_cc" == "cc_dropout" ]]; then
        skip=$(fixture_get subtitles cc_dropout skip_every 7)
      fi
      log "→ $_label"
      if _subs_cc_raw "$raw" \
        && python3 "$SCRIPT_DIR/lib/inject_cc.py" "$raw" "$injected" "$skip" >>"$LOG" 2>&1 \
        && MP4Box -quiet -add "${injected}:fps=${FPS}" -new "$out" >>"$LOG" 2>&1; then
        _subs_verify_cc "$out" && log "  OK  →  $out"
      else
        log "  FAILED (see $LOG)"
        rm -f "$out"
      fi
      rm -f "$raw" "$injected"
    fi
  fi
done

rm -f "$_SUBS_SRT" "$_SUBS_VTT" "$_SUBS_TTML"
