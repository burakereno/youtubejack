import XCTest
@testable import YouTubeJackCore

final class QualityProfileTests: XCTestCase {
    func testBuildsExactMP4SelectorForResolution() {
        let selector = QualityProfile.q1080.formatSelector(container: .mp4)
        XCTAssertTrue(selector.contains("height<=1080"))
        XCTAssertTrue(selector.contains("height>720"))
        XCTAssertTrue(selector.contains("ext=mp4"))
        XCTAssertTrue(selector.contains("ba[ext=m4a]"))
    }

    func testBuildsExactWebMSelectorForResolution() {
        let selector = QualityProfile.q1440.formatSelector(container: .webm)
        XCTAssertTrue(selector.contains("height<=1440"))
        XCTAssertTrue(selector.contains("height>1080"))
        XCTAssertTrue(selector.contains("ext=webm"))
        XCTAssertTrue(selector.contains("ba[ext=webm]"))
    }

    func testBuilds480BandWithoutLowerHeightLimit() {
        let selector = QualityProfile.q480.formatSelector(container: .webm)
        XCTAssertTrue(selector.contains("height<=480"))
        XCTAssertFalse(selector.contains("height>"))
    }

    func testH264SelectorFiltersBothSplitAndCombinedVideo() {
        let selector = QualityProfile.q1080.formatSelector(container: .mp4, codec: .h264)
        XCTAssertEqual(selector.components(separatedBy: VideoCodecPreference.h264.formatFilter).count - 1, 2)
        XCTAssertFalse(selector.contains("av01"))
    }

    func testAV1SelectorFiltersWebMVideo() {
        let selector = QualityProfile.best.formatSelector(container: .webm, codec: .av1)
        XCTAssertTrue(selector.contains("[ext=webm]\(VideoCodecPreference.av1.formatFilter)"))
    }
}
