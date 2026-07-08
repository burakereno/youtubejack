import Foundation

enum AppPreferenceKeys {
    static let downloadDirectory = "downloadDirectory"
    static let downloadDirectoryBookmark = "downloadDirectoryBookmark"
    static let autoDetectClipboard = "autoDetectClipboard"
    static let defaultQuality = "defaultQuality"
    static let defaultContainer = "defaultContainer"
}

enum AppPreferenceDefaults {
    static var downloadDirectory: String {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?
            .appendingPathComponent("YouTubeJack", isDirectory: true)
            .path ?? NSHomeDirectory()
    }

    static let defaultQuality = "q1080"
    static let defaultContainer = "mp4"
}
