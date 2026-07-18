#!/usr/bin/env bash
# generate.sh — mp4-fixtures orchestrator
# Usage: ./generate.sh [--config path/to/fixtures.toml]
#
# Reads fixtures.toml (or --config override), sources parsed env vars,
# then delegates to each lib/*.sh category script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Parse args ────────────────────────────────────────────────────────────────
CONFIG="$SCRIPT_DIR/fixtures.toml"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: ./generate.sh [--config path/to/fixtures.toml]"
      exit 0 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ ! -f "$CONFIG" ]]; then
  echo "Error: config file not found: $CONFIG" >&2
  exit 1
fi

# ── Load TOML config into env ─────────────────────────────────────────────────
eval "$(python3 "$SCRIPT_DIR/toml_to_env.py" "$CONFIG")"

# ── Setup ─────────────────────────────────────────────────────────────────────
mkdir -p "$OUTPUT_DIR"
LOG="$OUTPUT_DIR/generate.log"
: > "$LOG"   # truncate log for this run

export FFMPEG="$FFMPEG_BIN"
export EXT="$OUTPUT_FORMAT"
export LOG

# Shared helpers available to all lib scripts
source "$SCRIPT_DIR/lib/helpers.sh"

log "=== mp4-fixtures generator ==="
log "Config:  $CONFIG"
log "Output:  $OUTPUT_DIR"
log "Format:  .$EXT"
log ""

# ── Run categories ────────────────────────────────────────────────────────────
run_category() {
  local name="$1"
  local script="$SCRIPT_DIR/lib/${name}.sh"
  local flag_var="CAT_$(echo "$name" | tr '[:lower:]' '[:upper:]')"   # e.g. CAT_CODECS

  if [[ "${!flag_var:-1}" == "0" ]]; then
    log "--- [$name] skipped (disabled in config) ---"
    return
  fi

  if [[ ! -f "$script" ]]; then
    log "--- [$name] skipped (lib/${name}.sh not found) ---"
    return
  fi

  log "--- [$name] ---"
  # shellcheck disable=SC1090
  source "$script"
}

run_category codecs
run_category resolutions
run_category frame_rates
run_category audio
run_category container
run_category metadata
run_category edge_cases
run_category gaps
run_category subtitles
run_category scte35
run_category drm
run_category hdr

# ── Custom fixtures ───────────────────────────────────────────────────────────
source "$SCRIPT_DIR/lib/custom.sh"

# ── Summary ───────────────────────────────────────────────────────────────────
log ""
log "=== Done ==="
log ""

TOTAL=$(find "$OUTPUT_DIR" -maxdepth 1 -name "*.${EXT}" | wc -l | tr -d ' ')
SIZE=$(du -sh "$OUTPUT_DIR"/*.${EXT} 2>/dev/null | awk '{sum+=$1} END{print sum}' || echo "?")

echo ""
echo "Generated $TOTAL files in $OUTPUT_DIR"
echo ""
find "$OUTPUT_DIR" -maxdepth 1 -name "*.${EXT}" -exec ls -lh {} \; \
  | awk '{print $5"\t"$9}' | sort -k2
echo ""
echo "Full log: $LOG"
