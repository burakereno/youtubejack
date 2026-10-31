import Foundation
import Testing
@testable import YouTubeJack

@MainActor
struct UpdateCheckerTests {
    @Test
    func startupChecksImmediatelyAndTheTimerChecksAgainAfterTwoHours() async throws {
        let fixture = try UpdateBundleFixture(production: true)
        let clock = UpdateTestClock()
        let source = ReleaseSourceStub(result: .success(try release()))
        let scheduler = UpdateTimerStub()
        let checker = UpdateChecker(bundle: fixture.bundle, now: { clock.date }, fetchReleaseInfo: source.fetch, timerFactory: scheduler.schedule)
        defer { checker.stop(); fixture.cleanUp() }

        await checker.start()
        #expect(source.callCount == 1)
        #expect(scheduler.intervals == [7200])
        #expect(checker.updateAvailable)
        #expect(checker.shouldShowToolbarUpdate)
        #expect(checker.isChecking == false)

        clock.date.addTimeInterval(7200)
        await scheduler.fire()
        #expect(source.callCount == 2)
        #expect(checker.lastCheckCompletedAt == clock.date)

        checker.stop()
        #expect(scheduler.timer?.isValid == false)
        await scheduler.fire()
        #expect(source.callCount == 2)
    }

    @Test
    func startingTwiceDoesNotCreateAnotherTimerOrCheck() async throws {
        let fixture = try UpdateBundleFixture(production: true)
        let source = ReleaseSourceStub(result: .success(try release()))
        let scheduler = UpdateTimerStub()
        let checker = UpdateChecker(bundle: fixture.bundle, fetchReleaseInfo: source.fetch, timerFactory: scheduler.schedule)
        defer { checker.stop(); fixture.cleanUp() }

        await checker.start()
        await checker.start()
        #expect(source.callCount == 1)
        #expect(scheduler.intervals == [7200])
    }

    @Test
    func automaticFailuresStayQuietAndManualFailuresAreVisible() async throws {
        let fixture = try UpdateBundleFixture(production: true)
        let source = ReleaseSourceStub(result: .failure(.badStatus(503)))
        let scheduler = UpdateTimerStub()
        let checker = UpdateChecker(bundle: fixture.bundle, fetchReleaseInfo: source.fetch, timerFactory: scheduler.schedule)
        defer { checker.stop(); fixture.cleanUp() }

        await checker.start()
        #expect(checker.lastError == nil)
        #expect(checker.isUpToDate == false)
        #expect(checker.shouldShowToolbarUpdate == false)

        await checker.checkForUpdates(force: true)
        #expect(checker.lastError?.contains("503") == true)
        #expect(checker.isChecking == false)
    }

    @Test
    func failedAutomaticRecheckPreservesTheLastValidatedUpdate() async throws {
        let fixture = try UpdateBundleFixture(production: true)
        let clock = UpdateTestClock()
        let source = ReleaseSourceStub(result: .success(try release()))
        let scheduler = UpdateTimerStub()
        let checker = UpdateChecker(bundle: fixture.bundle, now: { clock.date }, fetchReleaseInfo: source.fetch, timerFactory: scheduler.schedule)
        defer { checker.stop(); fixture.cleanUp() }

        await checker.start()
        let validatedURL = checker.downloadURL
        source.result = .failure(.badStatus(503))
        clock.date.addTimeInterval(7200)
        await scheduler.fire()

        #expect(checker.latestVersion == "1.1.0")
        #expect(checker.downloadURL == validatedURL)
        #expect(checker.lastError == nil)
        #expect(checker.shouldShowToolbarUpdate)
    }

    @Test(arguments: [false, true])
    func realToolbarUpdatesRespectTheProductionBuild(production: Bool) async throws {
        let fixture = try UpdateBundleFixture(production: production)
        let source = ReleaseSourceStub(result: .success(try release()))
        let scheduler = UpdateTimerStub()
        let checker = UpdateChecker(bundle: fixture.bundle, fetchReleaseInfo: source.fetch, timerFactory: scheduler.schedule)
        defer { checker.stop(); fixture.cleanUp() }

        await checker.start()
        #expect(checker.updateAvailable == production)
        #expect(checker.updatesEnabled == production)
        #expect(checker.shouldShowToolbarUpdate == production)
    }

    @Test
    func currentVersionDoesNotShowAnUpdateButton() async throws {
        let fixture = try UpdateBundleFixture(production: true)
        let source = ReleaseSourceStub(result: .success(try release(version: "1.0.0")))
        let scheduler = UpdateTimerStub()
        let checker = UpdateChecker(bundle: fixture.bundle, fetchReleaseInfo: source.fetch, timerFactory: scheduler.schedule)
        defer { checker.stop(); fixture.cleanUp() }

        await checker.start()
        #expect(checker.isUpToDate)
        #expect(checker.lastCheckCompletedAt != nil)
        #expect(checker.shouldShowToolbarUpdate == false)
    }

    @Test
    func localToolbarPreviewNeverEnablesInstallationOrInventsReleaseMetadata() throws {
        let fixture = try UpdateBundleFixture(production: false)
        defer { fixture.cleanUp() }
        let checker = UpdateChecker(bundle: fixture.bundle, isPreviewingUpdate: true)

        #expect(checker.shouldShowToolbarUpdate)
        #expect(checker.updateAvailable == false)
        #expect(checker.updatesEnabled == false)
        #expect(checker.latestVersion == nil)
        #expect(checker.downloadURL == nil)

        checker.downloadAndInstall()
        #expect(checker.isDownloading == false)
        #expect(checker.lastError?.contains("disabled") == true)
    }

