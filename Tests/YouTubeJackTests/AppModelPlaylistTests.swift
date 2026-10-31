import Foundation
import Testing
import YouTubeJackCore
@testable import YouTubeJack

@MainActor
struct AppModelPlaylistTests {
    @Test(.timeLimit(.minutes(1)))
    func playlistWithoutCaptionsOrDubsDisablesUnavailableOptions() async throws {
        let fixture = try PlaylistFixture(videos: [video("AAAAAAAAAAA"), video("BBBBBBBBBBB")])
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.subtitleOptions = SubtitleOptions(isEnabled: true, languageCodes: ["tr", "en"])
        await model.analyzeCurrentURL()
        #expect(model.isAnalyzingFormats)
        #expect(model.canAddToQueue == false)
        model.addSelectedToQueue()
        #expect(model.queue.isEmpty)
        try await fixture.finishAnalysis()

        #expect(model.audioLanguages.isEmpty)
        #expect(model.subtitleLanguages.isEmpty)
        #expect(model.canIncludeSubtitles == false)
        #expect(model.includesSubtitles == false)
        #expect(model.subtitleOptions.isEnabled, "Keep the user's saved preference for other videos")
        #expect(model.isQualityAvailable(.q2160) == false)
        #expect(model.isQualityAvailable(.q1080))
        #expect(model.isVideoCodecAvailable(.av1) == false)
        #expect(model.isContainerAvailable(.webm, for: .q1080) == false)
        #expect(model.canAddToQueue)

        model.addSelectedToQueue()
        #expect(model.queue.count == 2)
        #expect(model.queue.allSatisfy { $0.subtitles.isEnabled == false })
        #expect(model.queue.allSatisfy { $0.audioLanguage == AudioLanguageSelection(languageCode: "tr", isOriginal: true) })
        model.addSelectedToQueue()
        #expect(model.queue.count == 2, "Resolved original languages must still deduplicate")
    }

