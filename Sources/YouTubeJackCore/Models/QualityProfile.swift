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
            return L10n.string("Best")
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
            return L10n.string("Audio")
        }
    }

    public var detail: String {
        switch self {
        case .best:
            return L10n.string("Best available video and audio; the result may be WebM")
        case .q2160, .q1440:
            return L10n.string("Preserves quality; the result may be WebM")
        case .q1080, .q720, .q480:
            return L10n.string("Prefers MP4-compatible video and audio")
        case .audioM4A:
            return L10n.string("M4A audio file")
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

    public func audioSelector(language: AudioLanguageSelection) -> String {
        let filter = language.formatFilter
        return "bestaudio\(filter)/best\(filter)"
    }

    public func formatSelector(container: DownloadContainer, codec: VideoCodecPreference = .automatic, audioLanguage: AudioLanguageSelection = .original) -> String {
        if audioLanguage.languageCode != nil {
            if isAudioOnly { return audioSelector(language: audioLanguage) }
            let resolution: String
            if let height {
                resolution = "[height<=\(height)]" + (lowerExclusiveHeight.map { "[height>\($0)]" } ?? "")
            } else {
                resolution = ""
            }
            let video = "[ext=\(container.rawValue)]\(codec.formatFilter)\(resolution)"
            let audioExt = container == .mp4 ? "m4a" : "webm"
            // bv is video-only. bv* can retain an unrelated combined audio stream.
            return "bv\(video)+ba[ext=\(audioExt)]\(audioLanguage.formatFilter)/b\(video)\(audioLanguage.formatFilter)"
        }
        switch self {
        case .best:
            return bestSelector(container: container, codec: codec)
        case .q2160:
            return exactVideoSelector(height: 2160, container: container, codec: codec)
        case .q1440:
            return exactVideoSelector(height: 1440, container: container, codec: codec)
        case .q1080:
            return exactVideoSelector(height: 1080, container: container, codec: codec)
        case .q720:
            return exactVideoSelector(height: 720, container: container, codec: codec)
        case .q480:
            return exactVideoSelector(height: 480, container: container, codec: codec)
        case .audioM4A:
            return audioSelector
        }
    }

    private func bestSelector(container: DownloadContainer, codec: VideoCodecPreference) -> String {
        switch container {
        case .mp4:
            return "bv*[ext=mp4]\(codec.formatFilter)+ba[ext=m4a]/b[ext=mp4]\(codec.formatFilter)"
        case .webm:
            return "bv*[ext=webm]\(codec.formatFilter)+ba[ext=webm]/b[ext=webm]\(codec.formatFilter)"
        }
    }

    private func exactVideoSelector(height: Int, container: DownloadContainer, codec: VideoCodecPreference) -> String {
        let heightClause: String
        if let lowerExclusiveHeight {
            heightClause = "[height<=\(height)][height>\(lowerExclusiveHeight)]"
        } else {
            heightClause = "[height<=\(height)]"
        }

        switch container {
        case .mp4:
            return "bv*\(heightClause)[ext=mp4]\(codec.formatFilter)+ba[ext=m4a]/b\(heightClause)[ext=mp4]\(codec.formatFilter)"
        case .webm:
            return "bv*\(heightClause)[ext=webm]\(codec.formatFilter)+ba[ext=webm]/b\(heightClause)[ext=webm]\(codec.formatFilter)"
        }
    }
}
