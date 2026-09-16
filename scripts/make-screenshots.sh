#!/bin/bash
# Generates App Store screenshots at 2880x1800 (16:10, the largest size Apple accepts).
#
# Two stages. scripts/stage.swift paints a controlled backdrop on the chosen display so
# nothing of the real desktop is ever published; Tyto's UI in the shot is entirely real.
# scripts/compose-panel.swift then wraps each shot in a marketing panel with a headline,
# which is what every shipping screenshot app does on the store.
#
# One panel makes one point. Combining ideas (blur plus step numbers, say) reads as noise.
#
# usage: scripts/make-screenshots.sh [secondary|main]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISPLAY_SPEC="${1:-secondary}"
CTL="$(cd "$ROOT" && swift build -c debug --show-bin-path)/tytoctl"
OUT="$ROOT/out/screenshots"
TMP="${TMPDIR:-/tmp}/tyto-shots"
mkdir -p "$OUT" "$TMP"
rm -f "$OUT"/*.png

for tool in stage crop-screenshot compose-panel; do
  swiftc -O "$ROOT/scripts/$tool.swift" -o "$TMP/${tool%%-*}" 2>/dev/null
done

"$TMP/stage" "$DISPLAY_SPEC" >/dev/null 2>&1 &
STAGE_PID=$!
cleanup() { "$CTL" cancel >/dev/null 2>&1 || true; kill "$STAGE_PID" 2>/dev/null || true; }
trap cleanup EXIT
sleep 2

q() { "$CTL" "$@" >/dev/null; }
raw() { "$TMP/crop" "$TMP/$1.png" "$TMP/$1-crop.png" 1632 780 2752 1720 2880 1800 >/dev/null; }
panel() { (cd "$ROOT" && "$TMP/compose" "$TMP/$1-crop.png" "$OUT/$1.png" "$2" "$3" "${4:-}"); }

scene() {  # scene <name> ; caller has already set up the annotations
  sleep 1
  q snapshot "$TMP/$1.png" --display "$DISPLAY_SPEC"
  q cancel
  raw "$1"
}

echo "== 1 capture" >&2
q capture --display "$DISPLAY_SPEC"
q select 1800 980 2400 1350
scene 01-capture
panel 01-capture "01" "Press ⌘⇧9. The screen freezes instantly." \
  "Drag any region, or click a window to grab it exactly."

echo "== 2 annotate" >&2
q capture --display "$DISPLAY_SPEC"
q select 1800 980 2400 1350
q width thin
q color red;   q tool rect;  q draw 1890 1055 2570 1145
q color red;   q tool arrow; q draw 3350 1230 3810 1440
q color red;   q width thick; q tool text; q text 2850 1150 "best week yet"
scene 02-annotate
panel 02-annotate "02" "Mark it up without leaving the capture." \
  "Arrows, boxes, ellipses, lines and text, in any colour."

echo "== 3 blur" >&2
q capture --display "$DISPLAY_SPEC"
q select 1800 980 2400 1350
q tool blur; q draw 2545 1900 3010 2090
scene 03-blur
panel 03-blur "03" "Blur out anything private." \
  "Emails, names, keys: drag over them and they are gone."

echo "== 4 steps" >&2
q capture --display "$DISPLAY_SPEC"
q select 1800 980 2400 1350
q color orange; q width thick; q tool badge
q click 2020 2255; q click 2530 2255; q click 3040 2255
scene 04-steps
panel 04-steps "04" "Number the steps." \
  "Auto-incrementing badges turn a capture into instructions."

q tool arrow; q width thin; q color red
echo "" >&2
ls -la "$OUT"/*.png | awk '{print $NF, $5, "bytes"}' >&2
