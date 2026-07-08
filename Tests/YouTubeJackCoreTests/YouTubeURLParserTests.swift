import XCTest
@testable import YouTubeJackCore

final class YouTubeURLParserTests: XCTestCase {
    func testParsesWatchURL() {
        let parsed = YouTubeURLParser().parse("https://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(parsed?.videoID, "abc123")
        XCTAssertEqual(parsed?.isPlaylist, false)
        XCTAssertEqual(parsed?.normalizedURL, "https://www.youtube.com/watch?v=abc123")
    }

    func testParsesPlaylistURL() {
        let parsed = YouTubeURLParser().parse("https://www.youtube.com/playlist?list=PL123")
        XCTAssertEqual(parsed?.playlistID, "PL123")
        XCTAssertEqual(parsed?.isPlaylist, true)
    }

    func testTreatsWatchWithListAsPlaylist() {
        let parsed = YouTubeURLParser().parse("https://www.youtube.com/watch?v=abc123&list=PL123")
        XCTAssertEqual(parsed?.videoID, "abc123")
        XCTAssertEqual(parsed?.playlistID, "PL123")
        XCTAssertEqual(parsed?.isPlaylist, true)
    }

    func testParsesShortURL() {
        let parsed = YouTubeURLParser().parse("https://youtu.be/abc123")
        XCTAssertEqual(parsed?.videoID, "abc123")
    }

    func testRejectsNonHTTPSchemes() {
        XCTAssertNil(YouTubeURLParser().parse("ftp://www.youtube.com/watch?v=abc123"))
    }

    func testNormalizesHTTPToHTTPS() {
        let parsed = YouTubeURLParser().parse("http://www.youtube.com/watch?v=abc123")
        XCTAssertEqual(parsed?.normalizedURL, "https://www.youtube.com/watch?v=abc123")
    }
}
