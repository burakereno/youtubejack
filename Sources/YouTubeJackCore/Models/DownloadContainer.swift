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
            return "MP4 akışları seçilir; video codec’i ayrıca belirlenir"
        case .webm:
            return "WebM akışları seçilir; video codec’i ayrıca belirlenir"
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
