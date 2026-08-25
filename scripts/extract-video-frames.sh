#!/usr/bin/env bash
# Review a screen-recording the owner sent (e.g. a device test) by extracting
# frames you can actually look at. Reading an .mp4 directly isn't supported;
# frames are. Then open a spread of frames to reconstruct the user's scenario.
# Usage: ./extract-video-frames.sh <video.mp4> <out_dir> [fps]
# Example: ./extract-video-frames.sh ~/Downloads/screen.mp4 ./vid-frames 0.25
set -euo pipefail
VID="$1"; OUT="${2:-./vid-frames}"; FPS="${3:-0.25}"   # 0.25 = 1 frame / 4s
FF="${FF:-ffmpeg}"
mkdir -p "$OUT"
"$FF" -y -i "$VID" -vf "fps=${FPS},scale=540:-1" "$OUT/f%03d.jpg"
echo "frames -> $OUT ($(ls "$OUT" | wc -l))"
echo "Now Read a spread (first/middle/last) to reconstruct the scenario."
