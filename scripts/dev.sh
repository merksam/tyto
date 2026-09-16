#!/bin/bash
# Build, (re)launch Tyto.app, and wait for the debug socket to answer.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$("$ROOT/scripts/build-app.sh")"
CTL="$(cd "$ROOT" && swift build -c "${CONFIG:-debug}" --show-bin-path)/tytoctl"
mkdir -p "$ROOT/out"

pkill -x Tyto 2>/dev/null || true
for _ in $(seq 1 20); do pgrep -x Tyto >/dev/null || break; sleep 0.1; done

# Launch the executable inside the bundle (not `open`) so stdout/stderr land in a log
# and the environment is inherited. TCC still attributes the process to the bundle.
nohup "$APP/Contents/MacOS/Tyto" >"$ROOT/out/tyto.log" 2>&1 &
echo "launched pid $! (log: out/tyto.log)" 1>&2

for i in $(seq 1 50); do
  if "$CTL" ping >/dev/null 2>&1; then
    "$CTL" ping
    echo "socket: $(ls -la "$("$CTL" container)/tmp/tyto-debug.sock" 2>/dev/null || echo 'not in container (TYTO_DEBUG_SOCKET override?)')" 1>&2
    exit 0
  fi
  sleep 0.1
done
echo "Tyto did not answer on the debug socket within 5s; see out/tyto.log" 1>&2
tail -20 "$ROOT/out/tyto.log" 1>&2
exit 1
