import Foundation
import Observation
import Testing
@testable import YouTubeJackCore

struct AppLocalizationTests {
    @Test func defaultsToEnglishAndFallsBackFromUnsupportedValues() throws {
        let fixture = try LanguagePreferencesFixture()
        defer { fixture.clean() }
        let settings = AppLanguageSettings(defaults: fixture.defaults)
        fixture.defaults.set(["tr"], forKey: "AppleLanguages")
        #expect(settings.language == .english, "App language defaults to English independently of macOS language")
        fixture.defaults.set("unsupported", forKey: AppLanguageSettings.preferenceKey)
        #expect(settings.language == .english)
    }

    @Test func languagePersistsWithoutChangingDownloadPreferences() throws {
        let fixture = try LanguagePreferencesFixture()
        defer { fixture.clean() }
        let subtitles = try JSONEncoder().encode(SubtitleOptions(isEnabled: true, languageCodes: ["tr"]))
        fixture.defaults.set(subtitles, forKey: "subtitleOptions")
        fixture.defaults.set("q2160", forKey: "defaultQuality")
        AppLanguageSettings(defaults: fixture.defaults).language = .turkish
        let relaunched = AppLanguageSettings(defaults: fixture.defaults)
        #expect(relaunched.language == .turkish)
        #expect(fixture.defaults.data(forKey: "subtitleOptions") == subtitles)
        #expect(fixture.defaults.string(forKey: "defaultQuality") == "q2160")
        #expect(fixture.defaults.stringArray(forKey: "AppleLanguages") == ["tr"])
        relaunched.language = .english
        #expect(AppLanguageSettings(defaults: fixture.defaults).language == .english)
    }

    @Test func systemControlsUseEnglishByDefaultAtLaunch() throws {
        let fixture = try LanguagePreferencesFixture()
        defer { fixture.clean() }
        fixture.defaults.set(["tr"], forKey: "AppleLanguages")
        let settings = AppLanguageSettings(defaults: fixture.defaults)
        settings.applySystemLanguageAtLaunch()
        #expect(fixture.defaults.stringArray(forKey: "AppleLanguages") == ["en"])
        settings.language = .turkish
        AppLanguageSettings(defaults: fixture.defaults).applySystemLanguageAtLaunch()
        #expect(fixture.defaults.stringArray(forKey: "AppleLanguages") == ["tr"])
    }

    @Test func languageChangesNotifyObservers() async throws {
        let fixture = try LanguagePreferencesFixture()
        defer { fixture.clean() }
        let settings = AppLanguageSettings(defaults: fixture.defaults)
        await confirmation("Views observe a language change") { changed in
            withObservationTracking {
                #expect(settings.language == .english)
            } onChange: {
                changed()
            }
            settings.language = .turkish
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func staticAndInterpolatedTextUsesTheSelectedLanguage(language: AppLanguage) {
        let version = "1.2.3"
        let translated = L10n.string("New version available: %@", defaultValue: "New version available: \(version)", language: language)
        #expect(translated == (language == .english ? "New version available: 1.2.3" : "Yeni sürüm hazır: 1.2.3"))
        #expect(L10n.string("Settings", language: language) == (language == .english ? "Settings" : "Ayarlar"))
        let count = 3, total = 7
        #expect(L10n.string("%lld / %lld selected", defaultValue: "\(count) / \(total) selected", language: language)
            == (language == .english ? "3 / 7 selected" : "3 / 7 seçili"))
        let percent = 42, remaining = 5
        #expect(L10n.string("%lld%% · %lld videos remaining", defaultValue: "\(percent)% · \(remaining) videos remaining", language: language)
            == (language == .english ? "42% · 5 videos remaining" : "42% · 5 video kaldı"))
        let code: Int32 = 12
        #expect(L10n.string("%@ exited with code %d.", defaultValue: "\("yt-dlp") exited with code \(code).", language: language)
            == (language == .english ? "yt-dlp exited with code 12." : "yt-dlp 12 koduyla durdu."))
    }

    @Test func bothResourcesHaveMatchingKeysAndPlaceholderTypes() throws {
        let english = try table(.english), turkish = try table(.turkish)
        #expect(english.count > 200)
        #expect(Set(english.keys) == Set(turkish.keys))
        let placeholders = try NSRegularExpression(pattern: "%[@a-z]+")
        func types(_ text: String) -> [String] {
            let text = text.replacingOccurrences(of: "%%", with: "")
            return placeholders.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                Range($0.range, in: text).map { String(text[$0]) }
            }
        }
        for (key, value) in english {
            #expect(types(value) == types(try #require(turkish[key])), "Placeholder types must match for \(key)")
        }
    }

    @Test func fallbackPreservesUnknownText() {
        #expect(L10n.string("An untranslated fallback", language: .turkish) == "An untranslated fallback")
    }

    @Test(arguments: [1, 2])
    func englishCountsUseNativePluralRules(count: Int) {
        #expect(L10n.string("%lld items", defaultValue: "\(count) items", language: .english)
            == (count == 1 ? "1 item" : "2 items"))
        #expect(L10n.string("Add %lld videos to queue", defaultValue: "Add \(count) videos to queue", language: .english)
            == (count == 1 ? "Add 1 video to queue" : "Add 2 videos to queue"))
        let percentage = 42
        #expect(L10n.string("%lld%% · %lld videos remaining", defaultValue: "\(percentage)% · \(count) videos remaining", language: .english)
            == (count == 1 ? "42% · 1 video remaining" : "42% · 2 videos remaining"))
    }

    private func table(_ language: AppLanguage) throws -> [String: String] {
        let url = try #require(L10n.bundle(for: language).url(forResource: "Localizable", withExtension: "strings"))
        return try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
    }
}

private struct LanguagePreferencesFixture {
    let name = "YouTubeJack.LanguageTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: name))
    }

    func clean() { defaults.removePersistentDomain(forName: name) }
}
