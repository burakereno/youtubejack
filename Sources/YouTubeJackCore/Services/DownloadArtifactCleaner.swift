import Foundation

public struct DownloadArtifactCleaner: Sendable {
    public init() {}

    public func removeWorkspace(at path: String, itemID: UUID) {
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        guard DownloadWorkspace.isOwnedDirectory(directory, itemID: itemID) else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
