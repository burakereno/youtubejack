#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
  run|--build-only|build-only|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|--preview-update) ;;
  *) echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify|--preview-update]" >&2; exit 2 ;;
esac
APP_NAME="YouTubeJack"
BUNDLE_ID="${YOUTUBEJACK_BUNDLE_ID:-com.local.YouTubeJack}"
APP_VERSION="${APP_VERSION:-0.1.0}"
APP_BUILD_NUMBER="${APP_BUILD_NUMBER:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${YOUTUBEJACK_DIST_DIR:-$ROOT_DIR/dist}"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

local_app_pids() {
  local pid
  while IFS= read -r pid; do
    if [[ "$(/bin/ps -p "$pid" -o comm=)" == "$APP_BINARY" ]]; then
      echo "$pid"
    fi
  done < <(/usr/bin/pgrep -x "$APP_NAME" || true)
}

cd "$ROOT_DIR"

if [[ "${YOUTUBEJACK_PREPARE_RUNTIME:-1}" != "0" ]]; then
  "$ROOT_DIR/script/prepare_runtime_tools.sh"
fi

source "$ROOT_DIR/script/macos_build.sh"
MIN_SYSTEM_VERSION="$YOUTUBEJACK_MACOS_MINIMUM"
youtubejack_build_macos debug
BUILD_BINARY="$YOUTUBEJACK_MACOS_BINARY"

if [[ "$MODE" != "--build-only" && "$MODE" != "build-only" ]]; then
  while IFS= read -r pid; do
    /bin/kill -TERM "$pid" 2>/dev/null || true
  done < <(local_app_pids)
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -d "$ROOT_DIR/Sources/YouTubeJack/Resources" ]]; then
  mkdir -p "$APP_CONTENTS/Resources"
  ditto "$ROOT_DIR/Sources/YouTubeJack/Resources" "$APP_CONTENTS/Resources"
fi

youtubejack_copy_localization_resources "$APP_CONTENTS/Resources"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array><string>en</string><string>tr</string></array>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>DTSDKName</key>
  <string>$YOUTUBEJACK_MACOS_SDK_NAME</string>
  <key>DTSDKBuild</key>
  <string>$YOUTUBEJACK_MACOS_SDK_BUILD</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

youtubejack_verify_macos_binary "$APP_BINARY" --info-plist "$INFO_PLIST"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build-only|build-only)
    echo "Built $APP_BUNDLE"
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    [[ -n "$(local_app_pids)" ]]
    ;;
  --preview-update)
    /usr/bin/open -n "$APP_BUNDLE" --args --preview-update
    sleep 1
    [[ -n "$(local_app_pids)" ]]
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify|--preview-update]" >&2
    exit 2
    ;;
esac
