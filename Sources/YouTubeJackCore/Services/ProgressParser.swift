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

public enum ProgressParser {
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
