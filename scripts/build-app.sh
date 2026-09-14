#!/bin/bash
# Builds Owl.app into build/ and signs it.
# A real bundle with a stable signature is required for the Screen Recording grant to persist.
# Signing: SIGN_IDENTITY env var, else the first "Developer ID Application" identity in the
# keychain, else ad-hoc (the TCC grant will then be lost on every rebuild).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
APP_NAME="Owl"
BUNDLE_ID="com.owl.app"
APP="$ROOT/build/$APP_NAME.app"

cd "$ROOT"
swift build -c "$CONFIG" 1>&2
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Owl" "$APP/Contents/MacOS/Owl"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
fi
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --options runtime --timestamp=none \
    --identifier "$BUNDLE_ID" "$APP" 1>&2
  echo "signed with: $IDENTITY" 1>&2
else
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" 1>&2
  echo "signed ad-hoc (Screen Recording grant will not survive rebuilds)" 1>&2
fi
codesign --verify --verbose=2 "$APP" 1>&2
echo "$APP"
