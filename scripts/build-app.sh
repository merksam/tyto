#!/bin/bash
# Builds Tyto.app into build/ and signs it.
# A real bundle with a stable signature is required for the Screen Recording grant to persist.
# Signing: SIGN_IDENTITY env var, else the first "Developer ID Application" identity in the
# keychain, else ad-hoc (the TCC grant will then be lost on every rebuild).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${CONFIG:-debug}"
APP_NAME="Tyto"
BUNDLE_ID="com.yevhenii.tyto"
APP="$ROOT/build/$APP_NAME.app"

cd "$ROOT"
swift build -c "$CONFIG" 1>&2
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Tyto" "$APP/Contents/MacOS/$APP_NAME"   # SwiftPM product is Tyto; the shipped binary is Tyto
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Compile the asset catalog so the hand-built bundle carries the same icon as the Xcode build.
if [ -d "$ROOT/Resources/Assets.xcassets" ]; then
  xcrun actool "$ROOT/Resources/Assets.xcassets" \
    --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 27.0 \
    --app-icon AppIcon --output-partial-info-plist "$(mktemp -t tyto-actool)" >/dev/null 2>&1 || \
    echo "actool failed; bundle will have no icon" 1>&2
fi

IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
fi

# Every build is sandboxed (Mac App Store posture). SANDBOX=0 is a bisecting escape hatch only.
ENTITLEMENTS="$ROOT/Resources/Tyto.entitlements"
ENT_ARGS=(--entitlements "$ENTITLEMENTS")
if [ "${SANDBOX:-1}" = "0" ]; then
  ENT_ARGS=()
  echo "SANDBOX=0: signing WITHOUT entitlements (not the shipping posture)" 1>&2
fi

if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --options runtime --timestamp=none \
    --identifier "$BUNDLE_ID" ${ENT_ARGS[@]+"${ENT_ARGS[@]}"} "$APP" 1>&2
  echo "signed with: $IDENTITY" 1>&2
else
  codesign --force --sign - --identifier "$BUNDLE_ID" ${ENT_ARGS[@]+"${ENT_ARGS[@]}"} "$APP" 1>&2
  echo "signed ad-hoc (Screen Recording grant will not survive rebuilds)" 1>&2
fi
codesign --verify --verbose=2 "$APP" 1>&2
if [ "${SANDBOX:-1}" != "0" ]; then
  if codesign -d --entitlements - "$APP" 2>&1 | grep -q "com.apple.security.app-sandbox"; then
    echo "sandboxed: yes" 1>&2
  else
    echo "error: build is not sandboxed" 1>&2
    exit 1
  fi
fi
echo "$APP"
