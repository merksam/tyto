#!/bin/bash
# Archives the app with Xcode and exports it.
#   METHOD=store  -> Mac App Store .pkg (needs Apple Distribution + Mac Installer
#                    Distribution certs; UPLOAD=1 sends it to App Store Connect)
#   METHOD=devid  -> Developer ID .app for direct distribution (notarize separately)
# Credentials for automatic signing/upload, when set:
#   ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (App Store Connect API key, Admin role)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
METHOD="${METHOD:-devid}"
ARCHIVE="$ROOT/build/Tyto.xcarchive"

case "$METHOD" in
  store) OPTS_SRC="$ROOT/ExportOptions/AppStore.plist";   EXPORT="$ROOT/build/export-store" ;;
  devid) OPTS_SRC="$ROOT/ExportOptions/DeveloperID.plist"; EXPORT="$ROOT/build/export-devid" ;;
  *) echo "METHOD must be store or devid" >&2; exit 2 ;;
esac

AUTH=(-allowProvisioningUpdates)
if [ -n "${ASC_KEY_ID:-}" ]; then
  AUTH+=(-authenticationKeyPath "${ASC_KEY_PATH:?ASC_KEY_PATH required}" \
         -authenticationKeyID "$ASC_KEY_ID" \
         -authenticationKeyIssuerID "${ASC_ISSUER_ID:?ASC_ISSUER_ID required}")
fi

"$ROOT/scripts/gen-project.sh" >/dev/null
rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild -project "$ROOT/Tyto.xcodeproj" -scheme TytoApp -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" archive "${AUTH[@]}"

OPTS="$ROOT/build/ExportOptions-$METHOD.plist"
mkdir -p "$ROOT/build"
cp "$OPTS_SRC" "$OPTS"
if [ "${UPLOAD:-0}" = "1" ]; then
  [ "$METHOD" = "store" ] || { echo "UPLOAD=1 only applies to METHOD=store" >&2; exit 2; }
  plutil -replace destination -string upload "$OPTS"
fi

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTS" \
  -exportPath "$EXPORT" "${AUTH[@]}"
echo "exported to: $EXPORT" >&2
ls -la "$EXPORT" >&2
