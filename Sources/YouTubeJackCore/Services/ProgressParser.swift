import Foundation

public struct DownloadProgress: Equatable, Sendable {
    public let fraction: Double?
    public let speed: String
    public let eta: String

    public init(fraction: Double?, speed: String, eta: String) {
        self.fraction = fraction
        self.speed = speed
        self.eta = eta
    }
}

public struct SelectedMediaFormat: Equatable, Sendable {
    public let height: Int?
    public let videoCodec: String
    public let audioCodec: String
    public let audioLanguageCode: String?

    public init(height: Int?, videoCodec: String, audioCodec: String, audioLanguageCode: String? = nil) {
        self.height = height
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.audioLanguageCode = audioLanguageCode
    }

    public var videoCodecTitle: String {
        let codec = videoCodec.lowercased()
        if codec.hasPrefix("avc1") || codec.hasPrefix("avc3") || codec.hasPrefix("h264") { return "H.264" }
        if codec.hasPrefix("av01") || codec.hasPrefix("av1") { return "AV1" }
        if codec.hasPrefix("vp9") { return "VP9" }
        if codec.hasPrefix("vp8") { return "VP8" }
        if codec.hasPrefix("hev1") || codec.hasPrefix("hvc1") || codec.hasPrefix("h265") { return "H.265" }
        return videoCodec
    }

    public var audioCodecTitle: String {
        let codec = audioCodec.lowercased()
        if codec == "na" || codec == "none" { return L10n.string("Unknown audio") }
        if codec.hasPrefix("mp4a") || codec.hasPrefix("aac") { return "AAC" }
        if codec.hasPrefix("opus") { return "Opus" }
        if codec.hasPrefix("vorbis") { return "Vorbis" }
        return audioCodec
    }
}

public enum ProgressParser {
    public static func selectedMediaFormat(_ line: String) -> SelectedMediaFormat? {
        let prefix = "download-codecs:"
        guard line.hasPrefix(prefix) else { return nil }
        let values = line.dropFirst(prefix.count).split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard (3...4).contains(values.count), values[1] != "NA", values[1] != "none" else { return nil }
        let language = values.count == 4 && AudioLanguageSelection.isValidCode(values[3]) ? values[3] : nil
        return SelectedMediaFormat(height: Int(values[0]), videoCodec: values[1], audioCodec: values[2], audioLanguageCode: language)
    }

    public static func parse(_ line: String) -> DownloadProgress? {
        guard line.hasPrefix("download-progress:") else { return nil }
        let payload = line.replacingOccurrences(of: "download-progress:", with: "")
        let pieces = payload.split(separator: "|", omittingEmptySubsequences: false).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let percentText = pieces.indices.contains(0) ? pieces[0] : ""
        let speed = pieces.indices.contains(1) ? pieces[1] : ""
        let eta = pieces.indices.contains(2) ? pieces[2] : ""
        let fraction = percentFraction(from: percentText)

        return DownloadProgress(fraction: fraction, speed: speed, eta: eta)
    }

    public static func destinationPath(_ line: String) -> String? {
        let finalPrefix = "download-output:"
        if line.hasPrefix(finalPrefix) {
            return String(line.dropFirst(finalPrefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let prefix = "[download] Destination:"
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func percentFraction(from text: String) -> Double? {
        let cleaned = text
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned) else { return nil }
        return max(0, min(1, value / 100))
    }
}
