import Combine
import CryptoKit
import Foundation
import Testing
import YouTubeJackCore
@testable import YouTubeJack

@MainActor
struct YTDLPUpdateNotificationTests {
    @Test func startupAndTheTwoHourTimerDiscoverUpdatesWithoutOpeningInfo() async throws {
        let fixture = try YTDLPNotificationFixture()
        defer { fixture.clean() }
        let timer = YTDLPNotificationTimer()
        let model = fixture.model(timer: timer)
        defer { model.stopYTDLPUpdateChecks() }

        await model.startYTDLPUpdateChecks()
        #expect(timer.intervals == [7200])
        #expect(fixture.source.requestCount == 3)
        #expect(model.shouldShowYTDLPToolbarUpdate)
        #expect(model.ytdlpUpdateMessage == nil)
        #expect(model.isUpdatePanelPresented == false)

        await model.startYTDLPUpdateChecks()
        #expect(timer.intervals == [7200])
        #expect(fixture.source.requestCount == 3)

        fixture.source.version = "2026.11.01"
        await timer.fire()
        #expect(fixture.source.requestCount == 6)
        #expect(model.ytdlpLatestVersion == "2026.11.01")
        #expect(model.shouldShowYTDLPToolbarUpdate)

        try fixture.writeInstalledVersion("2026.11.01")
        await timer.fire()
        #expect(model.shouldShowYTDLPToolbarUpdate == false)
        #expect(model.canUpdateYTDLP == false)

        model.stopYTDLPUpdateChecks()
        #expect(timer.timer?.isValid == false)
        let calls = fixture.source.requestCount
        await timer.fire()
        #expect(fixture.source.requestCount == calls)
    }

    @Test func automaticFailuresAreSilentAndKeepAnAlreadyDiscoveredUpdate() async throws {
        let fixture = try YTDLPNotificationFixture()
        defer { fixture.clean() }
        let timer = YTDLPNotificationTimer()
        let model = fixture.model(timer: timer)
        defer { model.stopYTDLPUpdateChecks() }
        fixture.source.status = 503
        await model.startYTDLPUpdateChecks()
        #expect(model.ytdlpUpdateMessage == nil)
        #expect(model.shouldShowYTDLPToolbarUpdate == false)

        fixture.source.status = 200
        await timer.fire()
        #expect(model.shouldShowYTDLPToolbarUpdate)
        fixture.source.status = 503
        await timer.fire()
        #expect(model.shouldShowYTDLPToolbarUpdate)
        #expect(model.ytdlpUpdateMessage == nil)

        await model.checkYTDLPUpdate()
        #expect(model.ytdlpUpdateMessage?.contains("503") == true)
    }

    @Test(arguments: [false, true])
    func installingHidesTheNoticeOnSuccessAndLeavesARetryOnFailure(badChecksum: Bool) async throws {
        let fixture = try YTDLPNotificationFixture()
        defer { fixture.clean() }
        let timer = YTDLPNotificationTimer()
        let model = fixture.model(timer: timer)
        defer { model.stopYTDLPUpdateChecks() }
        await model.startYTDLPUpdateChecks()
        fixture.source.badChecksum = badChecksum
        var installingStates: [Bool] = []
        let observer = model.$isInstallingYTDLP.dropFirst().sink { installingStates.append($0) }
        defer { observer.cancel() }

        await model.updateYTDLP()

        #expect(installingStates == [true, false])
        #expect(model.isInstallingYTDLP == false)
        #expect(model.isUpdatingYTDLP == false)
        #expect(model.shouldShowYTDLPToolbarUpdate == badChecksum)
        #expect(model.canUpdateYTDLP == badChecksum)
        #expect(model.ytdlpInstalledVersion == (badChecksum ? "2026.08.19" : "2026.10.26"))
    }
}

@MainActor
private final class YTDLPNotificationTimer {
    var intervals: [TimeInterval] = []
    var action: (@MainActor @Sendable () async -> Void)?
    var timer: Timer?

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

private struct YTDLPNotificationFixture {
    let root: URL
    let name: String
    let defaults: UserDefaults
    let source = YTDLPNotificationSource()

