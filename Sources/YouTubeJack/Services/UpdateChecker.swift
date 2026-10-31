import AppKit
import Foundation
import OSLog

@MainActor
final class UpdateChecker: ObservableObject {
    static let shared: UpdateChecker = {
        #if DEBUG
        return UpdateChecker(isPreviewingUpdate: ProcessInfo.processInfo.arguments.contains("--preview-update"))
        #else
        return UpdateChecker()
        #endif
    }()

    typealias ReleaseTransport = @MainActor (URLRequest) async throws -> (Data, URLResponse)
    typealias TimerFactory = @MainActor (TimeInterval, @escaping @MainActor @Sendable () async -> Void) -> Timer

    private static let owner = "burakereno"
    private static let repo = "youtubejack"
    private static let assetName = "YouTubeJack.dmg"
    private static let manifestName = "YouTubeJack.dmg.update.json"
    private static let productionBundleIdentifier = "dev.local.YouTubeJack"
    private static let appBundleName = "YouTubeJack.app"
    private static let executableName = "YouTubeJack"
    private static let checkInterval: TimeInterval = 2 * 60 * 60
    private static let minimumManualCheckInterval: TimeInterval = 30 * 60
    private static let minimumVisibleCheckDuration: UInt64 = 500_000_000

    private let bundle: Bundle
    private let now: @MainActor () -> Date
    private let fetchReleaseInfo: @MainActor () async throws -> UpdateReleaseInfo
    private let downloadArtifact: @MainActor (URL, @escaping @Sendable (Double) -> Void) async throws -> URL
    private let fetchManifest: @MainActor (URL) async throws -> UpdateManifest
    private let installArtifact: @MainActor (URL, String, String) throws -> Void
    private let timerFactory: TimerFactory
    private let logger: Logger
    let isPreviewingUpdate: Bool

    @Published private(set) var latestVersion: String?
    @Published private(set) var downloadURL: URL?
    private var manifestURL: URL?
    @Published private(set) var isChecking = false
    @Published private(set) var isDownloading = false
    @Published private(set) var isInstalling = false
    @Published private(set) var downloadProgress: Double = 0
    @Published private(set) var lastError: String?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var lastCheckCompletedAt: Date?