    @Test(.timeLimit(.minutes(1)))
    func selectedEntriesDriveOptionsAndQueuedItemsKeepTheirSettings() async throws {
        let fixture = try PlaylistFixture(videos: [
            video("AAAAAAAAAAA"),
            video("BBBBBBBBBBB", height: 2160, dub: "en", captions: ["en"])
        ])
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.subtitleOptions = SubtitleOptions(isEnabled: true, languageCodes: ["tr", "en"], delivery: .separateFile, format: .vtt)
        await model.analyzeCurrentURL()
        try await fixture.finishAnalysis()

        #expect(model.audioLanguages.map(\.code) == ["en"])
        #expect(model.subtitleLanguages.map(\.code) == ["en"])
        #expect(model.subtitleOptions.languageCodes == ["en"])
        #expect(model.isQualityAvailable(.q2160))
        model.updateSelectedAudioLanguage(AudioLanguageSelection(languageCode: "en"))
        model.updateSelectedQuality(.q2160)
        model.updateSelectedVideoCodec(.h264)
        let selectedSubtitles = model.queuedSubtitleOptions
        model.addSelectedToQueue()
        #expect(model.queue.count == 2)
        #expect(model.queue.allSatisfy { $0.quality == .q2160 && $0.container == .mp4 && $0.videoCodecPreference == .h264 })
        #expect(model.queue.allSatisfy { $0.audioLanguage.languageCode == "en" && $0.subtitles == selectedSubtitles })
        #expect(model.formatSelectionDetail.contains("1/2"))

        // Deselecting the only captioned/dubbed video updates controls from cached metadata.
        model.playlistEntries[1].isSelected = false
        #expect(model.isAnalyzingFormats == false)
        #expect(model.audioLanguages.isEmpty)
        #expect(model.subtitleLanguages.isEmpty)
        #expect(model.includesSubtitles == false)
        #expect(model.selectedAudioLanguage == .original)
        #expect(model.isQualityAvailable(.q2160) == false)
        #expect(model.queue.allSatisfy { $0.audioLanguage.languageCode == "en" && $0.subtitles == selectedSubtitles })

        model.playlistEntries[1].isSelected = true
        #expect(model.isAnalyzingFormats == false)
        #expect(model.audioLanguages.map(\.code) == ["en"])
        #expect(model.includesSubtitles)
        model.setAllPlaylistEntries(false)
        #expect(model.canAddToQueue == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func metadataFailureStaysUnknownAndDoesNotEraseCaptionPreferences() async throws {
        let fixture = try PlaylistFixture(videos: [video("AAAAAAAAAAA"), video("BBBBBBBBBBB")], failingIDs: ["BBBBBBBBBBB"])
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.subtitleOptions = SubtitleOptions(isEnabled: true, languageCodes: ["en"])
        await model.analyzeCurrentURL()
        try await fixture.finishAnalysis()

        #expect(model.playlistAvailability.failedCount == 1)
        #expect(model.subtitleAvailability.isKnown == false)
        #expect(model.canIncludeSubtitles)
        #expect(model.queuedSubtitleOptions.isEnabled)
        #expect(model.queuedSubtitleOptions.languageCodes == ["en"])
        #expect(model.formatSelectionDetail.contains("kontrol edilemedi"))
        #expect(model.canAddToQueue)
        try FileManager.default.removeItem(at: fixture.directory.appendingPathComponent("failure-BBBBBBBBBBB"))
        await model.analyzeCurrentURL()
        try await fixture.finishAnalysis()
        #expect(model.playlistAvailability.failedCount == 0)
        #expect(model.subtitleAvailability.isKnown)
        #expect(model.canIncludeSubtitles == false)
        model.clearCurrentInput()
        #expect(model.playlistMetadata.isEmpty)
        #expect(model.failedPlaylistURLs.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func changingSelectionDuringAnalysisDoesNotApplyCancelledResults() async throws {
        let fixture = try PlaylistFixture(videos: [video("AAAAAAAAAAA"), video("BBBBBBBBBBB", dub: "en", captions: ["en"])])
        defer { fixture.cleanUp() }
        let model = fixture.model
        await model.analyzeCurrentURL()
        model.playlistEntries[1].isSelected = false
        try await fixture.finishAnalysis()
        #expect(model.audioLanguages.isEmpty)
        #expect(model.subtitleLanguages.isEmpty)
        #expect(model.playlistAvailability.checkedCount == 1)

        model.playlistEntries[1].isSelected = true
        try await fixture.finishAnalysis()
        #expect(model.audioLanguages.map(\.code) == ["en"])
        #expect(model.subtitleLanguages.map(\.code) == ["en"])
        #expect(model.playlistAvailability.checkedCount == 2)
        model.clearCurrentInput()
        #expect(model.isAnalyzingFormats == false)
    }

    @Test(.timeLimit(.minutes(1)))
    func automaticCaptionsRemainUsableWhenPublisherCaptionsAreAbsent() async throws {
        let fixture = try PlaylistFixture(videos: [video("AAAAAAAAAAA", automaticCaptions: ["tr"])])
        defer { fixture.cleanUp() }
        let model = fixture.model
        model.subtitleOptions = SubtitleOptions(isEnabled: true, languageCodes: ["en"], includesAutomatic: false)
        await model.analyzeCurrentURL()
        try await fixture.finishAnalysis()
        #expect(model.canIncludeSubtitles == false)
        #expect(model.includesSubtitles == false)
        #expect(model.queuedSubtitleOptions.isEnabled == false)
        #expect(model.subtitleLanguages.first?.hasManual == false)
        #expect(model.subtitleLanguages.first?.hasAutomatic == true)
        model.subtitleOptions.includesAutomatic = true
        model.reconcileSubtitleSelection()
        #expect(model.canIncludeSubtitles)
        #expect(model.includesSubtitles)
        #expect(model.subtitleOptions.languageCodes == ["tr"])
        model.addSelectedToQueue()
        #expect(model.queue.first?.subtitles.includesAutomatic == true)
        #expect(model.queue.first?.subtitles.languageCodes == ["tr"])
    }

