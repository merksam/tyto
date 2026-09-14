#!/bin/bash
# Build, (re)launch Owl.app, and wait for the debug socket to answer.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$("$ROOT/scripts/build-app.sh")"
CTL="$(cd "$ROOT" && swift build -c "${CONFIG:-debug}" --show-bin-path)/owlctl"
mkdir -p "$ROOT/out"

pkill -x Owl 2>/dev/null || true
for _ in $(seq 1 20); do pgrep -x Owl >/dev/null || break; sleep 0.1; done

# Launch the executable inside the bundle (not `open`) so stdout/stderr land in a log
# and the environment is inherited. TCC still attributes the process to the bundle.
OWL_DEBUG=1 nohup "$APP/Contents/MacOS/Owl" >"$ROOT/out/owl.log" 2>&1 &
echo "launched pid $! (log: out/owl.log)" 1>&2

for i in $(seq 1 50); do
  if "$CTL" ping >/dev/null 2>&1; then
    "$CTL" ping
    exit 0
  fi
  sleep 0.1
done
echo "Owl did not answer on the debug socket within 5s; see out/owl.log" 1>&2
tail -20 "$ROOT/out/owl.log" 1>&2
exit 1
