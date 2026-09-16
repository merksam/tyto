#!/bin/bash
# End-to-end check of the annotation tools on the secondary display, through the same
# press/drag/release path the mouse uses. Produces PNGs in out/ for inspection.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="$(cd "$ROOT" && swift build -c "${CONFIG:-debug}" --show-bin-path)/tytoctl"
DISPLAY_SPEC="${TYTO_TEST_DISPLAY:-secondary}"
OUT="$ROOT/out"
mkdir -p "$OUT"
rm -f "$OUT"/e2e3-*.png

trap '"$CTL" cancel >/dev/null 2>&1 || true' EXIT

step() { echo "== $*" 1>&2; }
q() { "$CTL" "$@" >/dev/null; }

step "capture + select 400,300 1600x900"
q capture --display "$DISPLAY_SPEC" --test
q select 400 300 1600 900

step "draw one of everything"
q width medium
q color red;    q tool rect;    q draw 500 400 900 650
q color blue;   q tool arrow;   q draw 1000 450 1400 700
q color green;  q tool line;    q draw 500 800 900 1000
q color orange; q tool ellipse; q draw 1050 780 1450 1050
q color purple; q tool blur;    q draw 1500 400 1900 600
q color yellow; q tool badge;   q click 1600 800
q click 1750 800
q color white;  q width thick;  q text 520 1080 "Hello Tyto ünïcode"
q color black;  q width thin;   q text 1200 1120 "black on light"
"$CTL" shapes | /usr/bin/grep -c '"kind"' | sed 's/^/shape count: /' 1>&2

step "snapshot with annotations + toolbar"
q snapshot "$OUT/e2e3-1-annotated.png" --display "$DISPLAY_SPEC"

step "select tool: click the rect edge, move it, snapshot"
q tool select
q click 500 525
"$CTL" state | /usr/bin/grep selectedShape 1>&2
q draw 500 525 560 585
q snapshot "$OUT/e2e3-2-moved.png" --display "$DISPLAY_SPEC"

step "undo x2 (move, then the last text), redo x1"
q undo; q undo; q redo
"$CTL" state | /usr/bin/grep -E "shapeCount|canUndo|canRedo" 1>&2

step "delete the rect"
q click 500 525; q delete
"$CTL" shapes | /usr/bin/grep -c '"kind"' | sed 's/^/shape count after delete: /' 1>&2

step "export composite without ending, then copy (ends)"
q export "$OUT/e2e3-3-export.png"
"$CTL" copy | /usr/bin/grep -E "copyMS|width|height" 1>&2
q clipboard "$OUT/e2e3-4-clipboard.png"

step "downscaled previews"
for f in "$OUT"/e2e3-*.png; do sips -Z 1600 "$f" --out "${f%.png}-small.png" >/dev/null; done
ls -la "$OUT"/e2e3-*.png

# Leave the editor in a sane state for the next real capture.
"$CTL" tool rect >/dev/null
