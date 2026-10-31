import Foundation
import Testing
@testable import YouTubeJackCore

struct DownloadSafetyTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["YOUTUBEJACK_TEST_YTDLP"] != nil))
    func realYTDLPExpandsIdenticalTitlesToDifferentFilesWithoutNetworking() async throws {
        let executable = try #require(ProcessInfo.processInfo.environment["YOUTUBEJACK_TEST_YTDLP"])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var names: [String] = []
        for id in ["AAAAAAAAAAA", "BBBBBBBBBBB"] {
            let info: [String: Any] = ["id": id, "title": "Aynı başlık", "extractor": "youtube", "extractor_key": "Youtube",
                                     "url": "http://127.0.0.1:9/offline.mp4", "ext": "mp4", "format_id": "18",
                                     "formats": [["format_id": "18", "url": "http://127.0.0.1:9/offline.mp4", "ext": "mp4", "height": 720, "vcodec": "avc1", "acodec": "mp4a"]]]
            let metadata = root.appendingPathComponent("\(id).json")
            try JSONSerialization.data(withJSONObject: info).write(to: metadata)
            let item = DownloadItem(url: "https://www.youtube.com/watch?v=\(id)", title: "Aynı başlık", quality: .q720, container: .mp4)
            let result = try await ProcessRunner().run(executablePath: executable, arguments: [
                "--ignore-config", "--no-cache-dir", "--skip-download", "--print", "filename",
                "--load-info-json", metadata.path, "--paths", "home:\(root.path)", "-o", DownloadService.outputTemplate(for: item)
            ])
            let name = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(name.contains(id))
            names.append(name)
        }
        #expect(Set(names).count == 2)
    }

    @Test func audioReportsTheFinalM4AAndUsesAPrivateTemporaryPath() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = root.appendingPathComponent("yt-dlp")
        try """
        #!/bin/sh
        root="${0%/*}"
        printf '%s\\n' "$@" > "$root/args"
        printf '[download] Destination: %s/source.webm\\n' "$root"
        printf 'audio' > "$root/final.m4a"
        printf '[ExtractAudio] Destination: %s/final.m4a\\n' "$root"
        for arg do
          if [ "$arg" = 'after_move:download-output:%(filepath)s' ]; then printf 'download-output:%s/final.m4a\\n' "$root"; fi
        done
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let item = DownloadItem(url: "https://www.youtube.com/watch?v=AAAAAAAAAAA", title: "Audio", quality: .audioM4A, container: .mp4)
        let resolver = DependencyResolver(managedBinDirectory: root, bundledBinDirectory: nil, systemSearchPaths: [])
        let result = try await DownloadService(dependencyResolver: resolver).download(item: item, outputDirectory: root.path, onProgress: { _ in }, onOutputPath: { _ in })
        #expect(result == root.appendingPathComponent("final.m4a").path)
        let arguments = try String(contentsOf: root.appendingPathComponent("args"))
        let workspace = DownloadWorkspace(outputDirectory: root.path, itemID: item.id)
        #expect(arguments.contains("home:\(root.path)"))
        #expect(arguments.contains("temp:\(workspace.directory.path)"))
        #expect(FileManager.default.fileExists(atPath: workspace.directory.path) == false)
    }

    @Test func outputNameSeparatesVideosAndDownloadChoices() {
        let item = DownloadItem(url: "https://www.youtube.com/watch?v=AAAAAAAAAAA", title: "Same title", quality: .q720, container: .mp4)
        let higherQuality = DownloadItem(url: item.url, title: item.title, quality: .q1080, container: .mp4)
        let captioned = DownloadItem(url: item.url, title: item.title, quality: .q720, container: .mp4, subtitles: SubtitleOptions(isEnabled: true))
        let template = DownloadService.outputTemplate(for: item)
        #expect(template.contains("%(id)s"))
        #expect(template != DownloadService.outputTemplate(for: higherQuality))
        #expect(template != DownloadService.outputTemplate(for: captioned))
        #expect(template == DownloadService.outputTemplate(for: item))
        #expect(template.hasPrefix("/") == false)
    }

    @Test func cleanupRemovesOnlyTheOwnedWorkspace() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let itemID = UUID()
        let workspace = DownloadWorkspace(outputDirectory: root.path, itemID: itemID)
        try workspace.prepare()
        try workspace.prepare() // A paused item resumes in the same owned directory.
        let finished = root.appendingPathComponent("finished.mp4")
        try Data("preserve".utf8).write(to: finished)
        try Data("partial".utf8).write(to: workspace.directory.appendingPathComponent("video.mp4.part"))
        DownloadArtifactCleaner().removeWorkspace(at: workspace.directory.path, itemID: UUID())
        #expect(FileManager.default.fileExists(atPath: workspace.directory.path))
        DownloadArtifactCleaner().removeWorkspace(at: finished.path, itemID: itemID)
        #expect(try String(contentsOf: finished) == "preserve")
        DownloadArtifactCleaner().removeWorkspace(at: workspace.directory.path, itemID: itemID)
        #expect(FileManager.default.fileExists(atPath: workspace.directory.path) == false)
        #expect(try String(contentsOf: finished) == "preserve")
    }

    @Test func unownedAndSymlinkWorkspacesAreRejected() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let workspace = DownloadWorkspace(outputDirectory: root.path, itemID: id)
        try FileManager.default.createDirectory(at: workspace.directory, withIntermediateDirectories: true)
        #expect(throws: (any Error).self) { try workspace.prepare() }
        DownloadArtifactCleaner().removeWorkspace(at: workspace.directory.path, itemID: id)
        #expect(FileManager.default.fileExists(atPath: workspace.directory.path))
        try FileManager.default.removeItem(at: workspace.directory)
        let existing = root.appendingPathComponent("existing")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: workspace.directory, withDestinationURL: existing)
        #expect(throws: (any Error).self) { try workspace.prepare() }
        DownloadArtifactCleaner().removeWorkspace(at: workspace.directory.path, itemID: id)
        #expect(FileManager.default.fileExists(atPath: existing.path))
    }
}
