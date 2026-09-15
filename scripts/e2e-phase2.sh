#!/bin/bash
# End-to-end check of capture -> overlay -> selection -> copy, confined to the secondary display.
# Produces PNGs in out/ that a human (or Claude) can look at.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="$(cd "$ROOT" && swift build -c "${CONFIG:-debug}" --show-bin-path)/owlctl"
DISPLAY_SPEC="${OWL_TEST_DISPLAY:-secondary}"
OUT="$ROOT/out"
mkdir -p "$OUT"
rm -f "$OUT"/e2e-*.png

trap '"$CTL" cancel >/dev/null 2>&1 || true' EXIT

step() { echo "== $*" 1>&2; }

step "displays"
"$CTL" displays

step "capture (test mode, $DISPLAY_SPEC only)"
"$CTL" capture --display "$DISPLAY_SPEC" --test

step "snapshot overlay with no selection"
"$CTL" snapshot "$OUT/e2e-1-overlay.png" --display "$DISPLAY_SPEC"

step "select 400,300 1600x900"
"$CTL" select 400 300 1600 900

step "snapshot overlay with selection"
"$CTL" snapshot "$OUT/e2e-2-selection.png" --display "$DISPLAY_SPEC"

step "state"
"$CTL" state

step "copy"
"$CTL" copy

step "read clipboard back"
"$CTL" clipboard "$OUT/e2e-3-clipboard.png"

step "timings"
"$CTL" timings

step "downscaled previews"
for f in "$OUT"/e2e-*.png; do
  sips -Z 1600 "$f" --out "${f%.png}-small.png" >/dev/null
done
ls -la "$OUT"/e2e-*.png
