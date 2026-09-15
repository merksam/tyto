#!/bin/bash
# Regenerates Owl.xcodeproj from project.yml. The project is git-ignored on purpose:
# project.yml is the committed source of truth, and pbxproj diffs are unreadable.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODEGEN="${XCODEGEN:-$(command -v xcodegen || echo /opt/homebrew/bin/xcodegen)}"
[ -x "$XCODEGEN" ] || { echo "xcodegen not found (brew install xcodegen)" >&2; exit 1; }
cd "$ROOT"
"$XCODEGEN" generate --spec project.yml
echo "$ROOT/Owl.xcodeproj"
