#!/usr/bin/env bash
set -euo pipefail

YOUTUBEJACK_BUILD_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
YOUTUBEJACK_MACOS_MINIMUM="14.0"

youtubejack_configure_macos_sdk() {
  YOUTUBEJACK_MACOS_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
  YOUTUBEJACK_MACOS_SDK_VERSION="$(xcrun --sdk "$YOUTUBEJACK_MACOS_SDK_PATH" --show-sdk-version)"
  YOUTUBEJACK_MACOS_SDK_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CanonicalName' "$YOUTUBEJACK_MACOS_SDK_PATH/SDKSettings.plist")"
  YOUTUBEJACK_MACOS_SDK_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' "$YOUTUBEJACK_MACOS_SDK_PATH/System/Library/CoreServices/SystemVersion.plist")"
}

youtubejack_verify_macos_binary() {
  local binary="$1"
  shift
  python3 "$YOUTUBEJACK_BUILD_ROOT/script/verify_macos_sdk.py" "$binary" \
    --sdk "$YOUTUBEJACK_MACOS_SDK_VERSION" \
    --minimum "$YOUTUBEJACK_MACOS_MINIMUM" "$@"
}

youtubejack_copy_localization_resources() {
  local destination="$1"
  local resource_bundle="$(dirname "$YOUTUBEJACK_MACOS_BINARY")/YouTubeJack_YouTubeJackCore.bundle"
  if [[ ! -d "$resource_bundle" ]]; then
    echo "Missing SwiftPM localization resources: $resource_bundle" >&2
    return 1
  fi
  mkdir -p "$destination"
  ditto "$resource_bundle" "$destination/YouTubeJack_YouTubeJackCore.bundle"
}

youtubejack_build_macos() {
  local configuration="${1:-debug}"
  case "$configuration" in
    debug|release) ;;
    *) echo "Usage: macos_build.sh [debug|release]" >&2; return 2 ;;
  esac

  youtubejack_configure_macos_sdk

  # Swift Build's link invocation can stamp the deployment target as the SDK.
  # Forward the real sysroot to the clang linker driver as well as to Swift.
  local build_arguments=(
    --package-path "$YOUTUBEJACK_BUILD_ROOT"
    --sdk "$YOUTUBEJACK_MACOS_SDK_PATH"
    --configuration "$configuration"
    --product YouTubeJack
    -Xswiftc -Xclang-linker
    -Xswiftc -isysroot
    -Xswiftc -Xclang-linker
    -Xswiftc "$YOUTUBEJACK_MACOS_SDK_PATH"
  )

  xcrun swift build "${build_arguments[@]}"
  YOUTUBEJACK_MACOS_BINARY="$(xcrun swift build "${build_arguments[@]}" --show-bin-path)/YouTubeJack"
  youtubejack_verify_macos_binary "$YOUTUBEJACK_MACOS_BINARY"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  youtubejack_build_macos "${1:-debug}"
fi
