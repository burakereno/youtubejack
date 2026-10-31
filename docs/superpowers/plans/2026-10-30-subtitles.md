# Embedded Subtitles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add optional multilingual subtitles, either embedded or saved alongside videos, and launch a local preview.

**Architecture:** Decode available manual and automatic subtitle languages alongside existing format metadata. Snapshot subtitle preferences into each queue item. Download captions into an isolated temporary directory after media download, then embed compatible subtitle streams without re-encoding video; subtitle failures report a warning and preserve the downloaded video.

**Tech Stack:** SwiftPM, macOS 14+, SwiftUI, yt-dlp, ffmpeg, Swift Testing.

## Global Constraints

- No subtitle-only download mode.
- Confirmed clarification: offer both embedded subtitles and SRT/VTT sidecar files with a video download.
- Prefer publisher captions; automatic captions require the fallback toggle.
- List available languages, Turkish and English first; allow multiple selections.
- Check availability per video in playlists; missing captions must not fail video downloads.
- Use the existing local run script. Do not publish or release.
- Execute inline in the already authorized session; do not pause for a plan handoff.

### Task 1: Metadata and queue contracts

**Files:** `Sources/YouTubeJackCore/Models/SubtitleOptions.swift`, `Models/MediaInfo.swift`, `Models/DownloadItem.swift`, `Services/YTDLPModels.swift`, `Services/MetadataService.swift`, `Tests/YouTubeJackCoreTests/Models/SubtitleOptionsTests.swift`.

**Interfaces:** `SubtitleOptions(isEnabled:languageCodes:includesAutomatic:)`, `SubtitleLanguage(code:name:hasManual:hasAutomatic:)`, `SubtitleAvailability(isKnown:languages:)`; add defaulted `subtitleAvailability` to `MediaInfo`, `subtitles` and `subtitleMessage` to `DownloadItem`.

- [x] Decode `subtitles` and `automatic_captions` dictionaries, excluding live chat and empty tracks.
- [x] Merge manual/automatic language availability, localize names, sort Turkish/English first.
- [x] Verify publisher/automatic overlap, absent metadata, and exact language-code handling with Swift Testing.

### Task 2: Video embedding and warnings

**Files:** `Services/SubtitleService.swift`, `Services/DownloadService.swift`, `Tests/YouTubeJackCoreTests/Services/SubtitleServiceTests.swift`.

**Interfaces:** `SubtitleService.download(item:videoPath:onMessage:run:) async throws -> SubtitleResult`, with the process runner supplied by `DownloadService` so pause/cancel applies to every phase. Extend `DownloadService.download` with defaulted `onSubtitleMessage: (String?) -> Void` and `onArtifactPath: (String) -> Void`.

- [x] Keep the media download independent of subtitles and isolated from external yt-dlp configuration.
- [x] Fetch requested manual/fallback captions into a unique temporary directory using exact language selectors and VTT/SRT conversion.
- [x] Embed MP4 subtitles as `mov_text` and WebM subtitles as `webvtt`; copy video/audio streams and atomically replace only after success.
- [x] Clean temporary files on all exits. Propagate cancellation; convert subtitle errors to queue warnings while preserving media.
- [x] Verify missing languages, failed subtitle requests, embedding failure, successful multiple-language embedding, and cancellation with isolated executable fixtures.

### Task 3: SwiftUI controls and local preview

**Files:** `Sources/YouTubeJack/Views/SubtitlePickerView.swift`, `Views/ContentView.swift`, `Views/QueueView.swift`, `Stores/AppModel.swift`, `Support/AppPreferenceKeys.swift`, `README.md`.

**Interfaces:** `AppModel.subtitleOptions`, `subtitleLanguages`, `setSubtitleLanguage(_:selected:)`, and `queuedSubtitleOptions` feed a focused SwiftUI view and queue snapshots.

- [x] Add the subtitle toggle, language menu, automatic fallback toggle, and explanatory copy below quality selection.
- [x] Disable subtitle controls for audio-only quality; show analysis, empty, and playlist states.
- [x] Persist preferences and display per-item selection/status/warnings in the queue.
- [x] Run `swift test`; use bundled ffmpeg to verify real MP4/WebM stream compatibility with synthetic media.
- [x] Run `./script/build_and_run.sh --verify`, inspect the local UI, and leave the app open for user testing.

## Validation

- Existing XCTest suite: 33 tests passed.
- Subtitle Swift Testing suite: 13 tests passed, including parameterized MP4/WebM and SRT/VTT cases.
- Real bundled ffmpeg round trip: two subtitle tracks embedded and extracted successfully in both MP4 and WebM.
- Live YouTube publisher-caption request: Stanford video `UF8uR6Z6KLc`, English track `en-eEY6OEpapPo`, SRT download succeeded (20,564 bytes).
- Local `./script/build_and_run.sh --verify` build and launch succeeded.
