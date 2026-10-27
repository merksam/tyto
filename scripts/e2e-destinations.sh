#!/bin/bash
# End-to-end check of destinations against a real SSH host: ⇧⌘C's send path, what lands on the
# clipboard, the file on the host, Recent Captures, a failing destination and a clipboard the
# script changes. Captures on the secondary display in test mode, as the other e2e scripts do.
#
#   TYTO_E2E_HOST=devbox TYTO_E2E_FOLDER=clips scripts/e2e-destinations.sh
#
# The host must take `ssh HOST` without a prompt. Installs its scripts into the scripts folder
# directly (the Settings sheet does it through a save panel), and removes them, the
# destinations and the files it sent when done.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTL="$(cd "$ROOT" && swift build -c "${CONFIG:-debug}" --show-bin-path)/tytoctl"
DISPLAY_SPEC="${TYTO_TEST_DISPLAY:-secondary}"
HOST="${TYTO_E2E_HOST:-devbox}"
FOLDER="${TYTO_E2E_FOLDER:-clips}"
SCRIPTS="$HOME/Library/Application Scripts/com.yevhenii.tyto"
SSH_DEST=tyto-e2e-ssh
FAIL_DEST=tyto-e2e-fail
CLIP_DEST=tyto-e2e-clip
SENT=()

step() { echo "== $*" 1>&2; }
fail() { echo "FAIL: $*" 1>&2; exit 1; }
# A value out of tytoctl's JSON reply, e.g. field data.result.
field() { plutil -extract "$1" raw -o - - 2>/dev/null || true; }
capture() { "$CTL" capture --display "$DISPLAY_SPEC" --test >/dev/null; "$CTL" select 400 300 640 360 >/dev/null; }

PREVIOUS_DEFAULT="$("$CTL" destinations | field data.default)"
cleanup() {
  "$CTL" cancel >/dev/null 2>&1 || true
  for f in "${SENT[@]+"${SENT[@]}"}"; do ssh -o BatchMode=yes "$HOST" "rm -f -- $f" || true; done
  for d in "$SSH_DEST" "$FAIL_DEST" "$CLIP_DEST"; do
    "$CTL" removedestination "$d" >/dev/null 2>&1 || true
    rm -f "$SCRIPTS/$d.sh"
  done
  if [ -n "$PREVIOUS_DEFAULT" ]; then "$CTL" set defaultDestination "$PREVIOUS_DEFAULT" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT

step "install scripts: $SSH_DEST ($HOST:$FOLDER), $FAIL_DEST, $CLIP_DEST"
"$CTL" render ssh host="$HOST" folder="$FOLDER" > "$SCRIPTS/$SSH_DEST.sh"
"$CTL" render ssh host=tyto-e2e.invalid folder=clips > "$SCRIPTS/$FAIL_DEST.sh"
printf '#!/bin/sh\nprintf "copied by the script" | pbcopy\necho "%s"\n' "/tmp/should-not-be-pasted" > "$SCRIPTS/$CLIP_DEST.sh"
chmod +x "$SCRIPTS/$SSH_DEST.sh" "$SCRIPTS/$FAIL_DEST.sh" "$SCRIPTS/$CLIP_DEST.sh"
"$CTL" destinations | grep -q "\"$SSH_DEST\"" || fail "the scripts were not picked up"
"$CTL" set defaultDestination "$SSH_DEST" >/dev/null
"$CTL" set destinationClipboard result >/dev/null

step "send the selection to the default destination (⇧⌘C's path)"
capture
REPLY="$("$CTL" send)" || fail "send failed: $REPLY"
RESULT="$(echo "$REPLY" | field data.result)"
echo "$REPLY" | field data.message 1>&2; echo 1>&2
[[ "$RESULT" =~ ^~/$FOLDER/tyto-[0-9]{8}-[0-9]{6}\.png$ ]] || fail "unexpected result: $RESULT"
SENT+=("$RESULT")
[ "$("$CTL" cliptext | field data.text)" = "$RESULT" ] || fail "the clipboard does not hold $RESULT"
MAGIC="$(ssh -o BatchMode=yes "$HOST" "head -c 4 $RESULT | od -An -tx1" | tr -d ' ')"
[ "$MAGIC" = "89504e47" ] || fail "$HOST:$RESULT is not a PNG ($MAGIC)"
echo "on $HOST: $RESULT" 1>&2

step "result and image on one pasteboard item"
"$CTL" set destinationClipboard resultAndImage >/dev/null
capture
REPLY="$("$CTL" send "$SSH_DEST")" || fail "send failed: $REPLY"
RESULT="$(echo "$REPLY" | field data.result)"; SENT+=("$RESULT")
CLIP="$("$CTL" cliptext)"
[ "$(echo "$CLIP" | field data.text)" = "$RESULT" ] || fail "the clipboard text is not $RESULT"
[ "$(echo "$CLIP" | field data.items)" = "1" ] || fail "expected one pasteboard item"
for t in public.png public.tiff public.utf8-plain-text; do echo "$CLIP" | grep -q "\"$t\"" || fail "no $t on the item"; done
"$CTL" set destinationClipboard result >/dev/null

step "Recent Captures → Send to $SSH_DEST"
REPLY="$("$CTL" sendrecent)" || fail "sendrecent failed: $REPLY"
RESULT="$(echo "$REPLY" | field data.result)"; SENT+=("$RESULT")
echo "resent $(echo "$REPLY" | field data.capture) as $RESULT" 1>&2

step "a failing destination reports stderr and leaves the clipboard alone"
BEFORE="$("$CTL" cliptext | field data.changeCount)"
capture
if REPLY="$("$CTL" send "$FAIL_DEST")"; then fail "a send to tyto-e2e.invalid succeeded"; fi
echo "$REPLY" | field error 1>&2; echo 1>&2
[ "$("$CTL" cliptext | field data.changeCount)" = "$BEFORE" ] || fail "a failed send changed the clipboard"

step "a clipboard changed during the send wins"
capture
REPLY="$("$CTL" send "$CLIP_DEST")" || fail "send failed: $REPLY"
[ "$(echo "$REPLY" | field data.clipboard)" = "skipped" ] || fail "expected the result to be skipped: $REPLY"
[ "$("$CTL" cliptext | field data.text)" = "copied by the script" ] || fail "Tyto overwrote the clipboard"

step "activity"
"$CTL" sends | grep -cE '"destination" : "tyto-e2e' | sed 's/^/e2e sends logged: /' 1>&2
echo "PASS" 1>&2