    init() throws {
        name = "YouTubeJack.YTDLPNotifications.\(UUID().uuidString)"
        root = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defaults = try #require(UserDefaults(suiteName: name))
        defaults.set(root.appendingPathComponent("Downloads").path, forKey: AppPreferenceKeys.downloadDirectory)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try writeInstalledVersion("2026.08.19")
        YTDLPNotificationProtocol.registry.add(source, for: name)
    }

    func writeInstalledVersion(_ version: String) throws {
        let executable = root.appendingPathComponent("bin/yt-dlp")
        try "#!/bin/sh\nprintf '%s\\n' '\(version)'\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    @MainActor
    func model(timer: YTDLPNotificationTimer) -> AppModel {
        let resolver = DependencyResolver(managedBinDirectory: root.appendingPathComponent("bin"), bundledBinDirectory: nil, systemSearchPaths: [])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [YTDLPNotificationProtocol.self]
        configuration.httpAdditionalHeaders = ["X-YouTubeJack-Test": name]
        let service = YTDLPUpdateService(dependencyResolver: resolver, session: URLSession(configuration: configuration))
        return AppModel(dependencyResolver: resolver, defaults: defaults, ytdlpUpdateService: service, ytdlpUpdateTimerFactory: timer.schedule)
    }

    func clean() {
        YTDLPNotificationProtocol.registry.remove(name)
        defaults.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: root)
    }
}

/// URLProtocol callbacks run outside the main actor. The per-fixture source and
/// registry protect their mutable state with short synchronous NSLock sections.
private final class YTDLPNotificationSource: @unchecked Sendable {
    private let lock = NSLock()
    private var storedVersion = "2026.10.26"
    private var storedStatus = 200
    private var storedBadChecksum = false
    private var calls = 0
    var version: String { get { lock.withLock { storedVersion } } set { lock.withLock { storedVersion = newValue } } }
    var status: Int { get { lock.withLock { storedStatus } } set { lock.withLock { storedStatus = newValue } } }
    var badChecksum: Bool { get { lock.withLock { storedBadChecksum } } set { lock.withLock { storedBadChecksum = newValue } } }
    var requestCount: Int { lock.withLock { calls } }

    func response(for request: URLRequest) -> (HTTPURLResponse, Data) {
        lock.withLock {
            calls += 1
            let url = request.url!
            let resolved = url.path.hasSuffix("/latest") ? URL(string: "https://github.com/yt-dlp/yt-dlp/releases/tag/\(storedVersion)")! : url
            let binary = Data("#!/bin/sh\nprintf '%s\\n' '\(storedVersion)'\n".utf8)
            let digest = SHA256.hash(data: binary).map { String(format: "%02x", $0) }.joined()
            let checksum = (storedBadChecksum ? String(repeating: "0", count: 64) : digest) + "  yt-dlp_macos\n"
            let data = request.httpMethod == "HEAD" ? Data() : (url.lastPathComponent == "SHA2-256SUMS" ? Data(checksum.utf8) : binary)
            return (HTTPURLResponse(url: resolved, statusCode: storedStatus, httpVersion: nil, headerFields: nil)!, data)
        }
    }
}

private final class YTDLPNotificationRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [String: YTDLPNotificationSource] = [:]
    func add(_ source: YTDLPNotificationSource, for key: String) { lock.withLock { sources[key] = source } }
    func remove(_ key: String) { _ = lock.withLock { sources.removeValue(forKey: key) } }
    func source(for key: String) -> YTDLPNotificationSource? { lock.withLock { sources[key] } }
}

private final class YTDLPNotificationProtocol: URLProtocol {
    static let registry = YTDLPNotificationRegistry()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let key = request.value(forHTTPHeaderField: "X-YouTubeJack-Test"), let source = Self.registry.source(for: key) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let (response, data) = source.response(for: request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
