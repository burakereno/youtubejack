import Foundation

enum DisplayFormatters {
    static func duration(_ seconds: Double?) -> String {
        guard let seconds else { return "" }
        let value = Int(seconds)
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let remainingSeconds = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }

    static func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    static func fileSize(_ bytes: Int64) -> String {
        let megabytes = Double(bytes) / 1_000_000
        if megabytes < 10 {
            return String(format: "%.1f MB", megabytes)
        }
        return String(format: "%.0f MB", megabytes)
    }
}
