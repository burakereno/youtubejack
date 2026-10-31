import Foundation
import Testing
@testable import YouTubeJackCore

struct SubtitleServiceTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["YOUTUBEJACK_TEST_FFMPEG"] != nil), arguments: [DownloadContainer.mp4, .webm])
    func realFFmpegEmbedsReadableTracksWithoutSidecars(container: DownloadContainer) async throws {
        let ffmpeg = try #require(ProcessInfo.processInfo.environment["YOUTUBEJACK_TEST_FFMPEG"])
        let fixture = try SubtitleFixture(container: container, realFFmpeg: ffmpeg)
        defer { fixture.clean() }
        let runner = ProcessRunner()
        _ = try await runner.run(executablePath: ffmpeg, arguments: [
            "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "color=size=64x64:rate=5",
            "-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo", "-t", "1",
            "-c:v", container == .mp4 ? "libx264" : "libvpx-vp9",
            "-c:a", container == .mp4 ? "aac" : "libopus",
            fixture.root.appendingPathComponent("source.\(container.rawValue)").path
        ])
        var message: String?
        _ = try await fixture.download(options: SubtitleOptions(isEnabled: true, languageCodes: ["en", "tr"]), message: { message = $0 })
        #expect(message?.contains("videoya eklendi") == true)
        for (index, code) in ["en", "tr"].enumerated() {
            let caption = try await runner.run(executablePath: ffmpeg, arguments: [
                "-nostdin", "-hide_banner", "-loglevel", "error", "-i", fixture.video.path,
                "-map", "0:s:\(index)", "-c:s", "srt", "-f", "srt", "pipe:1"
            ])
            #expect(caption.stdout.contains("Caption \(code)"))
        }
        #expect(try fixture.outputNames == [fixture.video.lastPathComponent])
    }

    @Test(arguments: [DownloadContainer.mp4, .webm])
    func embedsMultipleLanguagesAndLeavesOnlyVideo(container: DownloadContainer) async throws {
        let fixture = try SubtitleFixture(container: container)
        defer { fixture.clean() }
        let options = SubtitleOptions(isEnabled: true, languageCodes: ["tr", "en"])
        var message: String?
        let path = try await fixture.download(options: options, message: { message = $0 })
        #expect(path == fixture.video.path)
        #expect(try String(contentsOf: fixture.video) == "embedded")
        #expect(message?.contains("videoya eklendi") == true)
        #expect(try fixture.outputNames == [fixture.video.lastPathComponent])
        let args = try String(contentsOf: fixture.root.appendingPathComponent("ffmpeg-arguments"))
        #expect(args.contains(container == .mp4 ? "mov_text" : "webvtt"))
        #expect(args.contains("language=tur"))
        #expect(args.contains("language=eng"))
    }

    @Test(arguments: [SubtitleFormat.srt, .vtt])
    func separateFilesUseVideoBasenameAndReportMissingLanguage(format: SubtitleFormat) async throws {
        let fixture = try SubtitleFixture(available: ["en"])
        defer { fixture.clean() }
        var message: String?
        var artifacts: [String] = []
        _ = try await fixture.download(
            options: SubtitleOptions(isEnabled: true, languageCodes: ["tr", "en"], delivery: .separateFile, format: format),
            message: { message = $0 }, artifact: { artifacts.append($0) }
        )
        #expect(try fixture.outputNames == ["Video.en.\(format.rawValue)", "Video.mp4"])
        #expect(try String(contentsOf: fixture.video) == "original")
        #expect(message?.contains("Bulunamayan altyazı") == true)
        #expect(artifacts == [fixture.output.appendingPathComponent("Video.en.\(format.rawValue)").path])
    }

    @Test(arguments: ["missing", "requestFailure", "embeddingFailure"])
    func subtitleProblemsPreserveCompletedMedia(scenario: String) async throws {
        let fixture = try SubtitleFixture(available: scenario == "missing" ? [] : ["en"], scenario: scenario)
        defer { fixture.clean() }
        var message: String?
        let path = try await fixture.download(options: SubtitleOptions(isEnabled: true, languageCodes: ["en"]), message: { message = $0 })
        #expect(path == fixture.video.path)
        #expect(try String(contentsOf: fixture.video) == "original")
        #expect(message?.isEmpty == false)
        #expect(try fixture.outputNames == ["Video.mp4"])
    }

    @Test func automaticFallbackIsOptInAndExistingSidecarsArePreserved() async throws {
        let fixture = try SubtitleFixture(available: ["en"])
        defer { fixture.clean() }
        let existing = fixture.output.appendingPathComponent("Video.en.srt")
        try "user captions".write(to: existing, atomically: true, encoding: .utf8)
        var message: String?
        _ = try await fixture.download(options: SubtitleOptions(isEnabled: true, languageCodes: ["en"], includesAutomatic: false, delivery: .separateFile), message: { message = $0 })
        #expect(try String(contentsOf: existing) == "user captions")
        #expect(message?.contains("korundu") == true)
        let args = try String(contentsOf: fixture.root.appendingPathComponent("subtitle-arguments"))
        #expect(args.contains("--no-write-auto-subs"))
        #expect(args.contains("--write-auto-subs\n") == false)
    }

    @Test func oneFailedLanguageDoesNotDiscardOtherCompletedCaptions() async throws {
        let fixture = try SubtitleFixture(scenario: "partial")
        defer { fixture.clean() }
        var message: String?
        _ = try await fixture.download(options: SubtitleOptions(isEnabled: true, languageCodes: ["en", "tr"], delivery: .separateFile), message: { message = $0 })
        #expect(try fixture.outputNames == ["Video.en.srt", "Video.mp4"])
        #expect(message?.contains("Bulunamayan altyazı") == true)
        #expect(message?.contains("indirilemedi") == true)
    }

    @Test func pauseBeforeCaptionProcessStartsPropagatesCancellation() async throws {
        let fixture = try SubtitleFixture()
        defer { fixture.clean() }
        let resolver = DependencyResolver(managedBinDirectory: fixture.root, bundledBinDirectory: nil, systemSearchPaths: [])
        let service = DownloadService(dependencyResolver: resolver)
        do {
            _ = try await service.download(
                item: DownloadItem(url: "https://www.youtube.com/watch?v=j8qdnqwjRJA", title: "Video", quality: .q1080, container: .mp4, subtitles: SubtitleOptions(isEnabled: true, languageCodes: ["en"])),
                outputDirectory: fixture.output.path, onProgress: { _ in }, onOutputPath: { _ in },
                onSubtitleMessage: { if $0 == "Altyazılar indiriliyor…" { service.cancelCurrentDownload() } }
            )
            Issue.record("Pause must stop before the caption process starts.")
        } catch is CancellationError {
            #expect(try String(contentsOf: fixture.video) == "original")
            #expect(try fixture.outputNames == ["Video.mp4"])
            #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("subtitle-started").path) == false)
        }
    }

    @Test func cancellationDuringSubtitleStageDoesNotReplaceVideo() async throws {
        let fixture = try SubtitleFixture(scenario: "wait")
        defer { fixture.clean() }
        let task = Task {
            try await fixture.download(options: SubtitleOptions(isEnabled: true, languageCodes: ["en"]))
        }
        let marker = fixture.root.appendingPathComponent("subtitle-started")
        for _ in 0..<200 {
            if FileManager.default.fileExists(atPath: marker.path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(FileManager.default.fileExists(atPath: marker.path))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancellation must propagate instead of reporting completion.")
        } catch is CancellationError {
            #expect(try String(contentsOf: fixture.video) == "original")
            #expect(try fixture.outputNames == ["Video.mp4"])
        }
    }

    @Test func disabledSubtitlesDoNotRunCaptionStage() async throws {
        let fixture = try SubtitleFixture()
        defer { fixture.clean() }
        _ = try await fixture.download(options: SubtitleOptions())
        #expect(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("subtitle-arguments").path) == false)
    }
}