    var currentVersion: String {
        bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    var updateAvailable: Bool {
        guard isProductionBuild else { return false }
        guard let latestVersion else { return false }
        return Self.compare(latestVersion, isNewerThan: currentVersion)
    }

    var isUpToDate: Bool {
        guard let latestVersion, lastError == nil else { return false }
        return !Self.compare(latestVersion, isNewerThan: currentVersion)
    }

    var updatesEnabled: Bool {
        isProductionBuild
    }

    var shouldShowToolbarUpdate: Bool {
        isPreviewingUpdate || updateAvailable
    }

    private var timer: Timer?
    private var installationTask: Task<Void, Never>?

    private var isProductionBuild: Bool {
        bundle.bundleIdentifier == Self.productionBundleIdentifier
    }

    init(
        bundle: Bundle = .main,
        isPreviewingUpdate: Bool = false,
        now: @escaping @MainActor () -> Date = { Date() },
        fetchReleaseInfo: @escaping @MainActor () async throws -> UpdateReleaseInfo = {
            try await UpdateChecker.fetchLatestReleaseInfo()
        },
        timerFactory: @escaping TimerFactory = { interval, action in
            UpdateChecker.makeAutomaticTimer(interval: interval, action: action)
        },
        downloadArtifact: @escaping @MainActor (URL, @escaping @Sendable (Double) -> Void) async throws -> URL = {
            try await UpdateArtifactDownloader.download(from: $0, onProgress: $1)
        },
        fetchManifest: @escaping @MainActor (URL) async throws -> UpdateManifest = { try await UpdateChecker.fetchManifest(at: $0) },
        installArtifact: @escaping @MainActor (URL, String, String) throws -> Void = {
            try UpdateChecker.installUpdate(dmgURL: $0, expectedVersion: $1, expectedSHA256: $2)
        }
    ) {
        self.bundle = bundle
        self.isPreviewingUpdate = isPreviewingUpdate
        self.now = now
        self.fetchReleaseInfo = fetchReleaseInfo
        self.timerFactory = timerFactory
        self.downloadArtifact = downloadArtifact
        self.fetchManifest = fetchManifest
        self.installArtifact = installArtifact
        logger = Logger(subsystem: bundle.bundleIdentifier ?? Self.productionBundleIdentifier, category: "Updates")
    }

    func start() async {
        guard timer == nil else { return }
        timer = timerFactory(Self.checkInterval) { [weak self] in
            await self?.checkForUpdates(force: false, reportsErrors: false)
        }
        logger.info("Automatic update checks started; interval: 7200 seconds.")
        await checkForUpdates(force: false, reportsErrors: false)
    }

    private static func makeAutomaticTimer(
        interval: TimeInterval,
        action: @escaping @MainActor @Sendable () async -> Void
    ) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            Task { @MainActor in await action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if isInstalling == false { installationTask?.cancel() }
    }

    func checkForUpdates(force: Bool = false) async {
        await checkForUpdates(force: force, reportsErrors: true)
    }

    private func checkForUpdates(force: Bool, reportsErrors: Bool) async {
        guard !isChecking else { return }

        let checkStartedAt = now()
        if !force,
           let lastCheckedAt,
           checkStartedAt.timeIntervalSince(lastCheckedAt) < Self.minimumManualCheckInterval
        {
            return
        }

        lastCheckedAt = checkStartedAt
        isChecking = true
        logger.info("Update check started: \(reportsErrors ? "manual" : "automatic", privacy: .public).")
        if reportsErrors {
            lastError = nil
        }

        do {
            let releaseInfo = try await fetchReleaseInfo()
            latestVersion = releaseInfo.version
            downloadURL = releaseInfo.downloadURL
            manifestURL = releaseInfo.manifestURL
            lastError = nil
            logger.info("Update check succeeded; current: \(self.currentVersion, privacy: .public), latest: \(releaseInfo.version, privacy: .public).")
        } catch {
            if reportsErrors {
                lastError = error.localizedDescription
            }
            logger.notice("Update check failed: \(reportsErrors ? "manual" : "automatic", privacy: .public).")
        }

        let elapsed = max(0, now().timeIntervalSince(checkStartedAt))
        if reportsErrors, elapsed < 0.5 {
            let remaining = Self.minimumVisibleCheckDuration - UInt64(elapsed * 1_000_000_000)
            try? await Task.sleep(nanoseconds: remaining)
        }

        lastCheckCompletedAt = now()
        isChecking = false
    }

    nonisolated static let unfinishedQueueMessage = "Güncellemeden önce kuyruktaki indirmeleri tamamlayın veya bekleyen işleri kuyruktan kaldırın."

    func reportInstallationBlocked() {
        lastError = Self.unfinishedQueueMessage
    }

    @discardableResult
    func downloadAndInstall(
        canInstall: @escaping @MainActor () -> Bool = { false },
        onPreparationChanged: @escaping @MainActor (Bool) -> Void = { _ in }
    ) -> Task<Void, Never>? {
        guard isProductionBuild else {
            lastError = "Updates are disabled for local builds."
            return nil
        }
        guard isDownloading == false, isInstalling == false else { return nil }
        guard canInstall() else { reportInstallationBlocked(); return nil }
        guard updateAvailable, let downloadURL, let manifestURL, let latestVersion else {
            lastError = "Update download is unavailable."
            return nil
        }

        isDownloading = true
        downloadProgress = 0
        lastError = nil
        onPreparationChanged(true)
        let reportProgress: @Sendable (Double) -> Void = { [weak self] progress in
            Task { @MainActor [weak self] in
                guard self?.isDownloading == true else { return }
                self?.downloadProgress = progress
            }
        }
        let operation = Task { @MainActor in
            var artifact: URL?
            defer {
                self.isDownloading = false
                self.downloadProgress = 0
                self.installationTask = nil
                if self.isInstalling == false { onPreparationChanged(false) }
            }
            do {
                let destination = try await self.downloadArtifact(downloadURL, reportProgress)
                artifact = destination
                let manifest = try await self.fetchManifest(manifestURL)
                let assetName = Self.assetName
                let bundleIdentifier = Self.productionBundleIdentifier
                try await Task.detached {
                    try UpdateSecurity.verify(manifest: manifest, artifactURL: destination,
                                              expectedVersion: latestVersion, expectedAsset: assetName,
                                              expectedBundleIdentifier: bundleIdentifier)
                }.value
                try Task.checkCancellation()
                guard canInstall() else { throw UpdateInstallationError.unfinishedQueue }
                self.isInstalling = true
                do {
                    try self.installArtifact(destination, latestVersion, manifest.sha256.lowercased())
                } catch {
                    self.isInstalling = false
                    throw error
                }
            } catch {
                if let artifact { UpdateArtifactDownloader.removeArtifact(at: artifact) }
                self.lastError = error.localizedDescription
            }
        }
        installationTask = operation
        return operation
    }

    private static func installUpdate(dmgURL: URL, expectedVersion: String, expectedSHA256: String) throws {
        let currentBundle = URL(fileURLWithPath: Bundle.main.bundlePath)
        let targetBundle = currentBundle.path.hasPrefix("/Applications/")
            ? currentBundle
            : URL(fileURLWithPath: "/Applications/\(Self.appBundleName)")
        try UpdateSecurity.launchInstaller(
            parentPID: ProcessInfo.processInfo.processIdentifier,
            dmgURL: dmgURL, targetURL: targetBundle,
            expectedBundleIdentifier: Self.productionBundleIdentifier,
            expectedVersion: expectedVersion, appBundleName: Self.appBundleName,
            executableName: Self.executableName, expectedSHA256: expectedSHA256
        )
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            NSApp.terminate(nil)
        }
    }

