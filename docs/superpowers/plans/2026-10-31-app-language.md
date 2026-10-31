# App Language Implementation Plan

**Goal:** Add English and Turkish app language selection, with English as the default regardless of system language.

**Architecture:** Store a dedicated app-language preference, observed through Observation and read by shared Foundation localization helpers. Keep translations in the core SwiftPM resource bundle so views, native controls, and service errors use the same language. Package that resource bundle in both development and release apps.

**Tech Stack:** SwiftUI, Foundation localization, Observation, SwiftPM, Swift Testing.

## Constraints

- Keep macOS 14 minimum support and SDK 27 build verification.
- Apply language changes immediately without recreating the app model or queue.
- Persist only the app-language preference; preserve audio/subtitle and download preferences.
- Cover native controls, menus, accessibility labels, service errors, and localized language names.

## Tasks

- [x] Add `AppLanguage`, persistent observable `AppLanguageSettings`, and `L10n` in `Sources/YouTubeJackCore/Support/AppLocalization.swift`; add English/Turkish `.strings` resources and `Package.swift` configuration.
- [x] Translate app-owned user-facing text in `Sources/YouTubeJack` and `Sources/YouTubeJackCore`; keep URLs, tool arguments, media titles, filenames, and log protocols verbatim.
- [x] Add an English/Türkçe selector to `SettingsView.swift`; provide the selected locale in `YouTubeJackApp.swift`; update native URL-field text during view updates.
- [x] Copy SwiftPM resource bundles in `script/build_and_run.sh` and `scripts/build-app.sh`; set English development region and supported localizations.
- [x] Add isolated tests for default/fallback language, preference persistence, observation, interpolated translations, translated model/error text, and resources in packaged builds.
- [x] Run the Swift and build-guard suites, then build and inspect both languages locally. Do not publish a release as part of this feature request.

## Validation

- All Swift suites passed: 31 XCTest tests, 45 app Swift Testing tests, and 40 core Swift Testing tests, including both language resources, typed interpolation, plural rules, persistence, and observation.
- Real local yt-dlp/ffmpeg download and subtitle integration tests passed.
- All 9 SDK build-guard tests passed; shell syntax and `git diff --check` passed.
- Debug and release app bundles built with SDK 27 and the macOS 14 minimum.
- Native UI verified English by default, immediate Turkish text updates, and Turkish persistence after quitting and reopening. System menus also adopted Turkish after reopening.
- Packaged-app cold launch succeeded while all build-product localization bundles were temporarily hidden, proving the app uses its bundled translations. Build resources were restored afterward.
- Isolated test app and its preference domain were removed. No release was published.
