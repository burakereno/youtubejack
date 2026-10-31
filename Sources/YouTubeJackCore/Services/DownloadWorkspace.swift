import Foundation

/// Partial files belong to one queue item. Published media never belongs to cleanup.
public struct DownloadWorkspace: Sendable {
    public let directory: URL
    private let itemID: UUID
    private static let ownerFile = ".youtubejack-owner"

    public init(outputDirectory: String, itemID: UUID) {
        self.itemID = itemID
        directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            .appendingPathComponent(".youtubejack-download-\(itemID.uuidString)", isDirectory: true)
    }

    public func prepare() throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) || (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
            guard Self.isOwnedDirectory(directory, itemID: itemID) else {
                throw AppError.outputDirectoryUnavailable(directory.path)
            }
            return
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            try Data(itemID.uuidString.utf8).write(to: directory.appendingPathComponent(Self.ownerFile), options: .withoutOverwriting)
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    static func isOwnedDirectory(_ directory: URL, itemID: UUID) -> Bool {
        guard directory.lastPathComponent == ".youtubejack-download-\(itemID.uuidString)",
              let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { return false }
        let owner = directory.appendingPathComponent(ownerFile)
        guard (try? owner.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return false }
        return (try? Data(contentsOf: owner)) == Data(itemID.uuidString.utf8)
    }
}
