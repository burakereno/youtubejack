import Foundation

public struct YTDLPReleaseInfo: Equatable, Sendable {
    public let version: String
    public let assetURL: URL
    public let checksumURL: URL

    public init(version: String, assetURL: URL, checksumURL: URL) {
        self.version = version
        self.assetURL = assetURL
        self.checksumURL = checksumURL
    }
}

public struct YTDLPInstallResult: Equatable, Sendable {
    public let version: String
    public let path: String

    public init(version: String, path: String) {
        self.version = version
        self.path = path
    }
}