private struct SubtitleFixture: Sendable {
    let root: URL
    let output: URL
    let video: URL
    let container: DownloadContainer

    init(container: DownloadContainer = .mp4, available: [String] = ["en", "tr"], scenario: String = "success", realFFmpeg: String? = nil) throws {
        self.container = container
        root = FileManager.default.temporaryDirectory.appendingPathComponent("subtitle-test-\(UUID().uuidString)")
        output = root.appendingPathComponent("output")
        video = output.appendingPathComponent("Video.\(container.rawValue)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let subtitleTracks = Dictionary(uniqueKeysWithValues: available.map { ($0, [["ext": "vtt"]]) })
        let metadata = try JSONSerialization.data(withJSONObject: ["subtitles": subtitleTracks])
        try metadata.write(to: root.appendingPathComponent("metadata.json"))
        try Self.writeExecutable("yt-dlp", root: root, script: """
        #!/bin/sh
        root="$(dirname "$0")"
        printf '%s\\n' "$@" > "$root/last-arguments"
        subtitles=0
        metadata=0
        format=srt
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --skip-download) subtitles=1 ;;
            --dump-single-json) metadata=1 ;;
            --convert-subs) shift; format="$1" ;;
            -o) shift; output="$1" ;;
          esac
          shift
        done
        if [ "$metadata" -eq 1 ]; then cat "$root/metadata.json"; exit 0; fi
        if [ "$subtitles" -eq 1 ]; then
          cp "$root/last-arguments" "$root/subtitle-arguments"
          touch "$root/subtitle-started"
          if [ "\(scenario)" = requestFailure ]; then printf 'HTTP Error 429: captions failed\\n' >&2; exit 1; fi
          if [ "\(scenario)" = wait ]; then exec /bin/sleep 30; fi
          for code in \(available.joined(separator: " ")); do
            if [ "\(scenario)" = partial ] && [ "$code" = tr ]; then continue; fi
            if [ "$format" = vtt ]; then
              printf 'WEBVTT\\n\\n00:00.000 --> 00:00.800\\nCaption %s\\n' "$code" > "$(dirname "$output")/subtitle.$code.$format"
            else
              printf '1\\n00:00:00,000 --> 00:00:00,800\\nCaption %s\\n' "$code" > "$(dirname "$output")/subtitle.$code.$format"
            fi
          done
          if [ "\(scenario)" = partial ]; then printf 'caption request failed\\n' >&2; exit 1; fi
        else
          if [ -f "$root/source.\(container.rawValue)" ]; then
            cp "$root/source.\(container.rawValue)" "$root/output/Video.\(container.rawValue)"
          else
            printf 'original' > "$root/output/Video.\(container.rawValue)"
          fi
          printf 'download-output:%s/output/Video.\(container.rawValue)\\n' "$root"
        fi
        """)
        let ffmpegScript = realFFmpeg.map { "#!/bin/sh\nexec '\($0.replacingOccurrences(of: "'", with: "'\\''"))' \"$@\"\n" } ?? """
        #!/bin/sh
        printf '%s\\n' "$@" > "$(dirname "$0")/ffmpeg-arguments"
        if [ "\(scenario)" = embeddingFailure ]; then printf 'embedding failed\\n' >&2; exit 1; fi
        for argument in "$@"; do output="$argument"; done
        printf 'embedded' > "$output"
        """
        try Self.writeExecutable("ffmpeg", root: root, script: ffmpegScript)
    }

    func download(options: SubtitleOptions, message: @escaping (String?) -> Void = { _ in }, artifact: @escaping (String) -> Void = { _ in }) async throws -> String? {
        let resolver = DependencyResolver(managedBinDirectory: root, bundledBinDirectory: nil, systemSearchPaths: [])
        return try await DownloadService(dependencyResolver: resolver).download(
            item: DownloadItem(url: "https://www.youtube.com/watch?v=j8qdnqwjRJA", title: "Video", quality: .q1080, container: container, subtitles: options),
            outputDirectory: output.path, onProgress: { _ in }, onOutputPath: { _ in },
            onSubtitleMessage: message, onArtifactPath: artifact
        )
    }

    var outputNames: [String] {
        get throws { try FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil, options: .skipsHiddenFiles).map(\.lastPathComponent).sorted() }
    }

    func clean() { try? FileManager.default.removeItem(at: root) }

    static func writeExecutable(_ name: String, root: URL, script: String) throws {
        let url = root.appendingPathComponent(name)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
