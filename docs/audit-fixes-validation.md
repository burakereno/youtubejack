# Audit fixes — 31 October 2026

All 15 findings were addressed in priority order. Existing user changes were preserved. No release or production update installation was performed.

| Finding | Result | Validation |
| --- | --- | --- |
| 1: Same-title videos collide | Video ID and a stable configuration fingerprint are part of the filename. | Real yt-dlp filename expansion and two local video downloads with distinct source bytes. |
| 2: Cleanup deletes completed files | Only UUID- and owner-marked private workspaces can be removed; published files are outside cleanup. | Completed-file preservation, mismatched ownership, symlink rejection and queue cleanup tests. |
| 3: Rapid pause/resume fails | Per-operation cancellation and pause identity survive an immediate resume. | Immediate and delayed resume regression cases using a controlled executable. |
| 4: Converted audio has a stale path | Audio and video both report the final `after_move` path. | Real Opus/WebM download, M4A conversion and ffmpeg decode. |
| 5: Old preview returns after clear/change | Request generations and current URL guard success/error mutations. | Delayed preview after clear and replacement URL while the first request is pending. |
| 6: Single-video format retry is blocked | A preview with unknown formats can retry extraction on the same URL. | First extraction fails; the second succeeds and enables queueing. |
| 7: Unavailable codec turns video into audio | Codec falls back to automatic before choosing an available video resolution; media mode stays video. | Saved H.264 preference against a VP9-only video. |
| 8: Different download settings are deduplicated | Quality, container and codec join audio/subtitle settings in request matching. | Separate quality, codec and container requests coexist; exact duplicates are suppressed. |
| 9: Current availability overwrites defaults | Explicit preference setters are separate from per-media reconciliation. | Resolution/container/codec preference tests and native UI verification. |
| 10: Drawer permits background typing | Background controls are disabled and hidden from accessibility; the native field respects enabled state. | Tab and typing while Settings was open left the link and preview unchanged. |
| 11: Split UTF-8 characters lose output | Stream readers accumulate bytes before decoding complete lines. | Turkish character split across process writes is preserved. |
| 12: Update file outlives its callback incorrectly | The file is moved synchronously to a private directory before callback exit. | Actual URLSession download from a loopback HTTP server, plus retention and HTTP rejection tests. |
| 13: Wrong process confirms update launch | A nonce/version/bundle/PID handshake and exact executable path plus startup liveness replace name-only detection. | Temporary installer targets: valid, missing, wrong-token, wrong-version and early-exit cases; another matching process cannot confirm launch. |
| 14: Update interrupts unfinished queue | Installation is blocked with pending/running/stopping work, new work is locked during preparation, and eligibility is rechecked before handoff. | Initial guards, changed queue during download, successful handoff and installer-failure unlock tests. |
| 15: Queue reordering requires dragging | Queue rows expose a native menu with labeled up/down actions and boundary disabling. | Model boundary tests, accessibility tree and native menu activation moving a queue item. |

The full Swift test suite, nine Python build guards, shell syntax validation, whitespace checks and updater audit passed. The updater audit reported zero issues and zero warnings. External live YouTube extraction was not needed for the deterministic local-media tests; signed/notarized production installation remains a release validation step.

The normal debug app is built with SDK 27 and a macOS 14 deployment target. Update preview is off. Temporary UI preferences were removed after validation.
