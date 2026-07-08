import CryptoKit
import Foundation

public enum YTDLPUpdateError: LocalizedError, Sendable {
    case releaseAssetMissing
    case checksumMissing
    case checksumMismatch
    case untrustedReleaseURL
    case downloadFailed(Int)

    public var errorDescription: String? {
        switch self {
        case .releaseAssetMissing:
            return "yt-dlp macOS release dosyası bulunamadı."
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
        let url = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
        let data = try await data(from: url)
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)

        guard
            let asset = release.assets.first(where: { $0.name == "yt-dlp_macos" }),
            let assetURL = URL(string: asset.browserDownloadURL)
        else {
            throw YTDLPUpdateError.releaseAssetMissing
        }

        guard
            let checksumAsset = release.assets.first(where: { $0.name == "SHA2-256SUMS" }),
            let checksumURL = URL(string: checksumAsset.browserDownloadURL)
        else {
            throw YTDLPUpdateError.checksumMissing
        }

        guard isTrustedGitHubReleaseURL(assetURL), isTrustedGitHubReleaseURL(checksumURL) else {
            throw YTDLPUpdateError.untrustedReleaseURL
        }

        return YTDLPReleaseInfo(
            version: release.tagName,
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
        let (data, response) = try await session.data(from: url)
        if let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) == false {
            throw YTDLPUpdateError.downloadFailed(httpResponse.statusCode)
        }
        return data
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

private struct GitHubRelease: Decodable {
    let tagName: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
