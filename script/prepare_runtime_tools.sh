#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$ROOT_DIR/Sources/YouTubeJack/Resources/bin"
LICENSE_DIR="$ROOT_DIR/Sources/YouTubeJack/Resources/licenses"
FORCE="${YOUTUBEJACK_FORCE_RUNTIME:-0}"
TMP_DIRS=""

cleanup() {
  while IFS= read -r dir; do
    [[ -n "$dir" ]] && rm -rf "$dir"
  done <<< "$TMP_DIRS"
  return 0
}
trap cleanup EXIT

mkdir -p "$BIN_DIR" "$LICENSE_DIR"

make_tmp_dir() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  TMP_DIRS="${TMP_DIRS}${tmp_dir}"$'\n'
  printf '%s\n' "$tmp_dir"
}

download() {
  local url="$1"
  local destination="$2"
  curl --proto '=https' --tlsv1.2 -L --fail --silent --show-error "$url" -o "$destination"
}

sha256_of() {
  shasum -a 256 "$1" | awk '{print $1}'
}

prepare_ytdlp() {
  local destination="$BIN_DIR/yt-dlp"
  if [[ -x "$destination" && "$FORCE" != "1" ]]; then
    echo "yt-dlp already prepared: $destination"
    return
  fi

  local tmp_dir
  tmp_dir="$(make_tmp_dir)"
  local binary="$tmp_dir/yt-dlp_macos"
  local sums="$tmp_dir/SHA2-256SUMS"

  echo "Downloading yt-dlp macOS release..."
  download "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" "$binary"
  download "https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS" "$sums"

  local expected
  expected="$(awk '$2 == "yt-dlp_macos" || $2 == "*yt-dlp_macos" { print $1; exit }' "$sums")"
  if [[ -z "$expected" ]]; then
    echo "Could not find yt-dlp_macos checksum" >&2
    exit 1
  fi

  local actual
  actual="$(sha256_of "$binary")"
  if [[ "$actual" != "$expected" ]]; then
    echo "yt-dlp checksum mismatch" >&2
    exit 1
  fi

  cp "$binary" "$destination"
  chmod 0755 "$destination"
}

prepare_ffmpeg() {
  local destination="$BIN_DIR/ffmpeg"
  if [[ -x "$destination" && "$FORCE" != "1" ]]; then
    echo "ffmpeg already prepared: $destination"
    return
  fi

  local machine
  machine="$(uname -m)"
  local ffmpeg_arch
  case "$machine" in
    arm64) ffmpeg_arch="arm64" ;;
    x86_64) ffmpeg_arch="amd64" ;;
    *)
      echo "Unsupported macOS architecture for bundled ffmpeg: $machine" >&2
      exit 1
      ;;
  esac

  local tmp_dir page urls zip_file checksum_file extract_dir
  tmp_dir="$(make_tmp_dir)"
  page="$tmp_dir/ffmpeg.html"
  urls="$tmp_dir/urls.txt"
  zip_file="$tmp_dir/ffmpeg.zip"
  checksum_file="$tmp_dir/ffmpeg.zip.sha256"
  extract_dir="$tmp_dir/extract"

  echo "Resolving ffmpeg macOS $ffmpeg_arch release build..."
  curl --proto '=https' --tlsv1.2 -L --fail --silent --show-error -A "YouTubeJack" "https://ffmpeg.martin-riedl.de/" -o "$page"
  /usr/bin/python3 - "$page" "$ffmpeg_arch" >"$urls" <<'PY'
from pathlib import Path
import re
import sys

page = Path(sys.argv[1]).read_text()
arch = sys.argv[2]
label = "macOS (Apple Silicon/arm64)" if arch == "arm64" else "macOS (Intel/amd64)"
release_marker = "<h2>Download Release Build</h2>"

try:
    section = page.split(release_marker, 1)[1]
except IndexError:
    raise SystemExit("release build section not found")

pattern = (
    r"<h3>" + re.escape(label) + r"</h3>.*?"
    r"<a href=\"([^\"]+)\">\s*FFmpeg \(ZIP\)\s*</a>.*?"
    r"<a href=\"([^\"]+)\"[^>]*>\s*SHA256\s*</a>"
)
match = re.search(pattern, section, re.S)
if not match:
    raise SystemExit(f"ffmpeg release links not found for {label}")

base = "https://ffmpeg.martin-riedl.de"
print(base + match.group(1))
print(base + match.group(2))
PY

  local ffmpeg_url checksum_url
  ffmpeg_url="$(sed -n '1p' "$urls")"
  checksum_url="$(sed -n '2p' "$urls")"

  echo "Downloading ffmpeg..."
  download "$ffmpeg_url" "$zip_file"
  download "$checksum_url" "$checksum_file"

  local expected actual
  expected="$(awk '{ print $1; exit }' "$checksum_file")"
  actual="$(sha256_of "$zip_file")"
  if [[ "$actual" != "$expected" ]]; then
    echo "ffmpeg checksum mismatch" >&2
    exit 1
  fi

  mkdir -p "$extract_dir"
  ditto -x -k "$zip_file" "$extract_dir"

  local extracted
  extracted="$(find "$extract_dir" -type f -name ffmpeg | head -1)"
  if [[ -z "$extracted" ]]; then
    echo "ffmpeg executable not found in archive" >&2
    exit 1
  fi

  cp "$extracted" "$destination"
  chmod 0755 "$destination"
}

prepare_ytdlp
prepare_ffmpeg

cat >"$LICENSE_DIR/runtime-tools-notice.txt" <<'NOTICE'
YouTubeJack bundles command-line runtime tools so users do not need Homebrew.

yt-dlp:
- Source: https://github.com/yt-dlp/yt-dlp
- Bundled from the official macOS release asset.
- The app can install newer yt-dlp releases into Application Support/YouTubeJack/bin.

FFmpeg:
- Source project: https://ffmpeg.org/
- macOS binary build provider used by the development packaging script:
  https://ffmpeg.martin-riedl.de/
- Current development build is a GPL-enabled FFmpeg build. Review and satisfy
  FFmpeg/GPL license obligations before public distribution.
NOTICE

echo "Runtime tools prepared in $BIN_DIR"
