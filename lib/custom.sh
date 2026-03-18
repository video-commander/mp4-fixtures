#!/usr/bin/env bash
# lib/custom.sh — runs [[custom]] fixtures from fixtures.toml
# Sourced by generate.sh after all category scripts.

CUSTOM_COUNT=$(python3 -c "
import json, os
customs = json.loads(os.environ.get('CUSTOM_JSON', '[]'))
print(len(customs))
")

if [[ "$CUSTOM_COUNT" -eq 0 ]]; then
  return 0
fi

log "--- [custom] ---"

python3 - <<'PYEOF'
import json, os, sys

customs = json.loads(os.environ.get('CUSTOM_JSON', '[]'))
output_dir = os.environ.get('OUTPUT_DIR', './output')
ext = os.environ.get('OUTPUT_FORMAT', 'mp4')
default_dur = os.environ.get('DEFAULT_DURATION', '10')
default_res = os.environ.get('DEFAULT_RESOLUTION', '1920x1080')
default_fps = os.environ.get('DEFAULT_FPS', '30')

for c in customs:
    if not c.get('enabled', True):
        continue
    name = c.get('name')
    if not name:
        print(f"[custom] skipping entry with no name", file=sys.stderr)
        continue
    print(f"CUSTOM_NAME={name}")
    print(f"CUSTOM_VIDEO_ARGS={c.get('video_args', '-c:v libx264 -crf 23')}")
    print(f"CUSTOM_AUDIO_ARGS={c.get('audio_args', '-c:a aac -b:a 128k')}")
    print(f"CUSTOM_DUR={c.get('duration', default_dur)}")
    print(f"CUSTOM_RES={c.get('resolution', default_res)}")
    print(f"CUSTOM_FPS={c.get('fps', default_fps)}")
    print("---")
PYEOF

# Re-run python to get entries as individual shell blocks
while IFS= read -r line; do
  [[ "$line" == "---" ]] && {
    # Run the accumulated fixture
    log "→ $CUSTOM_NAME (custom)"
    outfile="${OUTPUT_DIR}/${CUSTOM_NAME}.${EXT}"
    # shellcheck disable=SC2086
    if "$FFMPEG" -hide_banner -loglevel error \
      -f lavfi -i "lavfi:testsrc2=size=${CUSTOM_RES}:rate=${CUSTOM_FPS}:duration=${CUSTOM_DUR}" \
      -f lavfi -i "lavfi:sine=frequency=1000:duration=${CUSTOM_DUR}" \
      $CUSTOM_VIDEO_ARGS \
      $CUSTOM_AUDIO_ARGS \
      -t "$CUSTOM_DUR" \
      -y "$outfile" 2>>"$LOG"; then
      log "  OK  →  $outfile"
    else
      log "  FAILED (see $LOG)"
      rm -f "$outfile"
    fi
    continue
  }
  # Parse key=value
  key="${line%%=*}"
  val="${line#*=}"
  export "$key=$val"
done < <(python3 - <<'PYEOF'
import json, os, sys

customs = json.loads(os.environ.get('CUSTOM_JSON', '[]'))
default_dur = os.environ.get('DEFAULT_DURATION', '10')
default_res = os.environ.get('DEFAULT_RESOLUTION', '1920x1080')
default_fps = os.environ.get('DEFAULT_FPS', '30')

for c in customs:
    if not c.get('enabled', True):
        continue
    name = c.get('name')
    if not name:
        continue
    print(f"CUSTOM_NAME={name}")
    print(f"CUSTOM_VIDEO_ARGS={c.get('video_args', '-c:v libx264 -crf 23')}")
    print(f"CUSTOM_AUDIO_ARGS={c.get('audio_args', '-c:a aac -b:a 128k')}")
    print(f"CUSTOM_DUR={c.get('duration', default_dur)}")
    print(f"CUSTOM_RES={c.get('resolution', default_res)}")
    print(f"CUSTOM_FPS={c.get('fps', default_fps)}")
    print("---")
PYEOF
)
