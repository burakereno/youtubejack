# Audit Fixes Implementation Plan

> Execution: inline in this session, as explicitly authorized by the user. Preserve the existing dirty working tree. Do not publish or install a production update.

**Goal:** Resolve all 15 findings from the functional, security and UI audit, in priority order.

**Architecture:** Keep the existing SwiftPM/SwiftUI structure. Give every download a private, ownership-marked temporary directory; keep published files outside cleanup. Separate user defaults from media-specific selection, and use request identities for asynchronous analysis and cancellation.

**Tech Stack:** Swift, Swift Testing, SwiftUI/AppKit, yt-dlp, ffmpeg, macOS 14+, SDK 27.

## P1: File identity and safe cleanup (findings 1–2)

- [x] Add `DownloadWorkspace` in `Sources/YouTubeJackCore/Services/DownloadWorkspace.swift`, with `prepare() throws`, `directory: URL`, and `removeOwnedDirectory(at:itemID:)`. Require a matching UUID directory name, non-symlink directory and owner marker before cleanup.
- [x] Add a stable configuration fingerprint and a relative output template containing `%(id)s` in `Sources/YouTubeJackCore/Services/DownloadService.swift`. Send separate `--paths home:...` and `--paths temp:...` arguments so yt-dlp moves only finished files to the destination.
- [x] Record the workspace path in `DownloadItem` before starting a queue job. Replace output-path-based deletion in `AppModel`/`DownloadArtifactCleaner` with workspace-only cleanup. Wait for a running job to finish cancellation before cleaning its workspace.
- [x] Add regression tests in `Tests/YouTubeJackCoreTests/DownloadSafetyTests.swift`: identical titles with different IDs, distinct settings, shared home/unique temporary paths, preservation of completed files, rejection of unowned/symlink workspaces, retry reuse.
- [x] Run focused tests; resolve P1 failures before proceeding to P2.

## P2: Queue, output and selection (findings 3–4, 7–9, 11)

- [x] Track pause cancellation by job ID, independently of the current paused flag. Test immediate resume and a later resume using a controlled local executable.
- [x] Request `after_move:download-output:%(filepath)s` for audio and video. Test conversion where the initial WebM file no longer exists.
- [x] Buffer stdout/stderr as bytes until a complete line is available. Decode only complete lines; test a Turkish UTF-8 character split across writes.
- [x] Include quality, container and codec in queue request matching, for both videos and playlists. Test each variant and exact duplicate suppression.
- [x] Keep selected video mode when a codec is unavailable: fall back to automatic codec before choosing a resolution. Test a VP9-only video with a saved H.264 preference.
- [x] Introduce explicit default-setting methods in `AppModel`; remove preference writes from availability reconciliation. Bind Settings to the stored defaults and test that a loaded 1080p video cannot overwrite a saved 2160p default.

## P2: Analysis identity and retry (findings 5–6)

- [x] Add an analysis generation token. Invalidate it on input edits/clear; guard every success/error application with the token and normalized current URL.
- [x] Schedule a new input independently of the old request's `isAnalyzing` state. Cancel obsolete tasks without letting their error handlers clear current content.
- [x] Retry single-video format extraction when preview exists but formats are unknown. Inject metadata operations into `AppModel` for deterministic delayed/failing tests.
- [x] Test clearing during preview, replacing the URL during analysis, overlapping requests, and successful retry after extraction failure.

## P2/P3: UI focus and accessible reordering (findings 10, 15)

- [x] Disable and hide background content from accessibility while a drawer is presented. Propagate SwiftUI enabled state into the native text field. Verify Tab/typing cannot mutate the background field.
- [x] Add labeled move-up/move-down buttons or menu actions to queue rows, using existing `canMoveUp`, `canMoveDown`, and move methods. Verify accessibility actions and boundary disabling.

## P2: Update lifecycle (findings 12–14)

- [x] Move a downloaded temporary file synchronously inside the URLSession callback into a private directory, before scheduling MainActor work. Test retention after the callback-owned file is removed.
- [x] Replace process-name-only installer launch confirmation with a handshake from the exact installed bundle/version/process. Require sustained liveness and preserve rollback on missing/wrong handshake; test the script with temporary targets and stub external tools, without touching Applications.
- [x] Route update actions through `AppModel`. Refuse/defer installation while queue jobs remain pending/running or downloads are stopping; recheck immediately before installer handoff and block new queue work during installation preparation. Test guard changes during download and after queue completion.

## Validation and handoff

- [x] Run all Swift tests using the selected macOS SDK and linker sysroot; enable real local ffmpeg tests with bundled ffmpeg.
- [x] Run `python3 -m unittest discover -s Tests/BuildPipelineTests -v`, shell syntax checks, updater audit and `git diff --check`.
- [x] Build and run the normal app through `YOUTUBEJACK_PREPARE_RUNTIME=0 ./script/build_and_run.sh --verify` after checking the live queue is idle.
- [x] Verify corrected UI and file flows with isolated preferences and temporary files. Keep production update installation and publishing out of this task.
- [x] Report fixed findings, validation results and any limits. Release the awake lease before the final response.


## Completed validation

- All XCTest and Swift Testing targets passed with the selected SDK and linker sysroot. Real local yt-dlp filename expansion, two same-title video downloads and Opus-to-M4A conversion passed. Real ffmpeg embedded-caption tests passed for MP4 and WebM.
- Installer tests used temporary targets and test-only copies of the installer script with external trust/UI tools substituted. Valid launch confirmation succeeded; missing confirmation, another matching process, wrong token, wrong version and early process exit restored the previous target. Production trust checks were preserved.
- Native UI validation used an isolated defaults suite: drawer focus blocked background editing, a 2160p default survived a 1080p video, and queue menu actions moved items. The isolated app was closed and its preferences removed.
- Python build guards: 9 passed. Shell syntax and whitespace checks passed. Updater pattern audit: 0 issues, 0 warnings.
- No production update was installed or published. The normal local app runs without the preview flag.
