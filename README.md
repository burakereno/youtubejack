# YouTubeJack

<p align="center">
  <img src="https://youtubejack.burakerenoglu.com/apps/youtubejack/icon-rounded-20261030.webp" alt="YouTubeJack" width="340">
</p>

**Native macOS YouTube downloader.** Paste a video or playlist link, preview it, choose an available resolution and format, then download through a simple native queue.

<p align="center">
  <a href="https://github.com/burakereno/youtubejack/releases/latest/download/YouTubeJack.dmg">
    <img src="https://img.shields.io/badge/Download-YouTubeJack.dmg-22c55e?style=for-the-badge&logo=apple&logoColor=white&cb=2" alt="Download YouTubeJack.dmg" height="48">
  </a>
  &nbsp;
  <a href="https://github.com/burakereno/youtubejack/releases/latest">
    <img src="https://img.shields.io/github/v/release/burakereno/youtubejack?style=for-the-badge&label=Latest&color=2563eb&cb=2" alt="Latest release" height="48">
  </a>
</p>

<p align="center">
  <sub>macOS 14.0+ · bundled yt-dlp and ffmpeg · Developer ID signed and notarized</sub>
</p>

## Features

- **Native preview** — paste a YouTube video or playlist URL and fetch title, channel, duration, and thumbnail
- **Resolution-aware choices** — only available video resolutions, codecs, and container formats are enabled
- **Video codec control** — choose automatic, H.264, or AV1 and see the selected video and audio codecs in the queue
- **Audio language selection** — choose original audio or an available dub, including independently selected subtitles; queue jobs retain the language and translated downloads use a language suffix in the filename
- **Optional subtitles** — select multiple languages, prefer publisher captions, and optionally fall back to automatic captions; embed switchable subtitles in MP4/WebM or save SRT/VTT files alongside the video
- **MP4 / WebM handling** — preserves high-quality WebM where needed and uses MP4 when available
- **Playlist support** — select all, clear selection, and queue many playlist entries at once
- **Queue control** — start, pause, remove, retry, and drag-drop reorder downloads
- **File cleanup** — cancelled and failed partial downloads are cleaned without touching unrelated files
- **Bundled runtime tools** — ships with yt-dlp and ffmpeg, so users do not need Homebrew
- **yt-dlp updates** — app-managed yt-dlp updates keep the downloader current
- **One-click app updates** — checks GitHub releases, downloads the latest DMG, and installs it
- **Native macOS** — SwiftUI app, Developer ID release workflow, polished drag-to-Applications DMG

Enable **Altyazı ekle** below the quality controls to choose **Videoya göm** (embedded tracks) or **Ayrı dosya** (SRT/VTT). Caption availability is checked per video, including playlist entries. Missing or failed captions are reported in the queue while the video remains downloaded. Subtitle preferences are saved with each queued item; audio-only downloads do not include subtitles.

Use **Ses dili** to choose an existing audio track. **Orijinal** is selected for each new video. Single videos list available languages, and playlist language preferences are checked for each entry during download. If the chosen language is unavailable, that item reports an error instead of downloading another language. Audio-only downloads also honor the language selection.

## Installation

### Download DMG

1. Go to the [Releases](../../releases/latest) page
2. Download **`YouTubeJack.dmg`**
3. Open the DMG and drag **YouTubeJack.app** to your **Applications** folder

Release downloads are Developer ID signed and notarized. Use YouTubeJack only for media you have the right to download.

## Build from Source

### Requirements

- macOS 14.0+
- Xcode 16.0+
- Swift Package Manager

### Steps

```bash
git clone https://github.com/burakereno/youtubejack.git
cd youtubejack

swift test
./scripts/build-app.sh
open ".build/YouTubeJack.app"
```

For a local Developer ID signed DMG:

```bash
./scripts/build-signed-dmg.sh
```

`scripts/build-app.sh` prepares bundled runtime tools before staging the `.app` bundle. At runtime YouTubeJack resolves tools in this order:

1. `~/Library/Application Support/YouTubeJack/bin`
2. `YouTubeJack.app/Contents/Resources/bin`

The first location is used for app-managed yt-dlp updates.

## Tech Stack

- **SwiftUI** — native window and settings UI
- **AppKit** — app lifecycle, Finder reveal, update installer handoff
- **Swift Package Manager** — build system
- **yt-dlp / ffmpeg** — metadata extraction, download, merge, and remux
- **GitHub Releases** — app update checks and DMG distribution

Release signing setup is documented in [docs/release-signing.md](docs/release-signing.md).