    nonisolated static func compare(_ a: String, isNewerThan b: String) -> Bool {
        let parsedA = parse(a)
        let parsedB = parse(b)

        for index in 0..<max(parsedA.count, parsedB.count) {
            let valueA = index < parsedA.count ? parsedA[index] : 0
            let valueB = index < parsedB.count ? parsedB[index] : 0
            if valueA != valueB { return valueA > valueB }
        }

        return false
    }

    static func fetchLatestReleaseInfo(
        transport: ReleaseTransport = { try await URLSession.shared.data(for: $0) }
    ) async throws -> UpdateReleaseInfo {
        let latestURL = URL(string: "https://github.com/\(owner)/\(repo)/releases/latest")!
        var request = URLRequest(url: latestURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 12
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("YouTubeJack-UpdateChecker", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await transport(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.badResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateError.badStatus(httpResponse.statusCode)
        }
        guard let resolvedURL = httpResponse.url else {
            throw UpdateError.missingVersion
        }

        let releaseInfo = try releaseInfo(fromResolvedLatestURL: resolvedURL)
        try await validateDownloadURL(releaseInfo.downloadURL, assetName: assetName, transport: transport)
        try await validateDownloadURL(releaseInfo.manifestURL, assetName: manifestName, transport: transport)
        return releaseInfo
    }

    static func releaseInfo(fromResolvedLatestURL url: URL) throws -> UpdateReleaseInfo {
        let components = url.pathComponents
        guard url.scheme == "https", url.host == "github.com",
              components.count == 6,
              components[1].lowercased() == owner,
              components[2].lowercased() == repo,
              components[3] == "releases", components[4] == "tag" else {
            throw UpdateError.missingVersion
        }
        let tag = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard tag.range(of: "^v?[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil else {
            throw UpdateError.missingVersion
        }

        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard !version.isEmpty else {
            throw UpdateError.missingVersion
        }

        let downloadURL = URL(string: "https://github.com/\(owner)/\(repo)/releases/download/\(tag)/\(assetName)")!
        let manifestURL = URL(string: "https://github.com/\(owner)/\(repo)/releases/download/\(tag)/\(manifestName)")!
        return UpdateReleaseInfo(version: version, downloadURL: downloadURL, manifestURL: manifestURL)
    }

    private static func fetchManifest(at url: URL) async throws -> UpdateManifest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("YouTubeJack-UpdateChecker", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw UpdateError.badResponse
        }
        do {
            return try JSONDecoder().decode(UpdateManifest.self, from: data)
        } catch {
            throw UpdateError.invalidManifest
        }
    }

    private static func validateDownloadURL(_ url: URL, assetName: String, transport: ReleaseTransport) async throws {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 12
        request.setValue("YouTubeJack-UpdateChecker", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await transport(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UpdateError.badResponse
        }
        if httpResponse.statusCode == 404 {
            throw UpdateError.missingAsset(assetName)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateError.badStatus(httpResponse.statusCode)
        }
    }

    nonisolated private static func parse(_ value: String) -> [Int] {
        value
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }
}

enum UpdateError: LocalizedError, Equatable {
    case badResponse
    case badStatus(Int)
    case missingAsset(String)
    case missingVersion
    case invalidManifest

    var errorDescription: String? {
        switch self {
        case .badResponse:
            return "GitHub returned an invalid response"
        case .badStatus(let statusCode):
            return "GitHub returned HTTP \(statusCode)"
        case .missingAsset(let assetName):
            return "GitHub release is missing \(assetName)"
        case .missingVersion:
            return "GitHub release is missing a version tag"
        case .invalidManifest:
            return "GitHub release contains an invalid update manifest"
        }
    }
}

struct UpdateReleaseInfo: Equatable {
    let version: String
    let downloadURL: URL
    let manifestURL: URL
}

enum UpdateInstallationError: LocalizedError {
    case unfinishedQueue
    var errorDescription: String? { UpdateChecker.unfinishedQueueMessage }
}
