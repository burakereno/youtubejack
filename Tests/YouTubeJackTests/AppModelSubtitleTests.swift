import Foundation
import Testing
import YouTubeJackCore
@testable import YouTubeJack

@MainActor
struct AppModelSubtitleTests {
    @Test func legacyAutomaticDefaultMigratesOnceAndLaterOptInIsRemembered() throws {
        let fixture = try SubtitlePreferencesFixture()
        defer { fixture.cleanUp() }
        let saved = SubtitleOptions(isEnabled: true, languageCodes: ["en"], includesAutomatic: true, delivery: .separateFile, format: .vtt)
        fixture.defaults.set(try JSONEncoder().encode(saved), forKey: AppPreferenceKeys.subtitleOptions)

        let model = fixture.makeModel()
        #expect(model.subtitleOptions.includesAutomatic == false)
        #expect(model.subtitleOptions.isEnabled)
        #expect(model.subtitleOptions.languageCodes == ["en"])
        #expect(model.subtitleOptions.delivery == .separateFile)
        #expect(model.subtitleOptions.format == .vtt)
        let migrated = fixture.makeModel()
        #expect(migrated.subtitleOptions.includesAutomatic == false)

        model.subtitleOptions.includesAutomatic = true
        let optedIn = fixture.makeModel()
        #expect(optedIn.subtitleOptions.includesAutomatic)
        // The new default must not change the settings of already queued downloads.
        #expect(try JSONDecoder().decode(SubtitleOptions.self, from: JSONEncoder().encode(saved)) == saved)
    }

    @Test func disablingAutomaticCaptionsHidesOnlyAutomaticTracksAndRemovesTheirSelection() throws {
        let fixture = try SubtitlePreferencesFixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel()
        model.media = media(languages: [
            SubtitleLanguage(code: "tr", hasManual: false, hasAutomatic: true),
            SubtitleLanguage(code: "en", hasManual: true, hasAutomatic: true),
            SubtitleLanguage(code: "de", hasManual: true, hasAutomatic: false)
        ])
        model.subtitleOptions = SubtitleOptions(isEnabled: true, languageCodes: ["tr", "en"], includesAutomatic: true)
        #expect(model.selectableSubtitleLanguages.map(\.code) == ["tr", "en", "de"])

        model.includesAutomaticSubtitles = false
        #expect(model.selectableSubtitleLanguages.map(\.code) == ["en", "de"])
        #expect(model.subtitleOptions.languageCodes == ["en"])
        #expect(model.canIncludeSubtitles)
        #expect(model.hasOnlyAutomaticSubtitles == false)
        #expect(model.subtitleLanguages.count == 3, "Keep raw availability so the opt-in remains discoverable")
    }

    @Test func onlyAutomaticCaptionsRequireOptInAndCannotRemainSelectedWhenDisabled() throws {
        let fixture = try SubtitlePreferencesFixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel()
        model.media = media(languages: [SubtitleLanguage(code: "tr", hasManual: false, hasAutomatic: true)])
        model.subtitleOptions.isEnabled = true
        model.reconcileSubtitleSelection()
        #expect(model.hasOnlyAutomaticSubtitles)
        #expect(model.selectableSubtitleLanguages.isEmpty)
        #expect(model.subtitleOptions.languageCodes.isEmpty)
        #expect(model.canIncludeSubtitles == false)
        #expect(model.queuedSubtitleOptions.isEnabled == false)

        model.includesAutomaticSubtitles = true
        #expect(model.includesSubtitles)
        #expect(model.selectableSubtitleLanguages.map(\.code) == ["tr"])
        #expect(model.subtitleOptions.languageCodes == ["tr"])

        model.includesAutomaticSubtitles = false
        #expect(model.selectableSubtitleLanguages.isEmpty)
        #expect(model.subtitleOptions.languageCodes.isEmpty)
        #expect(model.includesSubtitles == false)
    }

    @Test func emptyAndUnknownAvailabilityDoNotClaimOnlyAutomaticCaptions() throws {
        let fixture = try SubtitlePreferencesFixture()
        defer { fixture.cleanUp() }
        let model = fixture.makeModel()
        model.media = media(languages: [])
        #expect(model.hasOnlyAutomaticSubtitles == false)

        model.media = media(languages: [SubtitleLanguage(code: "tr", hasManual: false, hasAutomatic: true)], isKnown: false)
        model.subtitleOptions.languageCodes = ["en"]
        model.reconcileSubtitleSelection()
        #expect(model.hasOnlyAutomaticSubtitles == false)
        #expect(model.subtitleOptions.languageCodes == ["en"], "Unknown metadata must preserve the saved selection")
    }

    private func media(languages: [SubtitleLanguage], isKnown: Bool = true) -> MediaInfo {
        MediaInfo(id: "AAAAAAAAAAA", sourceURL: "https://www.youtube.com/watch?v=AAAAAAAAAAA",
                  webpageURL: "https://www.youtube.com/watch?v=AAAAAAAAAAA", title: "Video", creator: "Creator",
                  duration: nil, thumbnailURL: nil, kind: .video, entryCount: 1,
                  subtitleAvailability: SubtitleAvailability(isKnown: isKnown, languages: languages))
    }
}

@MainActor
private struct SubtitlePreferencesFixture {
    let defaults: UserDefaults
    let suiteName: String
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    init() throws {
        suiteName = "YouTubeJack.SubtitleTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(directory.path, forKey: AppPreferenceKeys.downloadDirectory)
    }

    func makeModel() -> AppModel {
        AppModel(dependencyResolver: DependencyResolver(managedBinDirectory: directory, bundledBinDirectory: nil, systemSearchPaths: []), defaults: defaults)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
