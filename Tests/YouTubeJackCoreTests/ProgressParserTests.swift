import XCTest
@testable import YouTubeJackCore

final class ProgressParserTests: XCTestCase {
    func testParsesProgressTemplateLine() {
        let progress = ProgressParser.parse("download-progress: 42.5%|1.2MiB/s|00:15")
        XCTAssertEqual(progress?.fraction, 0.425)
        XCTAssertEqual(progress?.speed, "1.2MiB/s")
        XCTAssertEqual(progress?.eta, "00:15")
    }

    func testParsesDestination() {
        let path = ProgressParser.destinationPath("[download] Destination: /tmp/video.mp4")
        XCTAssertEqual(path, "/tmp/video.mp4")
    }
}