    @Test(.timeLimit(.minutes(1)))
    func streamsFromDifferentEntriesCannotCreateAnAvailableVideoFormat() async throws {
        var pictureOnly = video("AAAAAAAAAAA")
        pictureOnly["formats"] = (pictureOnly["formats"] as? [[String: Any]])?.filter { $0["acodec"] as? String == "none" }
        var soundOnly = video("BBBBBBBBBBB")
        soundOnly["formats"] = (soundOnly["formats"] as? [[String: Any]])?.filter { $0["vcodec"] as? String == "none" }
        let fixture = try PlaylistFixture(videos: [pictureOnly, soundOnly])
        defer { fixture.cleanUp() }
        await fixture.model.analyzeCurrentURL()
        try await fixture.finishAnalysis()
        #expect(fixture.model.isQualityAvailable(.q1080) == false)
        #expect(fixture.model.isContainerAvailable(.mp4, for: .q1080) == false)
        #expect(fixture.model.isQualityAvailable(.audioM4A))
    }

    private func video(_ id: String, height: Int = 1080, dub: String? = nil, captions: [String] = [], automaticCaptions: [String] = []) -> [String: Any] {
        var formats: [[String: Any]] = [
            ["format_id": "video", "ext": "mp4", "height": height, "vcodec": "avc1", "acodec": "none"],
            ["format_id": "audio-tr", "ext": "m4a", "vcodec": "none", "acodec": "mp4a", "language": "tr", "language_preference": 10]
        ]
        if let dub {
            formats.append(["format_id": "audio-dub", "ext": "m4a", "vcodec": "none", "acodec": "mp4a", "language": dub])
        }
        return [
            "id": id, "title": id, "formats": formats,
            "subtitles": Dictionary(uniqueKeysWithValues: captions.map { ($0, [["ext": "vtt"]]) }),
            "automatic_captions": Dictionary(uniqueKeysWithValues: automaticCaptions.map { ($0, [["ext": "vtt"]]) })
        ]
    }
}

@MainActor
private struct PlaylistFixture {
    let model: AppModel
    let directory: URL
    let defaults: UserDefaults
    let suiteName: String

    init(videos: [[String: Any]], failingIDs: Set<String> = []) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "YouTubeJack.PlaylistTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.set(directory.path, forKey: AppPreferenceKeys.downloadDirectory)
        let ids = try videos.map { try #require($0["id"] as? String) }
        let playlist: [String: Any] = ["id": "PLtest", "title": "Test playlist", "entries": ids.map { ["id": $0, "title": $0] }]
        try JSONSerialization.data(withJSONObject: playlist).write(to: directory.appendingPathComponent("playlist.json"))
        var cases = ""
        for (id, info) in zip(ids, videos) {
            try JSONSerialization.data(withJSONObject: info).write(to: directory.appendingPathComponent("\(id).json"))
            if failingIDs.contains(id) {
                try Data().write(to: directory.appendingPathComponent("failure-\(id)"))
            }
            let command = "if [ -f \"${0%/*}/failure-\(id)\" ]; then exit 1; fi; exec /bin/cat \"${0%/*}/\(id).json\""
            cases += "*v=\(id)) /bin/sleep 0.05; \(command);;\n"
        }
        let executable = directory.appendingPathComponent("yt-dlp")
        try """
        #!/bin/sh
        for arg do
            case "$arg" in --version) echo 2026.10.30; exit 0;; esac
        done
        case "$arg" in
        *list=*) exec /bin/cat "${0%/*}/playlist.json";;
        \(cases)
        *) exit 1;;
        esac
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        model = AppModel(dependencyResolver: DependencyResolver(managedBinDirectory: directory, bundledBinDirectory: nil, systemSearchPaths: []), defaults: defaults)
        model.inputURL = "https://www.youtube.com/playlist?list=PLtest"
    }

    func finishAnalysis() async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while model.isAnalyzingFormats, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(model.isAnalyzingFormats == false, "Playlist extraction did not finish")
    }

    func cleanUp() {
        model.clearCurrentInput()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}
