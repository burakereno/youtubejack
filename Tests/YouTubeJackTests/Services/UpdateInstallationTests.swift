import Foundation
import Testing
import YouTubeJackCore
@testable import YouTubeJack

@MainActor
struct UpdateInstallationTests {
    @Test(.timeLimit(.minutes(1)))
    func realURLSessionDownloadRetainsTheResponseBeforeCallbackExit() async throws {
        let fixture = try InstallationFixture()
        defer { fixture.clean() }
        let portFile = fixture.root.appendingPathComponent("http-port")
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-u", "-c", """
        import http.server,sys
        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header('Content-Length','3')
                self.end_headers()
                self.wfile.write(b'abc')
            def log_message(self,*args): pass
        server=http.server.HTTPServer(('127.0.0.1',0),Handler)
        with open(sys.argv[1],'w') as f: f.write(str(server.server_port))
        server.serve_forever()
        """, portFile.path]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer { if server.isRunning { server.terminate(); server.waitUntilExit() } }
        let deadline = ContinuousClock.now + .seconds(5)
        while FileManager.default.fileExists(atPath: portFile.path) == false, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let port = try String(contentsOf: portFile)
        let url = try #require(URL(string: "http://127.0.0.1:\(port)/fixture.dmg"))
        let artifact = try await UpdateArtifactDownloader.download(from: url, onProgress: { _ in })
        defer { UpdateArtifactDownloader.removeArtifact(at: artifact) }
        try await Task.sleep(for: .milliseconds(30))
        #expect(try Data(contentsOf: artifact) == Data("abc".utf8))
        #expect(UpdateArtifactDownloader.isOwnedDirectory(artifact.deletingLastPathComponent()))
    }

    @Test func aCallbackOwnedFileIsRetainedInAPrivateDirectory() throws {
        let fixture = try InstallationFixture()
        defer { fixture.clean() }
        #expect(FileManager.default.fileExists(atPath: fixture.originalTemporaryFile.path) == false)
        #expect(try Data(contentsOf: fixture.artifact) == Data("abc".utf8))
        #expect(UpdateArtifactDownloader.isOwnedDirectory(fixture.artifact.deletingLastPathComponent()))
        let response = try #require(HTTPURLResponse(url: fixture.release.downloadURL, statusCode: 403, httpVersion: nil, headerFields: nil))
        let rejected = fixture.root.appendingPathComponent("rejected")
        try Data("do not consume".utf8).write(to: rejected)
        #expect(throws: UpdateError.badResponse) {
            try UpdateArtifactDownloader.retainTemporaryFile(at: rejected, response: response)
        }
        #expect(FileManager.default.fileExists(atPath: rejected.path))
    }

    @Test(arguments: [DownloadState.pending, .running])
    func unfinishedQueuePreventsUpdateDownload(status: DownloadState) async throws {
        let fixture = try InstallationFixture()
        defer { fixture.clean() }
        var downloadStarted = false
        let updater = fixture.updater(download: { _, _ in downloadStarted = true; return fixture.artifact })
        let model = fixture.model()
        model.queue = [DownloadItem(url: "https://www.youtube.com/watch?v=AAAAAAAAAAA", title: "Pending", quality: .q1080, container: .mp4, status: status)]
        #expect(model.canInstallAppUpdate == false)
        #expect(model.installAppUpdate(using: updater) == nil)
        #expect(downloadStarted == false)
        #expect(updater.lastError == UpdateChecker.unfinishedQueueMessage)
        #expect(model.isPreparingAppUpdate == false)
    }

    @Test func changedQueueIsRecheckedBeforeInstallerHandoffAndUnlocksOnFailure() async throws {
        let fixture = try InstallationFixture()
        defer { fixture.clean() }
        let gate = InstallationGate()
        var installed = false
        let updater = fixture.updater(download: { _, _ in await gate.wait(); return fixture.artifact }, install: { _, _, _ in installed = true })
        await updater.checkForUpdates(force: true)
        let model = fixture.model()
        let task = try #require(model.installAppUpdate(using: updater))
        #expect(model.isPreparingAppUpdate)
        #expect(model.canAddToQueue == false)
        model.queue = [DownloadItem(url: "https://www.youtube.com/watch?v=AAAAAAAAAAA", title: "Unexpected new work", quality: .q1080, container: .mp4)]
        model.resumeQueue()
        #expect(model.isQueuePaused)
        await gate.release()
        await task.value
        #expect(installed == false)
        #expect(updater.lastError == UpdateChecker.unfinishedQueueMessage)
        #expect(model.isPreparingAppUpdate == false)
        #expect(updater.isInstalling == false)
        #expect(FileManager.default.fileExists(atPath: fixture.artifact.path) == false)
    }

    @Test func successfulHandoffKeepsQueueLockedUntilRelaunch() async throws {
        let fixture = try InstallationFixture()
        defer { fixture.clean() }
        var installedVersion: String?
        let updater = fixture.updater(install: { file, version, checksum in
            #expect(file == fixture.artifact)
            #expect(checksum == fixture.manifest.sha256)
            installedVersion = version
        })
        await updater.checkForUpdates(force: true)
        let model = fixture.model()
        let operation = try #require(model.installAppUpdate(using: updater))
        await operation.value
        #expect(installedVersion == "1.1.0")
        #expect(updater.isInstalling)
        #expect(model.isPreparingAppUpdate)
        #expect(model.canInstallAppUpdate == false)
        #expect(updater.lastError == nil)
    }

    @Test func installerLaunchFailureReleasesTheQueueLock() async throws {
        let fixture = try InstallationFixture()
        defer { fixture.clean() }
        let updater = fixture.updater(install: { _, _, _ in throw UpdateError.badResponse })
        await updater.checkForUpdates(force: true)
        let model = fixture.model()
        let operation = try #require(model.installAppUpdate(using: updater))
        await operation.value
        #expect(model.isPreparingAppUpdate == false)
        #expect(model.canInstallAppUpdate)
        #expect(updater.isInstalling == false)
        #expect(updater.lastError != nil)
    }

    @Test func launchConfirmationRequiresTheVersionAndAnOwnedDirectory() throws {
        let fixture = try InstallationFixture()
        defer { fixture.clean() }
        let confirmation = fixture.artifact.deletingLastPathComponent().appendingPathComponent(UpdateLaunchConfirmation.fileName)
        let token = UUID().uuidString
        let args = ["app", "--update-confirmation", confirmation.path, "--update-token", token, "--update-version", "1.0.0"]
        #expect(try UpdateLaunchConfirmation.writeIfRequested(arguments: args, bundle: fixture.bundle, processID: 12345))
        let decoded = try PropertyListDecoder().decode(UpdateLaunchConfirmation.self, from: Data(contentsOf: confirmation))
        #expect(decoded.token == token)
        #expect(decoded.version == "1.0.0")
        #expect(decoded.processID == 12345)
        #expect(decoded.bundlePath == fixture.bundle.bundleURL.standardizedFileURL.path)
        #expect(try UpdateLaunchConfirmation.writeIfRequested(arguments: args, bundle: fixture.bundle, processID: 12345) == false)
        let wrongVersion = Array(args.dropLast()) + ["9.9.9"]
        #expect(try UpdateLaunchConfirmation.writeIfRequested(arguments: wrongVersion, bundle: fixture.bundle) == false)
        let outside = fixture.root.appendingPathComponent(UpdateLaunchConfirmation.fileName)
        let invalid = ["app", "--update-confirmation", outside.path, "--update-token", token, "--update-version", "1.0.0"]
        #expect(try UpdateLaunchConfirmation.writeIfRequested(arguments: invalid, bundle: fixture.bundle) == false)
        #expect(FileManager.default.fileExists(atPath: outside.path) == false)
    }
}

@MainActor
private struct InstallationFixture {
    let root: URL
    let bundle: Bundle
    let artifact: URL
    let originalTemporaryFile: URL
    let defaults: UserDefaults
    let suite: String
    let release: UpdateReleaseInfo
    let manifest = UpdateManifest(version: "1.1.0", asset: "YouTubeJack.dmg", sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", bundleIdentifier: "dev.local.YouTubeJack", teamIdentifier: "66K3EFBVB6")

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let contents = root.appendingPathComponent("Fixture.app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "dev.local.YouTubeJack", "CFBundleShortVersionString": "1.0.0", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        bundle = try #require(Bundle(url: contents.deletingLastPathComponent()))
        release = try UpdateChecker.releaseInfo(fromResolvedLatestURL: #require(URL(string: "https://github.com/burakereno/youtubejack/releases/tag/v1.1.0")))
        originalTemporaryFile = root.appendingPathComponent("urlsession-callback.tmp")
        try Data("abc".utf8).write(to: originalTemporaryFile)
        let response = try #require(HTTPURLResponse(url: release.downloadURL, statusCode: 200, httpVersion: nil, headerFields: nil))
        artifact = try UpdateArtifactDownloader.retainTemporaryFile(at: originalTemporaryFile, response: response)
        suite = "YouTubeJack.UpdateInstallationTests.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(root.path, forKey: AppPreferenceKeys.downloadDirectory)
    }

    func updater(download: (@MainActor (URL, @escaping @Sendable (Double) -> Void) async throws -> URL)? = nil,
                 install: @escaping @MainActor (URL, String, String) throws -> Void = { _, _, _ in }) -> UpdateChecker {
        UpdateChecker(bundle: bundle, fetchReleaseInfo: { release }, downloadArtifact: download ?? { _, _ in artifact }, fetchManifest: { _ in manifest }, installArtifact: install)
    }

    func model() -> AppModel {
        AppModel(dependencyResolver: DependencyResolver(managedBinDirectory: root, bundledBinDirectory: nil, systemSearchPaths: []), defaults: defaults)
    }

    func clean() {
        defaults.removePersistentDomain(forName: suite)
        UpdateArtifactDownloader.removeArtifact(at: artifact)
        try? FileManager.default.removeItem(at: root)
    }
}

private actor InstallationGate {
    private var isReleased = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if isReleased { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}
