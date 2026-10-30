import Foundation
import Testing
@testable import YouTubeJackCore

struct AudioLanguageTests {
    @Test func originalAudioIsIndependentOfDefaultDubbingAndLanguageListIsDeduplicated() {
        let availability = MediaFormatAvailability(isKnown: true, formats: [
            audio("fr-1", code: "fr", preference: 10, note: "French original"),
            audio("fr-2", code: "fr", preference: 10),
            audio("en", code: "en", preference: 5, note: "English (default)"),
            audio("tr", code: "tr", note: "Turkish auto-dubbed"),
            MediaFormat(id: "video", ext: "mp4", height: 1080, vcodec: "avc1", acodec: "none", language: "de")
        ], sourceLanguageCode: "en")
        #expect(availability.originalAudioLanguageCode == "fr")
        #expect(availability.audioLanguages.map(\.code) == ["tr", "en", "fr"])
        #expect(availability.audioLanguages.first?.isAutomatic == true)
        #expect(availability.audioLanguages.last?.isOriginal == true)
        #expect(AudioLanguageSelection.original.resolved(in: availability).formatFilter == "[language=fr]")
    }

    @Test func availabilityAndEstimatesRespectAudioLanguageAndContainer() {
        let availability = MediaFormatAvailability(isKnown: true, formats: [
            MediaFormat(id: "v-mp4", ext: "mp4", height: 1080, vcodec: "avc1", acodec: "none", filesize: 100),
            MediaFormat(id: "v-webm", ext: "webm", height: 1080, vcodec: "vp9", acodec: "none", filesize: 90),
            audio("fr", code: "fr", preference: 10, size: 10),
            MediaFormat(id: "tr", ext: "webm", height: nil, vcodec: "none", acodec: "opus", filesize: 20, language: "tr")
        ])
        let turkish = AudioLanguageSelection(languageCode: "tr")
        #expect(availability.isContainerAvailable(.mp4, for: .q1080, audioLanguage: turkish) == false)
        #expect(availability.isContainerAvailable(.webm, for: .q1080, audioLanguage: turkish))
        #expect(availability.preferredContainer(for: .q1080, preferred: .mp4, audioLanguage: turkish) == .webm)
        #expect(availability.estimatedDownloadSizeBytes(for: .q1080, container: .webm, audioLanguage: turkish) == 110)
        #expect(availability.estimatedDownloadSizeBytes(for: .audioM4A, container: .mp4, audioLanguage: turkish) == 20)
        #expect(availability.isResolutionAvailable(.q1080, audioLanguage: AudioLanguageSelection(languageCode: "de")) == false)
    }

    @Test func combinedOriginalAudioCannotSatisfyAnotherLanguage() {
        let availability = MediaFormatAvailability(isKnown: true, formats: [
            MediaFormat(id: "combined", ext: "mp4", height: 720, vcodec: "avc1", acodec: "mp4a", language: "fr", languagePreference: 10),
            audio("tr", code: "tr")
        ])
        #expect(availability.isResolutionAvailable(.q720))
        #expect(availability.isResolutionAvailable(.q720, audioLanguage: AudioLanguageSelection(languageCode: "tr")) == false)
    }

    @Test(arguments: QualityProfile.allCases, DownloadContainer.allCases)
    func everySelectorBranchRequiresRequestedLanguage(profile: QualityProfile, container: DownloadContainer) {
        let selector = profile.formatSelector(container: container, audioLanguage: AudioLanguageSelection(languageCode: "tr"))
        for branch in selector.split(separator: "/") { #expect(branch.contains("[language=tr]")) }
        #expect(selector.contains("bv*") == false)
    }

    @Test func unknownLanguageMetadataPreservesExistingSingleLanguageBehavior() {
        let availability = MediaFormatAvailability(isKnown: true, formats: [
            MediaFormat(id: "v", ext: "mp4", height: 720, vcodec: "avc1", acodec: "none"),
            MediaFormat(id: "a", ext: "m4a", height: nil, vcodec: "none", acodec: "mp4a")
        ])
        #expect(availability.audioLanguages.isEmpty)
        #expect(AudioLanguageSelection.original.resolved(in: availability) == .original)
        #expect(availability.isResolutionAvailable(.q720))
        #expect(MediaFormatAvailability.unknown.isResolutionAvailable(.q1080, audioLanguage: AudioLanguageSelection(languageCode: "tr")))
    }

    @Test func regionCodesAreExactAndUnsafeCodesAreRejected() {
        #expect(AudioLanguageSelection(languageCode: "en-US").formatFilter == "[language=en-US]")
        #expect(AudioLanguageSelection(languageCode: "tr]/best").languageCode == nil)
        #expect(AudioLanguageSelection(languageCode: "../tr").languageCode == nil)
    }

    private func audio(_ id: String, code: String, preference: Int = -1, note: String? = nil, size: Int64? = nil) -> MediaFormat {
        MediaFormat(id: id, ext: "m4a", height: nil, vcodec: "none", acodec: "mp4a", filesize: size, language: code, languagePreference: preference, formatNote: note)
    }
}
