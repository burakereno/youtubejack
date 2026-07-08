import XCTest
@testable import YouTubeJackCore

final class DownloadArtifactCleanerTests: XCTestCase {
    func testRemovesOnlyArtifactsForExactOutputName() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let output = directory.appendingPathComponent("Video.mp4")
        let exactPart = directory.appendingPathComponent("Video.mp4.part")
        let fragment = directory.appendingPathComponent("Video.mp4.part-Frag12")
        let sidecar = directory.appendingPathComponent("Video.mp4.ytdl")
        let unrelatedPart = directory.appendingPathComponent("Video backup.mp4.part")
        let unrelatedTemp = directory.appendingPathComponent("Video.temp")

        for url in [output, exactPart, fragment, sidecar, unrelatedPart, unrelatedTemp] {
            try Data("x".utf8).write(to: url)
        }

        DownloadArtifactCleaner().removeArtifacts(for: [output.path])

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exactPart.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fragment.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedPart.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelatedTemp.path))
    }
}
