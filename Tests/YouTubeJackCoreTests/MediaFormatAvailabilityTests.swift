import XCTest
@testable import YouTubeJackCore

final class MediaFormatAvailabilityTests: XCTestCase {
    func testEnablesOnlyExistingResolutionContainerPairs() {
        let availability = MediaFormatAvailability(
            isKnown: true,
            formats: [
                MediaFormat(id: "137", ext: "mp4", height: 1080, vcodec: "avc1.640028", acodec: "none"),
                MediaFormat(id: "140", ext: "m4a", height: nil, vcodec: "none", acodec: "mp4a.40.2"),
                MediaFormat(id: "271", ext: "webm", height: 1440, vcodec: "vp9", acodec: "none"),
                MediaFormat(id: "251", ext: "webm", height: nil, vcodec: "none", acodec: "opus")
            ]
        )

        XCTAssertTrue(availability.isResolutionAvailable(.q1080))
        XCTAssertTrue(availability.isResolutionAvailable(.q1440))
        XCTAssertTrue(availability.isContainerAvailable(.mp4, for: .q1080))
        XCTAssertFalse(availability.isContainerAvailable(.webm, for: .q1080))
        XCTAssertFalse(availability.isContainerAvailable(.mp4, for: .q1440))
        XCTAssertTrue(availability.isContainerAvailable(.webm, for: .q1440))
        XCTAssertEqual(availability.maxVideoHeight, 1440)
    }

    func testTreatsNonStandardHeightsAsResolutionBands() {
        let availability = MediaFormatAvailability(
            isKnown: true,
            formats: [
                MediaFormat(id: "244", ext: "webm", height: 468, vcodec: "vp9", acodec: "none"),
                MediaFormat(id: "140", ext: "m4a", height: nil, vcodec: "none", acodec: "mp4a.40.2"),
                MediaFormat(id: "251", ext: "webm", height: nil, vcodec: "none", acodec: "opus")
            ]
        )

        XCTAssertTrue(availability.isResolutionAvailable(.q480))
        XCTAssertFalse(availability.isResolutionAvailable(.q720))
        XCTAssertTrue(availability.isContainerAvailable(.webm, for: .q480))
        XCTAssertFalse(availability.isContainerAvailable(.mp4, for: .q480))
        XCTAssertEqual(availability.maxVideoHeight, 468)
    }

    func testUnknownPlaylistFormatsKeepOptionsAvailable() {
        XCTAssertTrue(MediaFormatAvailability.unknown.isResolutionAvailable(.q2160))
        XCTAssertTrue(MediaFormatAvailability.unknown.isContainerAvailable(.mp4, for: .q2160))
        XCTAssertTrue(MediaFormatAvailability.unknown.isContainerAvailable(.webm, for: .q2160))
    }

    func testEstimatesSelectedVideoAndAudioSize() {
        let availability = MediaFormatAvailability(
            isKnown: true,
            formats: [
                MediaFormat(id: "137", ext: "mp4", height: 1080, vcodec: "avc1.640028", acodec: "none", filesize: 120_000_000),
                MediaFormat(id: "136", ext: "mp4", height: 720, vcodec: "avc1.4d401f", acodec: "none", filesize: 70_000_000),
                MediaFormat(id: "140", ext: "m4a", height: nil, vcodec: "none", acodec: "mp4a.40.2", filesize: 8_000_000),
                MediaFormat(id: "247", ext: "webm", height: 720, vcodec: "vp9", acodec: "none", filesizeApprox: 62_000_000),
                MediaFormat(id: "251", ext: "webm", height: nil, vcodec: "none", acodec: "opus", filesizeApprox: 7_000_000)
            ]
        )

        XCTAssertEqual(availability.estimatedDownloadSizeBytes(for: .q1080, container: .mp4), 128_000_000)
        XCTAssertEqual(availability.estimatedDownloadSizeBytes(for: .q720, container: .webm), 69_000_000)
    }

    func testEstimatesAudioOnlySizeFromBestAudio() {
        let availability = MediaFormatAvailability(
            isKnown: true,
            formats: [
                MediaFormat(id: "140", ext: "m4a", height: nil, vcodec: "none", acodec: "mp4a.40.2", filesize: 8_000_000),
                MediaFormat(id: "251", ext: "webm", height: nil, vcodec: "none", acodec: "opus", filesize: 10_000_000)
            ]
        )

        XCTAssertEqual(availability.estimatedDownloadSizeBytes(for: .audioM4A, container: .mp4), 10_000_000)
    }
}
