#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/.build/YouTubeJack.app"
OUTPUT_DMG="${1:-$ROOT_DIR/YouTubeJack.dmg}"

default_codesign_identity() {
  /usr/bin/security find-identity -v -p codesigning 2>/dev/null \
    | /usr/bin/awk '/Developer ID Application/ { print $2; exit }'
}

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-$(default_codesign_identity)}"
if [[ -z "$CODESIGN_IDENTITY" ]]; then
  echo "Developer ID Application signing identity not found." >&2
  echo "Set CODESIGN_IDENTITY or install a Developer ID Application certificate." >&2
  exit 1
fi

cd "$ROOT_DIR"

BUNDLE_IDENTIFIER="${BUNDLE_IDENTIFIER:-dev.local.YouTubeJack}" \
CODESIGN_IDENTITY="$CODESIGN_IDENTITY" \
"$ROOT_DIR/scripts/build-app.sh"

"$ROOT_DIR/scripts/create-dmg.sh" "$APP_PATH" "$OUTPUT_DMG"
/usr/bin/codesign --force --sign "$CODESIGN_IDENTITY" --timestamp "$OUTPUT_DMG"
/usr/bin/codesign --verify --verbose=2 "$OUTPUT_DMG"
/usr/bin/hdiutil verify "$OUTPUT_DMG"

echo "Built and signed $OUTPUT_DMG"
