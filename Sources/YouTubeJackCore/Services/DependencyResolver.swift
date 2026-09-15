import Foundation

public final class DependencyResolver: Sendable {
    private let managedDirectory: URL?
    private let bundledDirectory: URL?
    private let systemSearchPaths: [String]

    public init(
        managedBinDirectory: URL? = nil,
        bundledBinDirectory: URL? = Bundle.main.resourceURL?.appendingPathComponent("bin", isDirectory: true),
        systemSearchPaths: [String]? = nil
    ) {
        managedDirectory = managedBinDirectory
        bundledDirectory = bundledBinDirectory
        self.systemSearchPaths = systemSearchPaths ?? (
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/opt/local/bin"]
        )
    }

    public func resolveStatus() -> DependencyStatus {
        DependencyStatus(
            ytdlp: findTool(named: "yt-dlp"),
            ffmpeg: findTool(named: "ffmpeg"),
            jsRuntimePath: javaScriptRuntime()?.path
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

    public func javaScriptRuntimeArguments() -> [String] {
        guard let runtime = javaScriptRuntime() else { return [] }
        // GUI apps do not inherit the shell's Homebrew PATH, and Node is opt-in in yt-dlp.
        return ["--no-js-runtimes", "--js-runtimes", "\(runtime.name):\(runtime.path)"]
    }

    private func javaScriptRuntime() -> (name: String, path: String)? {
        for name in ["deno", "node"] {
            if let path = findTool(named: name)?.path ?? findExecutable(named: name) {
                return (name, path)
            }
        }
        return nil
    }

    public func managedBinDirectory() throws -> URL {
        if let managedDirectory { return managedDirectory }
        guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw AppError.outputDirectoryUnavailable("Application Support")
        }
        return applicationSupport
            .appendingPathComponent("YouTubeJack", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    public func bundledBinDirectory() -> URL? {
        bundledDirectory
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
        let fileManager = FileManager.default
        var visited = Set<String>()
        for directory in systemSearchPaths where visited.insert(directory).inserted {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(name).path
            if fileManager.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