    @Test
    func releaseRedirectBuildsBothExpectedAssetURLs() throws {
        let info = try release(version: "1.2.3")
        #expect(info.version == "1.2.3")
        #expect(info.downloadURL.absoluteString == "https://github.com/burakereno/youtubejack/releases/download/v1.2.3/YouTubeJack.dmg")
        #expect(info.manifestURL.absoluteString == "https://github.com/burakereno/youtubejack/releases/download/v1.2.3/YouTubeJack.dmg.update.json")
    }

    @Test(arguments: [
        "https://github.com/burakereno/youtubejack/releases/latest",
        "https://example.com/burakereno/youtubejack/releases/tag/v1.2.3",
        "https://github.com/another-owner/youtubejack/releases/tag/v1.2.3",
        "https://github.com/burakereno/another-app/releases/tag/v1.2.3",
        "https://github.com/burakereno/youtubejack/releases/tag/not-a-version"
    ])
    func unexpectedReleaseRedirectsAreRejected(value: String) throws {
        let url = try #require(URL(string: value))
        #expect(throws: UpdateError.missingVersion) {
            try UpdateChecker.releaseInfo(fromResolvedLatestURL: url)
        }
    }

    @Test
    func releaseChecksValidateTheDMGAndManifestWithHEADRequests() async throws {
        let transport = ReleaseTransportStub()
        let info = try await UpdateChecker.fetchLatestReleaseInfo(transport: transport.data)
        #expect(info.version == "1.2.3")
        #expect(transport.requests.map(\.httpMethod) == ["HEAD", "HEAD", "HEAD"])
        #expect(transport.requests.compactMap { $0.url?.lastPathComponent } == ["latest", "YouTubeJack.dmg", "YouTubeJack.dmg.update.json"])
    }

    @Test(arguments: ["YouTubeJack.dmg", "YouTubeJack.dmg.update.json"])
    func aMissingAssetPreventsTheReleaseFromBeingAdvertised(asset: String) async {
        let transport = ReleaseTransportStub(missingAsset: asset)
        await #expect(throws: UpdateError.missingAsset(asset)) {
            try await UpdateChecker.fetchLatestReleaseInfo(transport: transport.data)
        }
    }

    @Test(arguments: [("1.10.0", "1.9.9"), ("1.0.10", "1.0.9"), ("2.0.0", "1.99.99")])
    func versionComparisonIsNumeric(candidate: String, installed: String) {
        #expect(UpdateChecker.compare(candidate, isNewerThan: installed))
        #expect(UpdateChecker.compare(installed, isNewerThan: candidate) == false)
        #expect(UpdateChecker.compare(installed, isNewerThan: installed) == false)
    }

    private func release(version: String = "1.1.0") throws -> UpdateReleaseInfo {
        let url = try #require(URL(string: "https://github.com/burakereno/youtubejack/releases/tag/v\(version)"))
        return try UpdateChecker.releaseInfo(fromResolvedLatestURL: url)
    }
}

@MainActor
private final class ReleaseSourceStub {
    var result: Result<UpdateReleaseInfo, UpdateError>
    private(set) var callCount = 0

    init(result: Result<UpdateReleaseInfo, UpdateError>) {
        self.result = result
    }

    func fetch() async throws -> UpdateReleaseInfo {
        callCount += 1
        return try result.get()
    }
}

@MainActor
private final class UpdateTestClock {
    var date = Date(timeIntervalSince1970: 1_700_000_000)
}

@MainActor
private final class UpdateTimerStub {
    private var action: (@MainActor @Sendable () async -> Void)?
    private(set) var timer: Timer?
    private(set) var intervals: [TimeInterval] = []

    func schedule(interval: TimeInterval, action: @escaping @MainActor @Sendable () async -> Void) -> Timer {
        intervals.append(interval)
        self.action = action
        let timer = Timer(timeInterval: interval, repeats: true) { _ in }
        self.timer = timer
        return timer
    }

    func fire() async {
        guard timer?.isValid == true else { return }
        await action?()
    }
}

@MainActor
private struct UpdateBundleFixture {
    let directory: URL
    let bundle: Bundle

    init(production: Bool) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).app")
        let contents = directory.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": production ? "dev.local.YouTubeJack" : "com.local.YouTubeJack.Test",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundlePackageType": "APPL",
            "CFBundleName": "UpdateFixture"
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        bundle = try #require(Bundle(url: directory))
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
private final class ReleaseTransportStub {
    let missingAsset: String?
    private(set) var requests: [URLRequest] = []

    init(missingAsset: String? = nil) {
        self.missingAsset = missingAsset
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let url = try #require(request.url)
        let resolved = url.lastPathComponent == "latest"
            ? try #require(URL(string: "https://github.com/burakereno/youtubejack/releases/tag/v1.2.3"))
            : url
        let status = url.lastPathComponent == missingAsset ? 404 : 200
        let response = try #require(HTTPURLResponse(url: resolved, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil))
        return (Data(), response)
    }
}
