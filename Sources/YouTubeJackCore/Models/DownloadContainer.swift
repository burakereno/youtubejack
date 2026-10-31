import Foundation

public enum DownloadContainer: String, CaseIterable, Codable, Identifiable, Sendable {
    case mp4
    case webm

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .mp4:
            return "MP4"
        case .webm:
            return "WebM"
        }
    }

    public var detail: String {
        switch self {
        case .mp4:
            return L10n.string("MP4 streams are selected; choose the video codec separately")
        case .webm:
            return L10n.string("WebM streams are selected; choose the video codec separately")
        }
    }

    public var systemImage: String {
        switch self {
        case .mp4:
            return "play.rectangle"
        case .webm:
            return "sparkles.tv"
        }
    }
}
