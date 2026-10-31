# Audio Language Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Download videos with the user's chosen available audio language and run the local app for testing.

**Architecture:** Carry language, original-language preference, and format notes through existing format metadata. Resolve original audio from that metadata, constrain every format-selector branch to the chosen language, and snapshot the selection in each queue item. Keep existing subtitle controls independent.

**Tech Stack:** SwiftPM, macOS 14+, SwiftUI, Swift Testing, bundled yt-dlp/ffmpeg.

## Global Constraints

- Select existing audio tracks only; no generated dubbing.
- Default to original audio; list only available languages for single videos.
- Label automatic dubbing only when the source identifies it.
- Never fall back to a different language when an explicit language is requested.
- Playlist language preferences must be checked per video by the constrained selector.
- Preserve existing subtitle functionality and unrelated workspace changes.
- Execute inline in the already authorized session, then use `./script/build_and_run.sh --verify`; no release or publishing.

### Task 1: Audio metadata and format selection

**Files:** `Sources/YouTubeJackCore/Models/AudioLanguage.swift`, `Models/MediaFormatAvailability.swift`, `Models/QualityProfile.swift`, `Services/YTDLPModels.swift`, `Services/MetadataService.swift`, `Tests/YouTubeJackCoreTests/Models/AudioLanguageTests.swift`.

**Interfaces:** `AudioLanguageSelection(languageCode:isOriginal:)`, `.original`, `.resolved(in:)`; `MediaFormat.language`, `.languagePreference`, `.formatNote`; `MediaFormatAvailability.audioLanguages`, `.originalAudioLanguageCode`. Existing availability/estimate methods gain a defaulted `audioLanguage` parameter.

- [x] Add behavioral tests for deduplicated language lists, true original audio versus default dubbing, missing metadata, and compatible resolution/container choices.
- [x] Decode `language`, `language_preference`, `format_note`, and top-level `language`.
- [x] Constrain separate and combined audio selectors; explicit choices use video-only streams plus selected-language audio, with a combined same-language fallback.
- [x] Keep original behavior compatible with untagged single-language videos.

### Task 2: Download snapshots, errors, and output identity

**Files:** `Sources/YouTubeJackCore/Models/DownloadItem.swift`, `Services/DownloadService.swift`, `Services/ProgressParser.swift`, `Tests/YouTubeJackCoreTests/Services/AudioLanguageDownloadTests.swift`.

**Interfaces:** `DownloadItem.audioLanguage`; `QualityProfile.formatSelector(container:codec:audioLanguage:)`; `QualityProfile.audioSelector(language:)`; optional `SelectedMediaFormat.audioLanguageCode` with backward-compatible progress parsing.

- [x] Snapshot language into queue jobs and use it in audio-only and video downloads.
- [x] Preserve the language through chunking/container retries; report unavailable-language errors explicitly.
- [x] Include an explicit audio-language suffix in translated output filenames so different dubs cannot reuse or overwrite each other's video.
- [x] Verify strict selectors using both executable fixtures and the real yt-dlp `--load-info-json --simulate` path.

### Task 3: Native UI and local preview

**Files:** `Sources/YouTubeJack/Views/AudioLanguagePickerView.swift`, `Views/ContentView.swift`, `Views/QueueView.swift`, `Stores/AppModel.swift`, `README.md`.

- [x] Add an original/available-language picker and source labels, analysis state, and playlist preference explanation.
- [x] Reconcile quality/container availability and size estimates with the selected audio language; preserve a valid selected resolution when possible.
- [x] Show the selected audio language in the queue and distinguish duplicate jobs by their audio choice.
- [x] Run the full test suite; verify live Turkish audio selection and a short sample download when available.
- [x] Build/launch with `./script/build_and_run.sh --verify`, inspect the UI, and leave the local app ready for testing.

## Validation

- Full suite: 33 XCTest tests and 24 Swift Testing tests passed, including parameterized language/container selectors.
- Real yt-dlp with live metadata: Turkish, English, and original French selected correctly for MP4 and WebM (6 cases).
- Existing subtitle tests, including real ffmpeg MP4/WebM round trips, passed.
- `./script/build_and_run.sh --verify` succeeded. Native UI shows Turkish audio selected and the running queue item retains `Ses: Türkçe`. The user-started download was left running.
- Live Turkish WebM sample: 5 seconds, 234,630 bytes, selected audio `tr`, ffmpeg decode succeeded. The subprocess-only sample used `/etc/ssl/cert.pem` as the trusted CA file for ffmpeg remote inputs; no permanent settings changed.
- Native queue verification: selected audio remained Turkish while the actual 2160p AV1/AAC MP4 download advanced to 39%.
