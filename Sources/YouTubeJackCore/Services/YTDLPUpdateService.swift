import CryptoKit
import Foundation

public enum YTDLPUpdateError: LocalizedError, Sendable {
    case releaseAssetMissing
    case releaseVersionMissing
    case checksumMissing
    case checksumMismatch
    case untrustedReleaseURL
    case downloadFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .releaseAssetMissing:
            return "yt-dlp macOS release dosyası bulunamadı."
        case .releaseVersionMissing:
            return "yt-dlp release sürümü bulunamadı."
        case .checksumMissing:
            return "yt-dlp checksum bilgisi bulunamadı."
        case .checksumMismatch:
            return "yt-dlp checksum doğrulaması başarısız."
        case .untrustedReleaseURL:
            return "yt-dlp release URL doğrulaması başarısız."
        case .downloadFailed(let statusCode):
            return "yt-dlp indirme isteği başarısız: HTTP \(statusCode)."
        }
    }
}

public final class YTDLPUpdateService: Sendable {
    private let dependencyResolver: DependencyResolver
    private let processRunner: ProcessRunner
    private let session: URLSession

    public init(
        dependencyResolver: DependencyResolver = DependencyResolver(),
        processRunner: ProcessRunner = ProcessRunner(),
        session: URLSession = .shared
    ) {
        self.dependencyResolver = dependencyResolver
        self.processRunner = processRunner
        self.session = session
    }

    public func installedVersion() async -> String? {
        guard let ytdlpPath = dependencyResolver.findTool(named: "yt-dlp")?.path else {
            return nil
        }

        do {
            let result = try await processRunner.run(executablePath: ytdlpPath, arguments: ["--version"])
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    public func latestRelease() async throws -> YTDLPReleaseInfo {
        let tag = try await latestReleaseTag()
        let assetURL = releaseAssetURL(tag: tag, assetName: "yt-dlp_macos")
        let checksumURL = releaseAssetURL(tag: tag, assetName: "SHA2-256SUMS")

        guard isTrustedGitHubReleaseURL(assetURL), isTrustedGitHubReleaseURL(checksumURL) else {
            throw YTDLPUpdateError.untrustedReleaseURL
        }
        try await validateReleaseAssetURL(assetURL, missingError: .releaseAssetMissing)
        try await validateReleaseAssetURL(checksumURL, missingError: .checksumMissing)

        return YTDLPReleaseInfo(
            version: tag,
            assetURL: assetURL,
            checksumURL: checksumURL
        )
    }

    public func installLatest() async throws -> YTDLPInstallResult {
        let release = try await latestRelease()
        let binaryData = try await data(from: release.assetURL)
        let checksumData = try await data(from: release.checksumURL)
        try validate(binaryData: binaryData, checksumData: checksumData, assetName: "yt-dlp_macos")

        let binDirectory = try dependencyResolver.managedBinDirectory()
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        let destination = binDirectory.appendingPathComponent("yt-dlp")
        let temporaryDestination = binDirectory.appendingPathComponent("yt-dlp.tmp")
        try? FileManager.default.removeItem(at: temporaryDestination)
        defer { try? FileManager.default.removeItem(at: temporaryDestination) }

        try binaryData.write(to: temporaryDestination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporaryDestination.path)

        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporaryDestination)
        } else {
            try FileManager.default.moveItem(at: temporaryDestination, to: destination)
        }

        return YTDLPInstallResult(version: release.version, path: destination.path)
    }

    private func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("YouTubeJack-YTDLPUpdater", forHTTPHeaderField: "User-Agent")
        if url.host?.lowercased() == "api.github.com" {
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        }

        let (data, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) == false {
            throw YTDLPUpdateError.downloadFailed(httpResponse.statusCode)
        }
        return data
    }

    private func latestReleaseTag() async throws -> String {
        let url = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 12
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("YouTubeJack-YTDLPUpdater", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) == false {
            throw YTDLPUpdateError.downloadFailed(httpResponse.statusCode)
        }

        guard
            let resolvedURL = response.url,
            resolvedURL.lastPathComponent != "latest"
        else {
            throw YTDLPUpdateError.releaseVersionMissing
        }

        return resolvedURL.lastPathComponent
    }

    private func releaseAssetURL(tag: String, assetName: String) -> URL {
        URL(string: "https://github.com/yt-dlp/yt-dlp/releases/download/\(tag)/\(assetName)")!
    }

    private func validateReleaseAssetURL(_ url: URL, missingError: YTDLPUpdateError) async throws {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 12
        request.setValue("YouTubeJack-YTDLPUpdater", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await session.data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode == 404 {
                throw missingError
            }
            if (200..<300).contains(httpResponse.statusCode) == false {
                throw YTDLPUpdateError.downloadFailed(httpResponse.statusCode)
            }
        }
    }

    private func isTrustedGitHubReleaseURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        return url.host?.lowercased() == "github.com"
            && url.path.hasPrefix("/yt-dlp/yt-dlp/releases/download/")
    }

    private func validate(binaryData: Data, checksumData: Data, assetName: String) throws {
        guard
            let checksumText = String(data: checksumData, encoding: .utf8),
            let expected = checksumText
                .split(separator: "\n")
                .first(where: { line in
                    let parts = line.split(separator: " ")
                    guard let fileName = parts.last.map(String.init) else { return false }
                    return parts.count >= 2 && (fileName == assetName || fileName == "*\(assetName)")
                })?
                .split(separator: " ")
                .first
                .map(String.init)
        else {
            throw YTDLPUpdateError.checksumMissing
        }

        let actual = SHA256.hash(data: binaryData)
            .map { String(format: "%02x", $0) }
            .joined()

        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw YTDLPUpdateError.checksumMismatch
        }
    }
}
