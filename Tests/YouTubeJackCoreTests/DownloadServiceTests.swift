import XCTest
@testable import YouTubeJackCore

final class DownloadServiceTests: XCTestCase {
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
