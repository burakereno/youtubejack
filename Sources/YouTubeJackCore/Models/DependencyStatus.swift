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
                return "yt-dlp hazır (\(ytdlp.origin.title)), ffmpeg eksik"
            }
            return "Araçlar hazır: \(ytdlp.origin.title)"
        }
        return "yt-dlp bulunamadı"
    }
}

public enum RuntimeToolOrigin: String, Codable, Sendable {
    case managed
    case bundled
    case system

    public var title: String {
        switch self {
        case .managed:
            return "yönetilen"
        case .bundled:
            return "uygulama içi"
        case .system:
            return "sistem"
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
