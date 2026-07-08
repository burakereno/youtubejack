import Foundation

public enum QualityProfile: String, CaseIterable, Codable, Identifiable, Sendable {
    case best
    case q2160
    case q1440
    case q1080
    case q720
    case q480
    case audioM4A

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .best:
            return "En iyi"
        case .q2160:
            return "2160p"
        case .q1440:
            return "1440p"
        case .q1080:
            return "1080p"
        case .q720:
            return "720p"
        case .q480:
            return "480p"
        case .audioM4A:
            return "Ses"
        }
    }

    public var detail: String {
        switch self {
        case .best:
            return "Mevcut en iyi video ve ses; WebM gelebilir"
        case .q2160, .q1440:
            return "Kaliteyi korur; WebM gelebilir"
        case .q1080, .q720, .q480:
            return "MP4 uyumlu video ve ses tercih edilir"
        case .audioM4A:
            return "M4A ses dosyası"
        }
    }

    public var systemImage: String {
        switch self {
        case .audioM4A:
            return "waveform"
        case .best:
            return "sparkles.tv"
        default:
            return "display"
        }
    }

    public var isAudioOnly: Bool {
        self == .audioM4A
    }

    public var isVideoQuality: Bool {
        isAudioOnly == false
    }

    public var height: Int? {
        switch self {
        case .q2160:
            return 2160
        case .q1440:
            return 1440
        case .q1080:
            return 1080
        case .q720:
            return 720
        case .q480:
            return 480
        case .best, .audioM4A:
            return nil
        }
    }

    public var lowerExclusiveHeight: Int? {
        switch self {
        case .q2160:
            return 1440
        case .q1440:
            return 1080
        case .q1080:
            return 720
        case .q720:
            return 480
        case .q480:
            return nil
        case .best, .audioM4A:
            return nil
        }
    }

    public var audioSelector: String {
        "bestaudio/best"
    }

    public func formatSelector(container: DownloadContainer) -> String {
        switch self {
        case .best:
            return bestSelector(container: container)
        case .q2160:
            return exactVideoSelector(height: 2160, container: container)
        case .q1440:
            return exactVideoSelector(height: 1440, container: container)
        case .q1080:
            return exactVideoSelector(height: 1080, container: container)
        case .q720:
            return exactVideoSelector(height: 720, container: container)
        case .q480:
            return exactVideoSelector(height: 480, container: container)
        case .audioM4A:
            return audioSelector
        }
    }

    private func bestSelector(container: DownloadContainer) -> String {
        switch container {
        case .mp4:
            return "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]"
        case .webm:
            return "bv*[ext=webm]+ba[ext=webm]/b[ext=webm]"
        }
    }

    private func exactVideoSelector(height: Int, container: DownloadContainer) -> String {
        let heightClause: String
        if let lowerExclusiveHeight {
            heightClause = "[height<=\(height)][height>\(lowerExclusiveHeight)]"
        } else {
            heightClause = "[height<=\(height)]"
        }

        switch container {
        case .mp4:
            return "bv*\(heightClause)[ext=mp4]+ba[ext=m4a]/b\(heightClause)[ext=mp4]"
        case .webm:
            return "bv*\(heightClause)[ext=webm]+ba[ext=webm]/b\(heightClause)[ext=webm]"
        }
    }
}
