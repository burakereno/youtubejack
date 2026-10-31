import Foundation

enum UpdateArtifactDownloader {
    static func download(from url: URL, onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let transfer = UpdateTransfer()
        let artifact: URL = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = URLSession.shared.downloadTask(with: url) { temporaryURL, response, error in
                    // URLSession owns temporaryURL only until this callback returns.
                    let result = Result {
                        if let error { throw error }
                        guard let temporaryURL else { throw UpdateError.badResponse }
                        return try retainTemporaryFile(at: temporaryURL, response: response)
                    }
                    transfer.finish()
                    continuation.resume(with: result)
                }
                transfer.start(task, onProgress: onProgress)
            }
        } onCancel: {
            transfer.cancel()
        }
        do {
            try Task.checkCancellation()
            return artifact
        } catch {
            removeArtifact(at: artifact)
            throw error
        }
    }

    static func retainTemporaryFile(at temporaryURL: URL, response: URLResponse?) throws -> URL {
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            throw UpdateError.badResponse
        }
        let id = UUID().uuidString
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("youtubejack-update-\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            try Data(id.utf8).write(to: directory.appendingPathComponent(".youtubejack-update-owner"), options: .withoutOverwriting)
            let destination = directory.appendingPathComponent("YouTubeJack.dmg")
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func isOwnedDirectory(_ directory: URL) -> Bool {
        let prefix = "youtubejack-update-"
        guard directory.lastPathComponent.hasPrefix(prefix),
              UUID(uuidString: String(directory.lastPathComponent.dropFirst(prefix.count))) != nil,
              directory.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL,
              let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true,
              let attributes = try? FileManager.default.attributesOfItem(atPath: directory.path),
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { return false }
        let marker = directory.appendingPathComponent(".youtubejack-update-owner")
        guard (try? marker.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return false }
        return (try? String(contentsOf: marker)) == String(directory.lastPathComponent.dropFirst(prefix.count))
    }

    static func removeArtifact(at artifact: URL) {
        let directory = artifact.deletingLastPathComponent()
        guard isOwnedDirectory(directory) else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

/// URLSession callbacks and task cancellation can arrive on different queues; state is lock-protected.
private final class UpdateTransfer: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var observation: NSKeyValueObservation?
    private var cancelled = false

    func start(_ task: URLSessionDownloadTask, onProgress: @escaping @Sendable (Double) -> Void) {
        let shouldCancel = lock.withLock {
            self.task = task
            observation = task.progress.observe(\.fractionCompleted) { progress, _ in onProgress(progress.fractionCompleted) }
            return cancelled
        }
        if shouldCancel { task.cancel() }
        task.resume()
    }

    func cancel() {
        let task = lock.withLock { cancelled = true; return self.task }
        task?.cancel()
    }

    func finish() {
        lock.withLock {
            observation?.invalidate()
            observation = nil
            task = nil
        }
    }
}
