import Foundation
import Testing
@testable import YouTubeJackCore

struct DownloadPipelineIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["YOUTUBEJACK_TEST_YTDLP"] != nil && ProcessInfo.processInfo.environment["YOUTUBEJACK_TEST_FFMPEG"] != nil), .timeLimit(.minutes(1)))
    func realToolsKeepSameTitleVideosSeparateAndReportConvertedAudio() async throws {
        let fixture = try await LocalMediaFixture()
        defer { fixture.clean() }
        let service = DownloadService(dependencyResolver: fixture.resolver)
        var published: [String] = []
        for id in ["AAAAAAAAAAA", "BBBBBBBBBBB"] {
            let item = DownloadItem(url: "https://www.youtube.com/watch?v=\(id)", title: "Aynı başlık", quality: .q720, container: .mp4)
            var paths: [String] = []
            let result = try #require(await service.download(item: item, outputDirectory: fixture.output.path, onProgress: { _ in }, onOutputPath: { paths.append($0) }))
            #expect(result.contains(id))
            #expect(URL(fileURLWithPath: result).deletingLastPathComponent().path == fixture.output.path)
            #expect(try Data(contentsOf: URL(fileURLWithPath: result)) == Data(contentsOf: fixture.root.appendingPathComponent("\(id).mp4")))
            let workspace = DownloadWorkspace(outputDirectory: fixture.output.path, itemID: item.id)
            #expect(paths.contains(where: { $0.hasPrefix(workspace.directory.path + "/") }))
            #expect(FileManager.default.fileExists(atPath: workspace.directory.path) == false)
            published.append(result)
        }
        #expect(Set(published).count == 2)
        let audio = DownloadItem(url: "https://www.youtube.com/watch?v=CCCCCCCCCCC", title: "Audio", quality: .audioM4A, container: .mp4)
        let audioPath = try #require(await service.download(item: audio, outputDirectory: fixture.output.path, onProgress: { _ in }, onOutputPath: { _ in }))
        #expect(audioPath.hasSuffix(".m4a"))
        #expect(FileManager.default.fileExists(atPath: audioPath))
        let ffmpeg = try #require(ProcessInfo.processInfo.environment["YOUTUBEJACK_TEST_FFMPEG"])
        _ = try await ProcessRunner().run(executablePath: ffmpeg, arguments: ["-nostdin", "-v", "error", "-i", audioPath, "-f", "null", "-"])
        let names = try FileManager.default.contentsOfDirectory(atPath: fixture.output.path)
        #expect(names.count == 3)
        #expect(names.contains(where: { $0.hasPrefix(".youtubejack-download-") }) == false)
    }
}

private struct LocalMediaFixture {
    let root: URL
    let output: URL
    let server: Process
    var resolver: DependencyResolver { DependencyResolver(managedBinDirectory: root.appendingPathComponent("bin"), bundledBinDirectory: nil, systemSearchPaths: []) }

    init() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("youtubejack-local-media-\(UUID().uuidString)")
        output = root.appendingPathComponent("Downloads with spaces")
        let bin = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let ffmpeg = try #require(ProcessInfo.processInfo.environment["YOUTUBEJACK_TEST_FFMPEG"])
        let ytdlp = try #require(ProcessInfo.processInfo.environment["YOUTUBEJACK_TEST_YTDLP"])
        let runner = ProcessRunner()
        for (id, color) in [("AAAAAAAAAAA", "red"), ("BBBBBBBBBBB", "blue")] {
            _ = try await runner.run(executablePath: ffmpeg, arguments: [
                "-nostdin", "-v", "error", "-y", "-f", "lavfi", "-i", "color=c=\(color):size=64x64:rate=5",
                "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", "0.6", "-c:v", "libx264", "-c:a", "aac",
                root.appendingPathComponent("\(id).mp4").path
            ])
        }
        _ = try await runner.run(executablePath: ffmpeg, arguments: [
            "-nostdin", "-v", "error", "-y", "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo", "-t", "0.6", "-c:a", "libopus", root.appendingPathComponent("CCCCCCCCCCC.webm").path
        ])
        let portFile = root.appendingPathComponent("port")
        server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-u", "-c", """
        import http.server,os,sys
        os.chdir(sys.argv[1])
        class Handler(http.server.SimpleHTTPRequestHandler):
            def log_message(self,*args): pass
        server=http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler)
        with open(sys.argv[2],'w') as f: f.write(str(server.server_port))
        server.serve_forever()
        """, root.path, portFile.path]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        try server.run()
        let deadline = ContinuousClock.now + .seconds(5)
        while FileManager.default.fileExists(atPath: portFile.path) == false, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        let port = try String(contentsOf: portFile)
        for id in ["AAAAAAAAAAA", "BBBBBBBBBBB", "CCCCCCCCCCC"] {
            let audioOnly = id == "CCCCCCCCCCC"
            let ext = audioOnly ? "webm" : "mp4"
            var format: [String: Any] = ["format_id": "18", "url": "http://127.0.0.1:\(port)/\(id).\(ext)", "ext": ext, "vcodec": audioOnly ? "none" : "avc1", "acodec": audioOnly ? "opus" : "mp4a"]
            if audioOnly == false { format["height"] = 720 }
            let info: [String: Any] = ["id": id, "title": "Aynı başlık", "extractor": "youtube", "extractor_key": "Youtube", "webpage_url": "https://www.youtube.com/watch?v=\(id)", "formats": [format]]
            try JSONSerialization.data(withJSONObject: info).write(to: root.appendingPathComponent("\(id).json"))
        }
        let wrapper = """
        #!/usr/bin/python3
        import os,sys,urllib.parse
        executable=\(String(reflecting: ytdlp))
        args=sys.argv[1:]
        if args == ['--version']: os.execv(executable,[executable]+args)
        video=urllib.parse.parse_qs(urllib.parse.urlparse(args.pop()).query)['v'][0]
        root=os.path.dirname(os.path.dirname(__file__))
        os.execv(executable,[executable]+args+['--load-info-json',os.path.join(root,video+'.json')])
        """
        let file = bin.appendingPathComponent("yt-dlp")
        try wrapper.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        try FileManager.default.createSymbolicLink(at: bin.appendingPathComponent("ffmpeg"), withDestinationURL: URL(fileURLWithPath: ffmpeg))
    }

    func clean() {
        if server.isRunning { server.terminate(); server.waitUntilExit() }
        try? FileManager.default.removeItem(at: root)
    }
}
