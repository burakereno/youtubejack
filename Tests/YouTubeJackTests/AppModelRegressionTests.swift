import Foundation
import Testing
import YouTubeJackCore
@testable import YouTubeJack

@MainActor
struct AppModelRegressionTests {
    @Test func formatAndCodecDefaultsSurviveUnavailableCurrentVideoOptions() throws {
        let fixture = try RegressionFixture()
        defer { fixture.clean() }
        let model = fixture.model()
        model.media = fixture.media()
        model.updateDefaultContainer(.webm)
        #expect(fixture.defaults.string(forKey: AppPreferenceKeys.defaultContainer) == "webm")
        #expect(model.selectedContainer == .mp4)
        model.updateDefaultVideoCodec(.av1)
        #expect(fixture.defaults.string(forKey: AppPreferenceKeys.defaultVideoCodec) == "av1")
        #expect(model.selectedVideoCodec == .automatic)
        #expect(model.selectedQuality.isVideoQuality)
    }

    @Test func differentContainersOfTheSameVideoCanBeQueuedSeparately() throws {
        let fixture = try RegressionFixture()
        defer { fixture.clean() }
        let model = fixture.model()
        let mp4 = fixture.media()
        let webm = fixture.media(codec: "vp9", container: "webm")
        model.media = MediaInfo(id: mp4.id, sourceURL: mp4.sourceURL, webpageURL: mp4.webpageURL, title: mp4.title,
                                creator: mp4.creator, duration: mp4.duration, thumbnailURL: nil, kind: .video, entryCount: 1,
                                formatAvailability: MediaFormatAvailability(isKnown: true, formats: mp4.formatAvailability.formats + webm.formatAvailability.formats))
        model.updateSelectedContainer(.mp4)
        model.addSelectedToQueue()
        model.updateSelectedContainer(.webm)
        model.addSelectedToQueue()
        model.addSelectedToQueue()
        #expect(model.queue.map(\.container) == [.mp4, .webm])
    }

    @Test func unavailableSavedCodecCannotChangeVideoIntoAudioOrOverwriteDefaults() throws {
        let fixture = try RegressionFixture()
        defer { fixture.clean() }
        fixture.defaults.set("h264", forKey: AppPreferenceKeys.defaultVideoCodec)
        fixture.defaults.set("q2160", forKey: AppPreferenceKeys.defaultQuality)
        let model = fixture.model()
        model.media = fixture.media(codec: "vp9", container: "webm")
        model.updateSelectedQuality(.q1080)
        #expect(model.selectedQuality.isVideoQuality)
        #expect(model.selectedVideoCodec == .automatic)
        #expect(model.canAddToQueue)
        #expect(fixture.defaults.string(forKey: AppPreferenceKeys.defaultQuality) == "q2160")
        #expect(fixture.defaults.string(forKey: AppPreferenceKeys.defaultVideoCodec) == "h264")
        model.updateDefaultQuality(.q2160)
        #expect(fixture.defaults.string(forKey: AppPreferenceKeys.defaultQuality) == "q2160")
        #expect(model.selectedQuality.isVideoQuality)
    }

