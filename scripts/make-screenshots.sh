#!/bin/bash
# Generates App Store screenshots at 2880x1800 (16:10, the largest size Apple accepts).
#
# Screenshots of a screenshot tool need something to photograph. scripts/stage.swift paints a
# controlled backdrop on the chosen display so nothing of the real desktop is ever published;
# Tyto's own UI in the result is entirely real. Sessions run interactive so the floating
# toolbar is present, and each one is cancelled before the next begins.
#
# usage: scripts/make-screenshots.sh [secondary|main]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPLAY_SPEC="${1:-secondary}"
CTL="$(cd "$ROOT" && swift build -c debug --show-bin-path)/tytoctl"
OUT="$ROOT/out/screenshots"
TMP="${TMPDIR:-/tmp}/tyto-shots"
mkdir -p "$OUT" "$TMP"

swiftc -O "$ROOT/scripts/stage.swift" -o "$TMP/stage" 2>/dev/null
swiftc -O "$ROOT/scripts/crop-screenshot.swift" -o "$TMP/crop" 2>/dev/null

"$TMP/stage" "$DISPLAY_SPEC" >/dev/null 2>&1 &
STAGE_PID=$!
cleanup() { "$CTL" cancel >/dev/null 2>&1 || true; kill "$STAGE_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 2

q() { "$CTL" "$@" >/dev/null; }
# Crop window: the staged document and the toolbar beneath it, 16:10, output 2880x1800.
# Kept tight so Tyto's controls, which are a fixed point size, read clearly.
shot() { "$TMP/crop" "$TMP/$1.png" "$OUT/$1.png" 1664 790 2688 1680 2880 1800; }

echo "== 1. selecting a region" >&2
q capture --display "$DISPLAY_SPEC"
q select 1800 980 2400 1350
sleep 1
q snapshot "$TMP/01-select.png" --display "$DISPLAY_SPEC"
q cancel
shot 01-select

echo "== 2. annotating" >&2
q capture --display "$DISPLAY_SPEC"
q select 1800 980 2400 1350
q width thin
q color red;   q tool rect;  q draw 1890 1055 2570 1145
q color red;   q tool arrow; q draw 3350 1230 3810 1440
q color red;   q width thick; q tool text; q text 2850 1150 "best week yet"
sleep 1
q snapshot "$TMP/02-annotate.png" --display "$DISPLAY_SPEC"
q cancel
shot 02-annotate

echo "== 3. hiding private details and numbering steps" >&2
q capture --display "$DISPLAY_SPEC"
q select 1800 980 2400 1350
q tool blur;  q draw 1900 1985 2920 2050
q color orange; q width thick; q tool badge
q click 1865 1090; q click 1865 1620; q click 1865 2015
sleep 1
q snapshot "$TMP/03-blur-steps.png" --display "$DISPLAY_SPEC"
q cancel
shot 03-blur-steps

# Leave the editor on the shipping defaults.
q tool arrow; q width thin; q color red
echo "" >&2
ls -la "$OUT"/*.png | awk '{print $NF, $5, "bytes"}' >&2
