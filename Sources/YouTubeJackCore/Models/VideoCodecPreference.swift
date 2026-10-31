import Foundation

public enum VideoCodecPreference: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic
    case h264
    case av1

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return L10n.string("Automatic")
        case .h264: return "H.264"
        case .av1: return "AV1"
        }
    }

    public var formatFilter: String {
        switch self {
        case .automatic: return ""
        case .h264: return "[vcodec~='^(avc1|avc3|h264)']"
        case .av1: return "[vcodec~='^(av01|av1)']"
        }
    }

    public func allows(_ container: DownloadContainer) -> Bool {
        self != .h264 || container == .mp4
    }

    public func matches(_ codec: String?) -> Bool {
        if self == .automatic { return true }
        guard let codec = codec?.lowercased() else { return false }
        switch self {
        case .automatic: return true
        case .h264: return codec.hasPrefix("avc1") || codec.hasPrefix("avc3") || codec.hasPrefix("h264")
        case .av1: return codec.hasPrefix("av01") || codec.hasPrefix("av1")
        }
    }
}