    @Test func differentQualityAndCodecRequestsCanCoexistButExactDuplicatesCannot() throws {
        let fixture = try RegressionFixture()
        defer { fixture.clean() }
        let model = fixture.model()
        model.media = fixture.media()
        model.updateSelectedQuality(.q720)
        model.addSelectedToQueue()
        model.updateSelectedQuality(.q1080)
        model.addSelectedToQueue()
        model.updateSelectedVideoCodec(.h264)
        model.addSelectedToQueue()
        model.addSelectedToQueue()
        #expect(model.queue.count == 3)
        #expect(model.queue.map(\.quality) == [.q720, .q1080, .q1080])
    }

    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func pausingAndResumingKeepsTheJobRetryable(immediate: Bool) async throws {
        let fixture = try RegressionFixture()
        defer { fixture.clean() }
        try fixture.executable("""
        #!/bin/sh
        root="${0%/*}"
        for arg do
          if [ "$arg" = "--version" ]; then echo 2026.10.30; exit 0; fi
        done
        if [ ! -f "$root/started" ]; then
          touch "$root/started"
          /bin/sleep 0.3
        else
          printf 'media' > "$root/finished.mp4"
          printf 'download-output:%s/finished.mp4\\n' "$root"
        fi
        """)
        let model = fixture.model()
        model.queue = [DownloadItem(url: fixture.url, title: "Pause", quality: .q1080, container: .mp4)]
        model.resumeQueue()
        try await waitUntil { FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("started").path) }
        model.pauseQueue()
        if immediate == false {
            try await waitUntil { model.isQueueProcessing == false }
            #expect(model.queue.first?.status == .pending)
        }
        model.resumeQueue()
        try await waitUntil { model.queue.first?.status == .completed || model.queue.first?.status == .failed }
        try await waitUntil { model.isQueueProcessing == false }
        #expect(model.queue.first?.status == .completed)
        #expect(model.queue.first?.errorMessage == nil)
    }

    @Test func clearingARequestDoesNotAllowItsDelayedPreviewToReturn() async throws {
        let fixture = try RegressionFixture()
        defer { fixture.clean() }
        let source = DelayedPreviewSource()
        let model = AppModel(dependencyResolver: fixture.resolver, defaults: fixture.defaults, metadataClient: MetadataClient(
            fetchPreview: { try await source.fetch($0) }, fetch: { _ in throw CancellationError() }
        ))
        model.inputURL = fixture.url
        let request = Task { await model.analyzeCurrentURL() }
        try await source.waitForRequest()
        model.clearCurrentInput()
        await source.finish(fixture.media())
        await request.value
        #expect(model.media == nil)
        #expect(model.inputURL.isEmpty)
        #expect(model.statusMessage == nil)
        #expect(model.isAnalyzing == false)
    }

    @Test func failedSingleVideoFormatExtractionCanBeRetriedForTheSameURL() async throws {
        let fixture = try RegressionFixture()
        defer { fixture.clean() }
        let known = fixture.media()
        let preview = fixture.media(known: false)
        let source = RetryingFormatSource(media: known)
        let model = AppModel(dependencyResolver: fixture.resolver, defaults: fixture.defaults, metadataClient: MetadataClient(
            fetchPreview: { _ in MetadataResult(media: preview, entries: []) }, fetch: { try await source.fetch($0) }
        ))
        model.inputURL = fixture.url
        await model.analyzeCurrentURL()
        try await waitUntil { model.isAnalyzingFormats == false }
        #expect(model.canAddToQueue == false)
        await model.analyzeCurrentURL()
        try await waitUntil { model.isAnalyzingFormats == false }
        #expect(model.media?.formatAvailability.isKnown == true)
        #expect(model.canAddToQueue)
        #expect(model.statusMessage == nil)
    }

    @Test func replacingTheURLSchedulesNewAnalysisAndOldResultsCannotReplaceIt() async throws {
        let fixture = try RegressionFixture()
        defer { fixture.clean() }
        let source = DelayedPreviewSource()
        let old = fixture.media()
        let replacement = fixture.media(id: "BBBBBBBBBBB")
        let model = AppModel(dependencyResolver: fixture.resolver, defaults: fixture.defaults, metadataClient: MetadataClient(
            fetchPreview: { url in
                if url == replacement.sourceURL { return MetadataResult(media: replacement, entries: []) }
                return try await source.fetch(url)
            }, fetch: { _ in throw CancellationError() }
        ))
        model.inputURL = fixture.url
        let first = Task { await model.analyzeCurrentURL() }
        try await source.waitForRequest()
        model.inputURL = replacement.sourceURL
        model.scheduleAnalyzeForCurrentURL()
        try await waitUntil { model.media?.id == replacement.id }
        await source.finish(old)
        await first.value
        #expect(model.media?.id == replacement.id)
        #expect(model.isAnalyzing == false)
        #expect(model.statusMessage == nil)
    }

    @Test func keyboardReorderingRespectsQueueBoundariesAndRunningJobs() throws {
        let fixture = try RegressionFixture()
        defer { fixture.clean() }
        let model = fixture.model()
        let first = DownloadItem(url: fixture.url, title: "First", quality: .q1080, container: .mp4)
        let second = DownloadItem(url: fixture.url, title: "Second", quality: .q720, container: .mp4)
        let running = DownloadItem(url: fixture.url, title: "Running", quality: .best, container: .mp4, status: .running)
        model.queue = [first, second, running]
        #expect(model.canMoveUp(first) == false)
        #expect(model.canMoveDown(running) == false)
        #expect(model.canMoveUp(running) == false)
        model.moveQueueItemUp(second)
        #expect(model.queue.map(\.id) == [second.id, first.id, running.id])
        model.moveQueueItemDown(second)
        #expect(model.queue.map(\.id) == [first.id, second.id, running.id])
    }

    @Test func clearingFailedJobsPreservesFinishedFilesAndRemovesOnlyOwnedPartials() throws {
        let fixture = try RegressionFixture()
        defer { fixture.clean() }
        let model = fixture.model()
        let final = fixture.root.appendingPathComponent("existing.mp4")
        try Data("finished user file".utf8).write(to: final)
        var item = DownloadItem(url: fixture.url, title: "Fixture", quality: .q1080, container: .mp4, status: .failed, outputPath: final.path)
        let workspace = DownloadWorkspace(outputDirectory: fixture.root.path, itemID: item.id)
        try workspace.prepare()
        try Data("partial".utf8).write(to: workspace.directory.appendingPathComponent("partial.mp4.part"))
        item.temporaryDirectoryPath = workspace.directory.path
        model.queue = [item]
        model.clearFinished()
        #expect(model.queue.isEmpty)
        #expect(try String(contentsOf: final) == "finished user file")
        #expect(FileManager.default.fileExists(atPath: workspace.directory.path) == false)
    }
}

