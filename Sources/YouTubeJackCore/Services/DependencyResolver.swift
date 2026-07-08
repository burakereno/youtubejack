import Foundation

public final class DependencyResolver: Sendable {
    public init() {}

    public func resolveStatus() -> DependencyStatus {
        DependencyStatus(
            ytdlp: findTool(named: "yt-dlp"),
            ffmpeg: findTool(named: "ffmpeg"),
            jsRuntimePath: findExecutable(named: "node") ?? findExecutable(named: "deno")
        )
    }

    public func requireYTDLP() throws -> String {
        guard let path = findTool(named: "yt-dlp")?.path else {
            throw AppError.missingDependency("yt-dlp")
        }
        return path
    }

    public func ffmpegPath() -> String? {
        findTool(named: "ffmpeg")?.path
    }

    public func managedBinDirectory() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppError.outputDirectoryUnavailable("Application Support")
        }
        return applicationSupport
            .appendingPathComponent("YouTubeJack", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    public func bundledBinDirectory() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("bin", isDirectory: true)
    }

    public func findTool(named name: String) -> RuntimeTool? {
        let fileManager = FileManager.default

        if let managedDirectory = try? managedBinDirectory() {
            let path = managedDirectory.appendingPathComponent(name).path
            if fileManager.isExecutableFile(atPath: path) {
                return RuntimeTool(name: name, path: path, origin: .managed)
            }
        }

        if let bundledDirectory = bundledBinDirectory() {
            let path = bundledDirectory.appendingPathComponent(name).path
            if fileManager.isExecutableFile(atPath: path) {
                return RuntimeTool(name: name, path: path, origin: .bundled)
            }
        }

        return nil
    }

    public func findExecutable(named name: String) -> String? {
        findSystemExecutable(named: name)
    }

    private func findSystemExecutable(named name: String) -> String? {
        var candidates: [String] = []
        let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? ""
        candidates.append(contentsOf: pathValue.split(separator: ":").map { String($0) })
        candidates.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/opt/local/bin"
        ])

        let fileManager = FileManager.default
        for directory in Array(Set(candidates)) {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
