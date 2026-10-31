import Foundation

public struct DependencyStatus: Equatable, Sendable {
    public let ytdlp: RuntimeTool?
    public let ffmpeg: RuntimeTool?
    public let ytdlpPath: String?
    public let ffmpegPath: String?
    public let jsRuntimePath: String?

    public init(ytdlp: RuntimeTool?, ffmpeg: RuntimeTool?, jsRuntimePath: String?) {
        self.ytdlp = ytdlp
        self.ffmpeg = ffmpeg
        ytdlpPath = ytdlp?.path
        ffmpegPath = ffmpeg?.path
        self.jsRuntimePath = jsRuntimePath
    }

    public var isReady: Bool {
        ytdlp != nil
    }

    public var summary: String {
        if let ytdlp {
            if ffmpeg == nil {
                return L10n.string("yt-dlp is ready (%@), ffmpeg is missing", defaultValue: "yt-dlp is ready (\(ytdlp.origin.title)), ffmpeg is missing")
            }
            return L10n.string("Tools ready: %@", defaultValue: "Tools ready: \(ytdlp.origin.title)")
        }
        return L10n.string("yt-dlp was not found")
    }
}

public enum RuntimeToolOrigin: String, Codable, Sendable {
    case managed
    case bundled
    case system

    public var title: String {
        switch self {
        case .managed:
            return L10n.string("managed")
        case .bundled:
            return L10n.string("bundled")
        case .system:
            return L10n.string("system")
        }
    }
}

public struct RuntimeTool: Equatable, Sendable {
    public let name: String
    public let path: String
    public let origin: RuntimeToolOrigin

    public init(name: String, path: String, origin: RuntimeToolOrigin) {
        self.name = name
        self.path = path
        self.origin = origin
    }
}
