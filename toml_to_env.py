#!/usr/bin/env python3
"""
toml_to_env.py — parse fixtures.toml and emit shell-sourceable exports.
Usage: eval "$(python3 toml_to_env.py fixtures.toml)"
Requires Python 3.11+ (tomllib stdlib) or Python 3.8+ with `pip install tomli`.
"""

import sys
import json
import os

def load_toml(path):
    try:
        import tomllib
        with open(path, "rb") as f:
            return tomllib.load(f)
    except ImportError:
        pass
    try:
        import tomli
        with open(path, "rb") as f:
            return tomli.load(f)
    except ImportError:
        print("ERROR: Python < 3.11 detected and tomli is not installed.", file=sys.stderr)
        print("Run: pip install tomli", file=sys.stderr)
        sys.exit(1)

def shell_safe(value):
    """Escape a value for single-quote shell export."""
    return str(value).replace("'", "'\\''")

def emit(key, value):
    print(f"export {key}='{shell_safe(value)}'")

def main():
    config_path = sys.argv[1] if len(sys.argv) > 1 else "fixtures.toml"
    if not os.path.exists(config_path):
        print(f"ERROR: config file not found: {config_path}", file=sys.stderr)
        sys.exit(1)

    cfg = load_toml(config_path)

    # [settings]
    settings = cfg.get("settings", {})
    emit("FFMPEG_BIN",      settings.get("ffmpeg_bin", "ffmpeg"))
    emit("OUTPUT_DIR",      settings.get("output_dir", "./output"))
    emit("OUTPUT_FORMAT",   settings.get("output_format", "mp4"))

    # [categories]
    cats = cfg.get("categories", {})
    for cat in ["codecs", "resolutions", "frame_rates", "audio", "container", "metadata", "edge_cases", "hdr"]:
        val = "1" if cats.get(cat, True) else "0"
        emit(f"CAT_{cat.upper()}", val)

    # [defaults]
    defaults = cfg.get("defaults", {})
    emit("DEFAULT_CRF",           defaults.get("crf", 23))
    emit("DEFAULT_AUDIO_BITRATE", defaults.get("audio_bitrate", "128k"))
    emit("DEFAULT_DURATION",      defaults.get("duration", 10))
    emit("DEFAULT_RESOLUTION",    defaults.get("resolution", "1920x1080"))
    emit("DEFAULT_FPS",           defaults.get("fps", 30))

    # [fixtures.*.*] — emit as JSON blob, parsed per-lib
    fixtures = cfg.get("fixtures", {})
    emit("FIXTURES_JSON", json.dumps(fixtures))

    # [[custom]]
    custom = cfg.get("custom", [])
    emit("CUSTOM_JSON", json.dumps(custom))

if __name__ == "__main__":
    main()