@MainActor
private struct RegressionFixture {
    let root: URL
    let defaults: UserDefaults
    let suite: String
    let url = "https://www.youtube.com/watch?v=AAAAAAAAAAA"
    var resolver: DependencyResolver { DependencyResolver(managedBinDirectory: root, bundledBinDirectory: nil, systemSearchPaths: []) }

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "YouTubeJack.RegressionTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(root.path, forKey: AppPreferenceKeys.downloadDirectory)
    }

    func model() -> AppModel { AppModel(dependencyResolver: resolver, defaults: defaults) }

    func executable(_ script: String) throws {
        let file = root.appendingPathComponent("yt-dlp")
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }

    func media(codec: String = "avc1", container: String = "mp4", known: Bool = true, id: String = "AAAAAAAAAAA") -> MediaInfo {
        let videoURL = "https://www.youtube.com/watch?v=\(id)"
        return MediaInfo(id: id, sourceURL: videoURL, webpageURL: videoURL, title: "Fixture", creator: "Test", duration: 1,
                  thumbnailURL: nil, kind: .video, entryCount: 1,
                  formatAvailability: MediaFormatAvailability(isKnown: known, formats: [
                    MediaFormat(id: "720", ext: container, height: 720, vcodec: codec, acodec: "none"),
                    MediaFormat(id: "1080", ext: container, height: 1080, vcodec: codec, acodec: "none"),
                    MediaFormat(id: "audio", ext: container == "mp4" ? "m4a" : "webm", height: nil, vcodec: "none", acodec: container == "mp4" ? "mp4a" : "opus")
                  ]), subtitleAvailability: SubtitleAvailability(isKnown: true, languages: []))
    }

    func clean() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while condition() == false, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
    try #require(condition())
}

private actor DelayedPreviewSource {
    private var continuation: CheckedContinuation<MetadataResult, any Error>?
    func fetch(_ url: String) async throws -> MetadataResult {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func waitForRequest() async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while continuation == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try #require(continuation != nil)
    }
    func finish(_ media: MediaInfo) { continuation?.resume(returning: MetadataResult(media: media, entries: [])); continuation = nil }
}

private actor RetryingFormatSource {
    let media: MediaInfo
    private var calls = 0
    init(media: MediaInfo) { self.media = media }
    func fetch(_ url: String) throws -> MetadataResult {
        calls += 1
        if calls == 1 { throw AppError.metadataDecodeFailed }
        return MetadataResult(media: media, entries: [])
    }
}
