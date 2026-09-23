import XCTest
@testable import YouTubeJackCore

final class DownloadServiceTests: XCTestCase {
    func testH264DownloadReportsActualSelectedCodecs() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try writeExecutable("yt-dlp", in: directory, script: """
        #!/bin/sh
        printf '%s\\n' "$@" > "$(dirname "$0")/arguments"
        printf 'download-codecs:1080|avc1.640028|mp4a.40.2\\n'
        printf '[download] Destination: /tmp/h264.mp4\\n'
        printf 'download-output:/tmp/final-h264.mp4\\n'
        """)

        let resolver = DependencyResolver(
            managedBinDirectory: directory,
            bundledBinDirectory: nil,
            systemSearchPaths: [directory.path]
        )
        let item = DownloadItem(
            url: "https://www.youtube.com/watch?v=j8qdnqwjRJA",
            title: "H264 fixture",
            quality: .q1080,
            container: .mp4,
            videoCodecPreference: .h264
        )
        var selected: SelectedMediaFormat?
        let path = try await DownloadService(dependencyResolver: resolver).download(
            item: item,
            outputDirectory: directory.appendingPathComponent("output").path,
            onProgress: { _ in },
            onOutputPath: { _ in },
            onSelectedMediaFormat: { selected = $0 }
        )

        XCTAssertEqual(path, "/tmp/final-h264.mp4")
        XCTAssertEqual(selected?.height, 1080)
        XCTAssertEqual(selected?.videoCodecTitle, "H.264")
        XCTAssertEqual(selected?.audioCodecTitle, "AAC")
        let arguments = try String(contentsOf: directory.appendingPathComponent("arguments"))
        XCTAssertTrue(arguments.contains(VideoCodecPreference.h264.formatFilter))
        XCTAssertTrue(arguments.contains("--no-simulate"))
    }

    func testForbiddenDownloadRetriesWithChunkingAndExplicitRuntime() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try writeExecutable("node", in: directory, script: "#!/bin/sh\nexit 0\n")
        try writeExecutable("yt-dlp", in: directory, script: """
        #!/bin/sh
        runtime=0
        chunked=0
        for argument in "$@"; do
          case "$argument" in
            node:*) runtime=1 ;;
            --http-chunk-size) chunked=1 ;;
          esac
        done
        printf 'attempt\\n' >> "$(dirname "$0")/attempts"
        if [ "$runtime" -ne 1 ]; then
          printf 'ERROR: JavaScript runtime missing\\n' >&2
          exit 1
        fi
        if [ "$chunked" -ne 1 ]; then
          printf 'ERROR: unable to download video data: HTTP Error 403: Forbidden\\n' >&2
          exit 1
        fi
        printf '[download] Destination: /tmp/recovered.mp4\\n'
        """)

        let resolver = DependencyResolver(
            managedBinDirectory: directory,
            bundledBinDirectory: nil,
            systemSearchPaths: [directory.path]
        )
        let item = DownloadItem(
            url: "https://www.youtube.com/watch?v=j8qdnqwjRJA",
            title: "Retry fixture",
            quality: .best,
            container: .mp4
        )
        let path = try await DownloadService(dependencyResolver: resolver).download(
            item: item,
            outputDirectory: directory.appendingPathComponent("output").path,
            onProgress: { _ in },
            onOutputPath: { _ in }
        )

        XCTAssertEqual(path, "/tmp/recovered.mp4")
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("attempts")), "attempt\nattempt\n")
    }

    func testMetadataUsesExplicitRuntimeToo() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeExecutable("node", in: directory, script: "#!/bin/sh\nexit 0\n")
        try writeExecutable("yt-dlp", in: directory, script: """
        #!/bin/sh
        for argument in "$@"; do
          case "$argument" in
            node:*)
              printf '%s\\n' '{"id":"j8qdnqwjRJA","title":"Runtime fixture","formats":[]}'
              exit 0
              ;;
          esac
        done
        printf 'ERROR: JavaScript runtime missing\\n' >&2
        exit 1
        """)
        let resolver = DependencyResolver(
            managedBinDirectory: directory,
            bundledBinDirectory: nil,
            systemSearchPaths: [directory.path]
        )
        let result = try await MetadataService(dependencyResolver: resolver)
            .fetch(url: "https://www.youtube.com/watch?v=j8qdnqwjRJA")
        XCTAssertEqual(result.media.title, "Runtime fixture")
    }

    func testSystemRuntimeLookupPreservesSearchPathOrder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferred = directory.appendingPathComponent("preferred")
        let fallback = directory.appendingPathComponent("fallback")
        for folder in [preferred, fallback] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try writeExecutable("node", in: folder, script: "#!/bin/sh\nexit 0\n")
        }
        let resolver = DependencyResolver(
            managedBinDirectory: directory,
            bundledBinDirectory: nil,
            systemSearchPaths: [preferred.path, fallback.path, preferred.path]
        )
        XCTAssertEqual(resolver.resolveStatus().jsRuntimePath, preferred.appendingPathComponent("node").path)
        XCTAssertEqual(resolver.javaScriptRuntimeArguments(), [
            "--no-js-runtimes", "--js-runtimes", "node:\(preferred.appendingPathComponent("node").path)"
        ])
    }

    private func writeExecutable(_ name: String, in directory: URL, script: String) throws {
        let url = directory.appendingPathComponent(name)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
