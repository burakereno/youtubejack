import Foundation
import Testing
import YouTubeJackCore
@testable import YouTubeJack

@MainActor
struct YTDLPUpdateAvailabilityTests {
    @Test(arguments: [
        AvailabilityCase(installed: "2026.10.26", latest: "2026.10.26", enabled: false),
        AvailabilityCase(installed: "2026.10.27", latest: "2026.10.26", enabled: false),
        AvailabilityCase(installed: "2026.10.9", latest: "2026.10.26", enabled: true),
        AvailabilityCase(installed: "2026.10.26", latest: "2026.10.27", enabled: true),
        AvailabilityCase(installed: "2026.10.26", latest: nil, enabled: false),
        AvailabilityCase(installed: "2026.10.26", latest: "", enabled: false),
        AvailabilityCase(installed: nil, latest: "2026.10.26", enabled: true),
        AvailabilityCase(installed: nil, latest: nil, enabled: false),
        AvailabilityCase(installed: "2026.10.26", latest: "2026.10.27", busy: true, enabled: false)
    ])
    func updateRequiresANewerKnownReleaseOrAMissingTool(scenario: AvailabilityCase) throws {
        let fixture = try UpdateAvailabilityFixture()
        defer { fixture.clean() }
        let model = fixture.model()
        model.ytdlpInstalledVersion = scenario.installed
        model.ytdlpLatestVersion = scenario.latest
        model.isUpdatingYTDLP = scenario.busy
        #expect(model.canUpdateYTDLP == scenario.enabled)
    }

    @Test(arguments: [
        AvailabilityCase(installed: "2026.10.26", latest: "2026.10.26", enabled: false),
        AvailabilityCase(installed: "2026.10.27", latest: "2026.10.26", enabled: false),
        AvailabilityCase(installed: "2026.10.26", latest: nil, enabled: false)
    ])
    func directUpdateCallsDoNotDownloadWhenAnUpdateIsUnavailable(scenario: AvailabilityCase) async throws {
        let fixture = try UpdateAvailabilityFixture()
        defer { fixture.clean() }
        let model = fixture.model()
        model.ytdlpInstalledVersion = scenario.installed
        model.ytdlpLatestVersion = scenario.latest
        model.ytdlpUpdateMessage = "Existing status"

        await model.updateYTDLP()

        #expect(model.ytdlpUpdateMessage == "Existing status", "An ineligible update must not enter the download/error flow")
        #expect(model.isUpdatingYTDLP == false)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("bin/yt-dlp").path) == false)
    }

    struct AvailabilityCase: Sendable {
        let installed: String?
        let latest: String?
        var busy = false
        let enabled: Bool
    }
}

private struct UpdateAvailabilityFixture {
    let root: URL
    let name: String
    let defaults: UserDefaults

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ytdlp-update-test-\(UUID().uuidString)")
        name = "YouTubeJack.YTDLPUpdateTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: name))
        defaults.set(root.path, forKey: AppPreferenceKeys.downloadDirectory)
    }

    @MainActor
    func model() -> AppModel {
        let resolver = DependencyResolver(managedBinDirectory: root.appendingPathComponent("bin"), bundledBinDirectory: nil, systemSearchPaths: [])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UnavailableUpdateProtocol.self]
        let service = YTDLPUpdateService(dependencyResolver: resolver, session: URLSession(configuration: configuration))
        return AppModel(dependencyResolver: resolver, defaults: defaults, ytdlpUpdateService: service)
    }

    func clean() {
        defaults.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: root)
    }
}

/// Fail immediately if the guard regresses; never contact GitHub in this test.
private final class UnavailableUpdateProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)) }
    override func stopLoading() {}
}
