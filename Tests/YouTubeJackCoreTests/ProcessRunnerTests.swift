import XCTest
@testable import YouTubeJackCore

final class ProcessRunnerTests: XCTestCase {
    func testCollectedOutputIsCapped() async throws {
        let result = try await ProcessRunner().run(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf '%2048s' a"],
            timeout: 5,
            maxCollectedOutputBytes: 128
        )

        XCTAssertLessThanOrEqual(result.stdout.utf8.count, 128)
    }

    func testTimeoutTerminatesLongRunningProcess() async {
        let startedAt = Date()
        do {
            _ = try await ProcessRunner().run(
                executablePath: "/bin/sleep",
                arguments: ["2"],
                timeout: 0.1
            )
            XCTFail("Expected timeout")
        } catch is ProcessTimeoutError {
            XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
        } catch {
            XCTFail("Expected ProcessTimeoutError, got \(error)")
        }
    }
}
