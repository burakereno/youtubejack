import XCTest
@testable import YouTubeJackCore

final class ProcessRunnerTests: XCTestCase {
    func testStreamingFailurePreservesRecentStderr() async throws {
        do {
            _ = try await ProcessRunner().run(
                executablePath: "/bin/sh",
                arguments: ["-c", "printf '%2048s' warning >&2; printf '\\nERROR: HTTP Error 403: Forbidden\\n' >&2; exit 1"],
                timeout: 5,
                maxCollectedOutputBytes: 128,
                collectOutput: false
            )
            XCTFail("Expected process failure")
        } catch let error as ProcessExecutionError {
            XCTAssertEqual(error.exitCode, 1)
            XCTAssertTrue(error.localizedDescription.contains("HTTP Error 403: Forbidden"))
            XCTAssertLessThanOrEqual(error.stderr.utf8.count, 128)
        }
    }

    func testSuccessfulStreamingDoesNotReturnCollectedOutput() async throws {
        let result = try await ProcessRunner().run(
            executablePath: "/bin/sh",
            arguments: ["-c", "printf progress; printf warning >&2"],
            timeout: 5,
            collectOutput: false
        )
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(result.stderr, "")
    }

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
