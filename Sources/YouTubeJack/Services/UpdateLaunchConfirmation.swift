import Foundation

struct UpdateLaunchConfirmation: Codable {
    let token: String
    let version: String
    let bundlePath: String
    let processID: Int32

    static let fileName = "launch-confirmation.plist"

    @discardableResult
    static func writeIfRequested(arguments: [String], bundle: Bundle = .main,
                                 processID: Int32 = ProcessInfo.processInfo.processIdentifier) throws -> Bool {
        func argument(_ flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        guard let path = argument("--update-confirmation"), let token = argument("--update-token"),
              let version = argument("--update-version"), UUID(uuidString: token) != nil,
              processID > 1, bundle.bundleIdentifier == "dev.local.YouTubeJack",
              bundle.infoDictionary?["CFBundleShortVersionString"] as? String == version else { return false }
        let destination = URL(fileURLWithPath: path)
        guard destination.lastPathComponent == fileName,
              UpdateArtifactDownloader.isOwnedDirectory(destination.deletingLastPathComponent()) else { return false }
        guard FileManager.default.fileExists(atPath: destination.path) == false else { return false }
        let confirmation = Self(token: token, version: version, bundlePath: bundle.bundleURL.standardizedFileURL.path, processID: processID)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        try encoder.encode(confirmation).write(to: destination, options: .withoutOverwriting)
        return true
    }
}
