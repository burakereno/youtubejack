import XCTest
@testable import YouTubeJackCore

final class MetadataServiceTests: XCTestCase {
    func testLargeVideoMetadataPreservesFormatsAtEndOfOutput() async throws {
        let title = "Büyük video — Türkçe 🎬"
        let padding = String(repeating: "a", count: 2 * 1_048_576)
        let json = """
        {"description":"\(padding)","id":"CpkM0qAkBNY","title":"\(title)","formats":[
          {"format_id":"313","ext":"webm","height":2160,"vcodec":"vp9","acodec":"none"},
          {"format_id":"251","ext":"webm","vcodec":"none","acodec":"opus"}
        ]}
        """
        let directory = try makeToolDirectory(output: json)
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await makeService(directory: directory)
            .fetch(url: "https://www.youtube.com/watch?v=CpkM0qAkBNY")

        XCTAssertEqual(result.media.title, title)
        XCTAssertTrue(result.media.formatAvailability.isKnown)
        XCTAssertEqual(result.media.formatAvailability.formats.map(\.id), ["313", "251"])
        XCTAssertTrue(result.media.formatAvailability.isResolutionAvailable(.q2160))
        XCTAssertTrue(result.media.formatAvailability.isContainerAvailable(.webm, for: .q2160))
    }

    func testLargePlaylistMetadataPreservesEveryEntry() async throws {
        let count = 3_000
        let title = String(repeating: "Türkçe 🎬 ", count: 40)
        let entries = (0..<count).map { index in
            ["id": String(format: "%011d", index), "title": "\(title)\(index)"]
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "id": "PLlargeMetadata",
            "title": "Large playlist",
            "entries": entries
        ])
        XCTAssertGreaterThan(data.count, 1_048_576)
        let directory = try makeToolDirectory(output: String(decoding: data, as: UTF8.self))
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try await makeService(directory: directory)
            .fetch(url: "https://www.youtube.com/playlist?list=PLlargeMetadata")

        XCTAssertEqual(result.media.kind, .playlist)
        XCTAssertEqual(result.media.entryCount, count)
        XCTAssertEqual(result.entries.count, count)
        XCTAssertEqual(result.entries.last?.title, "\(title)\(count - 1)")
        XCTAssertEqual(result.entries.last?.index, count)
    }

    func testInvalidMetadataReturnsReadableError() async throws {
        for output in ["", "{\"title\":", "not JSON"] {
            let directory = try makeToolDirectory(output: output)
            defer { try? FileManager.default.removeItem(at: directory) }

            do {
                _ = try await makeService(directory: directory)
                    .fetch(url: "https://www.youtube.com/watch?v=CpkM0qAkBNY")
                XCTFail("Expected invalid metadata to fail")
            } catch {
                XCTAssertEqual(error as? AppError, .metadataDecodeFailed)
            }
        }
    }

    private func makeService(directory: URL) -> MetadataService {
        MetadataService(dependencyResolver: DependencyResolver(
            managedBinDirectory: directory,
            bundledBinDirectory: nil,
            systemSearchPaths: []
        ))
    }

    private func makeToolDirectory(output: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            try output.write(to: directory.appendingPathComponent("metadata.json"), atomically: true, encoding: .utf8)
            let executable = directory.appendingPathComponent("yt-dlp")
            try "#!/bin/sh\nexec /bin/cat \"${0%/*}/metadata.json\"\n"
                .write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
            return directory
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }
}
