#!/usr/bin/env bash
# lib/helpers.sh — shared utilities sourced by generate.sh and all lib scripts.
# Not executed directly.

# ── Logging ───────────────────────────────────────────────────────────────────

log() {
  local msg="[$(date +%H:%M:%S)] $*"
  echo "$msg" | tee -a "$LOG"
}

# ── Fixture config lookup ─────────────────────────────────────────────────────
# fixture_get <category> <name> <key> [fallback]
# Reads from FIXTURES_JSON (set by toml_to_env.py).
# Falls back to DEFAULT_<KEY> env var, then the optional 4th arg.
fixture_get() {
  local cat="$1" name="$2" key="$3" fallback="${4:-}"
  local val
  val=$(python3 -c "
import json, os, sys
fixtures = json.loads(os.environ.get('FIXTURES_JSON', '{}'))
entry = fixtures.get('$cat', {}).get('$name', {})
val = entry.get('$key')
if val is None:
    sys.exit(1)
print(val)
" 2>/dev/null) && echo "$val" || {
    # fall back to DEFAULT_<KEY> env var
    local default_var="DEFAULT_$(echo "$key" | tr '[:lower:]' '[:upper:]')"
    echo "${!default_var:-$fallback}"
  }
}

# fixture_enabled <category> <name>
# Returns 0 (true) if the fixture is enabled, 1 if disabled.
fixture_enabled() {
  local cat="$1" name="$2"
  local val
  val=$(python3 -c "
import json, os, sys
fixtures = json.loads(os.environ.get('FIXTURES_JSON', '{}'))
entry = fixtures.get('$cat', {}).get('$name', {})
# default to enabled=true if key not present
print('1' if entry.get('enabled', True) else '0')
" 2>/dev/null) || val="1"
  [[ "$val" == "1" ]]
}

# ── FFmpeg runner ─────────────────────────────────────────────────────────────
# ff <label> <ffmpeg args...>
# Runs ffmpeg, logs result, skips silently on codec-not-found errors.
ff() {
  local label="$1"; shift
  local outfile="${OUTPUT_DIR}/${label}.${EXT}"
  log "→ $label"
  if "$FFMPEG" -hide_banner -loglevel error "$@" -y "$outfile" 2>>"$LOG"; then
    log "  OK  →  $outfile"
  else
    # Check if it's a codec availability issue vs a real error
    if grep -q "Unknown encoder\|Encoder .* not found\|No such encoder" "$LOG" 2>/dev/null; then
      log "  SKIP (codec not available in this ffmpeg build)"
    else
      log "  FAILED (see $LOG)"
    fi
    rm -f "$outfile"
  fi
}

# ── Source generators ─────────────────────────────────────────────────────────
# These produce -f lavfi source strings.

video_src() {
  local res="${1:-$DEFAULT_RESOLUTION}"
  local fps="${2:-$DEFAULT_FPS}"
  local dur="${3:-$DEFAULT_DURATION}"
  echo "testsrc2=size=${res}:rate=${fps}:duration=${dur}"
}

audio_src() {
  local dur="${1:-$DEFAULT_DURATION}"
  local freq="${2:-1000}"
  echo "sine=frequency=${freq}:duration=${dur}"
}
