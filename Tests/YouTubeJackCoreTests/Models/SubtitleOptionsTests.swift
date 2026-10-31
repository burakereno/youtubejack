import Foundation
import Testing
@testable import YouTubeJackCore

struct SubtitleOptionsTests {
    @Test func automaticCaptionsRequireExplicitOptIn() throws {
        let options = SubtitleOptions(isEnabled: true, languageCodes: ["tr"])
        let info = try JSONDecoder().decode(YTDLPInfo.self, from: Data(#"{"automatic_captions":{"tr":[{}]}}"#.utf8))
        #expect(options.includesAutomatic == false)
        #expect(info.selectedSubtitles(for: options).isEmpty)
    }

    @Test func metadataMergesSourcesAndPrioritizesTurkishAndEnglish() throws {
        let data = Data(#"{"subtitles":{"en":[{"ext":"vtt"}],"tr":[{"ext":"vtt"}],"de":[],"live_chat":[{}]},"automatic_captions":{"en":[{}],"fr":[{}],"../bad":[{}]}}"#.utf8)
        let info = try JSONDecoder().decode(YTDLPInfo.self, from: data)
        let languages = info.subtitleAvailability.languages
        #expect(languages.map(\.code) == ["tr", "en", "fr"])
        let english = try #require(languages.first(where: { $0.code == "en" }))
        #expect(english.hasManual)
        #expect(english.hasAutomatic)
        #expect(languages.last?.hasManual == false)
    }

    @Test func missingSubtitleMetadataIsKnownEmptyAfterFullExtraction() throws {
        let info = try JSONDecoder().decode(YTDLPInfo.self, from: Data("{}".utf8))
        #expect(info.subtitleAvailability.isKnown)
        #expect(info.subtitleAvailability.languages.isEmpty)
        #expect(SubtitleAvailability.unknown.isKnown == false)
    }

    @Test func selectionUsesExactSafeCodesAndRoundTripsPreferences() throws {
        let options = SubtitleOptions(isEnabled: true, languageCodes: ["tr", "tr", "pt.BR", "../bad", "en,all", "live_chat"], includesAutomatic: false, delivery: .separateFile, format: .vtt)
        #expect(options.languageCodes == ["pt.BR", "tr"])
        #expect(options.languageSelector == "pt\\.BR,tr")
        let saved = try JSONEncoder().encode(options)
        #expect(try JSONDecoder().decode(SubtitleOptions.self, from: saved) == options)
    }

    @Test func publisherTrackIDsAreGroupedAndPreferredOverAutomaticCaptions() throws {
        let data = Data(#"{"subtitles":{"en-eEY6OEpapPo":[{}],"zh-Hans":[{}]},"automatic_captions":{"en":[{}],"en-orig":[{}],"tr":[{}]}}"#.utf8)
        let info = try JSONDecoder().decode(YTDLPInfo.self, from: data)
        #expect(info.subtitleAvailability.languages.map(\.code) == ["tr", "en", "zh-Hans"])
        let tracks = info.selectedSubtitles(for: SubtitleOptions(isEnabled: true, languageCodes: ["en", "tr"], includesAutomatic: true))
        #expect(tracks.map(\.trackCode) == ["en-eEY6OEpapPo", "tr"])
        #expect(tracks.map(\.isAutomatic) == [false, true])
        let manualOnly = info.selectedSubtitles(for: SubtitleOptions(isEnabled: true, languageCodes: ["en", "tr"], includesAutomatic: false))
        #expect(manualOnly.map(\.trackCode) == ["en-eEY6OEpapPo"])
    }
}
