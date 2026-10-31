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
- **Playlist support** — inspect selected videos in the background, show actual resolutions, audio languages and captions with progress, then queue entries with the chosen settings
- **Dedicated playlist column** — playlists open a resizable middle column with clickable selection rows, a full-height list, pinned selection controls and a selected-video queue action; the window stays compact and single videos keep the two-column layout with the queue on the right
- **Adaptive window height** — subtitle controls grow and shrink the window to fit the main content, keeping its width; scrolling remains available when the content exceeds the monitor's usable height
- **Queue control** — start, pause, remove, retry, and drag-drop reorder downloads
- **File cleanup** — cancelled and failed partial downloads are cleaned without touching unrelated files
- **Bundled runtime tools** — ships with yt-dlp and ffmpeg, so users do not need Homebrew
- **yt-dlp updates** — app-managed yt-dlp updates keep the downloader current
- **One-click app updates** — checks GitHub releases, downloads the latest DMG, and installs it
- **Native macOS** — SwiftUI app, Developer ID release workflow, polished drag-to-Applications DMG

Use the **ⓘ** button next to the settings button for app updates, yt-dlp updates, and tool status. Both open matching side drawers, with one drawer visible at a time. The settings drawer contains download defaults, clipboard behavior, and the download folder.

Enable **Altyazı ekle** below the quality controls to choose **Videoya ekle** (embedded tracks) or **Ayrı dosya kaydet** (SRT/VTT) from the **Kaydetme biçimi** menu next to **Diller**. Caption availability is checked per video, including playlist entries. Missing or failed captions are reported in the queue while the video remains downloaded. Subtitle preferences are saved with each queued item; audio-only downloads do not include subtitles.

Use **Ses dili** to choose an existing audio track. **Orijinal** is selected for each new video or playlist. Playlist options are built from the selected videos' metadata, with progress shown while checking. Changing the selection updates available resolutions, codecs, containers, audio languages and subtitles; videos without captions disable the subtitle switch. Options found in only part of a playlist are checked again per download. If the chosen audio language is unavailable, that item reports an error instead of downloading another language. Audio-only downloads also honor the language selection. A metadata failure is shown as unknown availability and can be retried by analyzing the same link again.

## Installation

### Download DMG

1. Go to the [Releases](../../releases/latest) page
2. Download **`YouTubeJack.dmg`**
3. Open the DMG and drag **YouTubeJack.app** to your **Applications** folder

Release downloads are Developer ID signed and notarized. Use YouTubeJack only for media you have the right to download.

YouTubeJack checks for app updates silently at launch and every two hours while the app is running. When a newer release is available, a green **Güncelle** button appears beside the info and settings buttons. Manual checks and update status are available in the info drawer. Automatic check failures stay silent; manual checks show errors in the drawer.

App installation waits until there are no pending or running downloads. Preparing an app update blocks new queue work, and the installer keeps the previous app until the expected new version confirms that it opened from the installed location.

Downloaded filenames include the video ID and the download configuration, so videos with identical titles and different quality selections remain separate. Partial files live in a private folder for each queue item. Removing a failed or paused job cleans that folder and preserves completed media files. Resolution, format and codec defaults in Settings remain independent of the options available for the currently loaded video. Queue rows also provide a **Sırayı değiştir** menu for keyboard-accessible reordering.

## Build from Source

### Requirements

- App runtime: macOS 14.0+
- Build tools: Xcode 27.0+ with the macOS 27 SDK or newer
- Swift Package Manager and Python 3 (for build verification)

### Steps

```bash
git clone https://github.com/burakereno/youtubejack.git
cd youtubejack

swift test
python3 -m unittest discover -s Tests/BuildPipelineTests -v
./scripts/build-app.sh
open ".build/YouTubeJack.app"
```

Debug and release packaging share `script/macos_build.sh`. It passes the selected macOS SDK to both the Swift compiler and the clang linker driver, while keeping the deployment target at macOS 14. Every built binary is checked against the selected SDK; a stale SDK stamp, raised deployment target, or mismatched bundle metadata stops packaging.

Use `./script/build_and_run.sh` for the local build-and-run flow, or `./script/build_and_run.sh --build-only` to stage a debug app without restarting running apps. A build without bundle staging is available through `./script/macos_build.sh debug` (or `release`).

Use `./script/build_and_run.sh --preview-update` to preview the green update button in a local debug build. The preview button opens the info drawer without downloading or installing an app update. Release builds ignore the preview flag; local builds cannot install production app updates.

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
