#!/bin/bash
# Builds the README demo loop: hotkey, freeze, drag, annotate, copy.
#
# Frames are staged and captured one at a time rather than screen-recorded, so the timing is
# exact, nothing of the real desktop appears, and the result is reproducible.
#
# usage: scripts/make-demo-gif.sh [secondary|main]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPLAY_SPEC="${1:-secondary}"
CTL="$(cd "$ROOT" && swift build -c debug --show-bin-path)/tytoctl"
TMP="${TMPDIR:-/tmp}/tyto-gif"
OUT="$ROOT/out/demo.gif"
rm -rf "$TMP"; mkdir -p "$TMP" "$ROOT/out"

swiftc -O "$ROOT/scripts/stage.swift" -o "$TMP/stage" 2>/dev/null
swiftc -O "$ROOT/scripts/crop-screenshot.swift" -o "$TMP/crop" 2>/dev/null

"$TMP/stage" "$DISPLAY_SPEC" >/dev/null 2>&1 &
STAGE_PID=$!
cleanup() { "$CTL" cancel >/dev/null 2>&1 || true; kill "$STAGE_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 2

q() { "$CTL" "$@" >/dev/null; }
n=0
frame() {  # frame <hold-in-frames>  — repeat a frame to hold it on screen
  local shot; shot=$(printf "%03d" "$n")
  q snapshot "$TMP/raw-$shot.png" --display "$DISPLAY_SPEC"
  "$TMP/crop" "$TMP/raw-$shot.png" "$TMP/f-$shot.png" 1632 780 2752 1720 1100 688 >/dev/null
  for _ in $(seq 2 "${1:-1}"); do n=$((n+1)); cp "$TMP/f-$shot.png" "$TMP/f-$(printf '%03d' $n).png"; done
  n=$((n+1))
}

# 1. The desktop, before anything happens.
frame 6

# 2. Hotkey: the screen freezes and dims.
q capture --display "$DISPLAY_SPEC"
frame 3

# 3. The drag, as a selection growing to its final size.
for box in "1800 980 700 420" "1800 980 1400 820" "1800 980 2100 1180" "1800 980 2400 1350"; do
  q select $box
  frame 2
done
frame 3

# 4. Marks appearing one at a time.
q width thin
q color red; q tool rect;  q draw 1890 1055 2570 1145
frame 3
q color red; q tool arrow; q draw 3350 1230 3810 1440
frame 3
q color red; q width thick; q tool text; q text 2850 1150 "best week yet"
frame 10

q cancel

# GIF from a shared palette: a per-frame palette makes flat UI colours shimmer.
ffmpeg -y -framerate 10 -i "$TMP/f-%03d.png" \
  -vf "scale=880:-1:flags=lanczos,palettegen=stats_mode=diff" "$TMP/palette.png" >/dev/null 2>&1
ffmpeg -y -framerate 10 -i "$TMP/f-%03d.png" -i "$TMP/palette.png" \
  -lavfi "scale=880:-1:flags=lanczos[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=3" \
  -loop 0 "$OUT" >/dev/null 2>&1

q tool arrow; q width thin; q color red
ls -la "$OUT" | awk '{print "  " $NF, $5, "bytes"}'
