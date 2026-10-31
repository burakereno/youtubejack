import Foundation

public enum AppError: LocalizedError, Equatable, Sendable {
    case invalidYouTubeURL
    case missingDependency(String)
    case metadataDecodeFailed
    case noMediaLoaded
    case noPlaylistSelection
    case outputDirectoryUnavailable(String)
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidYouTubeURL:
            return L10n.string("This is not a valid YouTube video or playlist link.")
        case .missingDependency(let name):
            return L10n.string("%@ was not found in the app. Reinstall the app or update yt-dlp from the Tools section.", defaultValue: "\(name) was not found in the app. Reinstall the app or update yt-dlp from the Tools section.")
        case .metadataDecodeFailed:
            return L10n.string("Could not read video information.")
        case .noMediaLoaded:
            return L10n.string("Analyze a video or playlist first.")
        case .noPlaylistSelection:
            return L10n.string("No playlist videos are selected.")
        case .outputDirectoryUnavailable(let path):
            return L10n.string("Could not prepare the download folder: %@", defaultValue: "Could not prepare the download folder: \(path)")
        case .processFailed(let message):
            return message
        }
    }
}
