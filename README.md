# mp4-fixtures

![Screenshot](screenshot.png)

A configurable test fixture generator for MP4 files, built to support [Video Commander](https://video-commander.com) testing.

Generates a comprehensive library of MP4 (or MOV/MKV) test files covering codecs, resolutions, frame rates, audio variants, container formats, metadata, and edge cases — all driven by a single `fixtures.toml` config.

## Requirements

- `ffmpeg` on your PATH (or set `ffmpeg_bin` in `fixtures.toml`)
  - Recommended: build from [ffmpeg-builder](https://github.com/video-commander/ffmpeg-builder) for a static binary with all codecs
  - **ffmpeg ≥ 7** for the HDR fixtures: older builds (e.g. Ubuntu's apt 6.1) cannot write the `mdcv`/`clli` colour boxes that HDR10 and Dolby Vision assert, so those recipes fail their self-verification. CI uses a pinned 8.1 static build.
- Python 3.8+ (3.11+ preferred for stdlib `tomllib`; older versions need `pip install tomli`)

## Quick start

```bash
git clone https://github.com/video-commander/mp4-fixtures
cd mp4-fixtures
chmod +x generate.sh
./generate.sh
```

Output goes to `./output/` by default.

## Releases

Tagging `fixtures-v*` runs `.github/workflows/release.yml`, which generates the full set on CI and publishes it as a release asset (`mp4-fixtures-<tag>.tar.zst`). Downstream test suites can download a pinned tag so their inputs stay byte-identical until the pin is bumped deliberately:

```bash
git tag fixtures-v1 && git push origin fixtures-v1
```

Note: `aac_he` requires an ffmpeg with `libfdk_aac` and is skipped on stock builds, including CI releases.

## Configuration

All configuration lives in `fixtures.toml`. The key sections:

### `[settings]`

```toml
[settings]
ffmpeg_bin    = "ffmpeg"   # path or binary name
output_dir    = "./output"
output_format = "mp4"      # mp4 | mov | mkv
```

### `[categories]`

Enable or disable entire fixture categories:

```toml
[categories]
codecs      = true
resolutions = true
frame_rates = true
audio       = true
container   = true
metadata    = true
edge_cases  = true
gaps        = true
subtitles   = true    # wvtt/ttml/embedded-caption fixtures need MP4Box
scte35      = true    # emsg/SCTE-35 splice markers; ffmpeg + python only
drm         = true
hdr         = true    # HDR10 + HLG; Dolby Vision needs dovi_tool + MP4Box
```

Some HDR and subtitle fixtures need extra tools on `PATH` and skip cleanly
when they're missing: Dolby Vision (`hevc_dolby_vision_81`) needs
[`dovi_tool`](https://github.com/quietvoid/dovi_tool) and GPAC's `MP4Box`;
HDR10+ (`hevc_hdr10plus`) needs
[`hdr10plus_tool`](https://github.com/quietvoid/hdr10plus_tool); the
bitstream-only fixture (`hevc_hdr10_bitstream_only`) needs `MP4Box`, because
ffmpeg's MP4 muxer would copy the VUI into a `colr` box and defeat it. HDR10,
HLG and `hevc_hdr10_sei_only_colr` need only ffmpeg. In the subtitles
category, `wvtt` and `ttml` need `MP4Box` (ffmpeg can't mux those formats
into MP4), and the embedded-caption fixtures (`cc_embedded`, `cc_dropout`)
need `MP4Box` too: no common tool authors CEA-608/708 SEIs, so
`lib/inject_cc.py` splices crafted A/53 "GA94" SEI NALs into a raw Annex-B
H.264 stream, which MP4Box then muxes (verified via ffprobe's A53 frame side
data). `tx3g_utf8` needs only ffmpeg. CI installs everything
(see `.github/workflows/release.yml`).

### `[defaults]`

Fallback values used by all fixtures unless overridden:

```toml
[defaults]
crf           = 23
audio_bitrate = "128k"
duration      = 10
resolution    = "1920x1080"
fps           = 30
```

### `[fixtures.<category>.<name>]`

Override specific parameters per fixture, or disable individual fixtures:

```toml
[fixtures.codecs.hevc_main]
enabled = true
crf     = 28

[fixtures.edge_cases.long_2hr]
enabled       = true
duration      = 7200
crf           = 40
audio_bitrate = "32k"
```

### `[[custom]]`

Add arbitrary fixtures without editing any script. `video_args` and `audio_args` are passed verbatim to FFmpeg:

```toml
[[custom]]
name       = "prores_422"
enabled    = true
video_args = "-c:v prores_ks -profile:v 2"
audio_args = "-c:a pcm_s16le"
duration   = 10

[[custom]]
name       = "low_bitrate_360p"
enabled    = true
video_args = "-c:v libx264 -crf 35 -vf scale=640:360"
audio_args = "-c:a aac -b:a 48k"
duration   = 30
```

## Using a different config file

```bash
./generate.sh --config path/to/my-config.toml
```

## Output format notes

`output_format` swaps the container extension globally (`mp4`, `mov`, or `mkv`). Codec compatibility is your responsibility — not all codecs mux into all containers. For example, `mov_text` subtitles require MP4/MOV; use `srt` for MKV.

## Fixture categories

| Category | What it generates |
|---|---|
| `codecs` | H.264 (baseline/main/high), HEVC, AV1, VP9 |
| `resolutions` | 360p, 480p, 720p, 1080p, 4K |
| `frame_rates` | 23.976, 24, 25, 29.97, 30, 50, 59.94, 60, VFR |
| `audio` | AAC-LC, AAC-HE, Opus, AC-3, 5.1, multi-track, audio-only, video-only |
| `container` | Fragmented fMP4, faststart, moov-at-end, edit list (elst) |
| `metadata` | Rotation (90/180/270), chapters, embedded subtitle track |
| `edge_cases` | Very short, 2-hour, truncated, B-frames, many fragments |
| `gaps` | Timeline gaps: dropped video frames (stretched samples), tracks ending early |
| `subtitles` | Subtitle tracks in all three MP4 carriages (tx3g/mov_text with UTF-8 + multi-line cues, WebVTT with cue settings, TTML/stpp) plus embedded CEA-608/708 caption SEIs — full coverage and a dropout variant (needs `MP4Box`) |
| `scte35` | Fragmented MP4 with `emsg` event messages: SCTE-35 splice_insert (out-of-network + auto-return break) and time_signal with a segmentation descriptor, plus a non-SCTE ID3 event (`lib/inject_emsg.py` hand-builds the boxes) |
| `drm` | CENC-encrypted (cenc-aes-ctr, stable KID/key), plus a deliberate tenc-vs-pssh KID mismatch |
| `hdr` | HEVC HDR10 (PQ) and HLG with real colr/mdcv/clli ISOBMFF boxes; HDR10 with signalling only in the bitstream (VUI/SEI, no colour boxes; needs `MP4Box`); HDR10 with a colr box but SEI-only static metadata (the typical ffmpeg remux profile); HDR10+ with ST 2094-40 dynamic-metadata SEI (needs `hdr10plus_tool`); and Dolby Vision 8.1 (single-layer, HDR10-compatible; needs `dovi_tool` + `MP4Box`). Fixtures needing missing tools skip cleanly |

## Adding a new category

1. Create `lib/mycat.sh` (source `lib/helpers.sh` functions — `ff`, `fixture_enabled`, `fixture_get`)
2. Add `mycat = true` under `[categories]` in `fixtures.toml`
3. Add `[fixtures.mycat.*]` entries as needed
4. `generate.sh` picks it up automatically via `run_category mycat`

## Log

Each run writes a full log to `$output_dir/generate.log`. Check it for skipped fixtures (codec not available) vs actual failures.
