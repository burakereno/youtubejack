import Foundation
import Testing
@testable import YouTubeJackCore

struct ProcessStreamingTests {
    @Test func aUTF8CharacterSplitAcrossWritesPreservesTheWholeLine() async throws {
        var lines: [String] = []
        let result = try await ProcessRunner().run(executablePath: "/usr/bin/python3", arguments: [
            "-c", "import os,time; os.write(1,b'download-output:/tmp/\\xc4'); time.sleep(.1); os.write(1,b'\\xb0stanbul.mp4\\n')"
        ], onStdoutLine: { lines.append($0) })
        #expect(lines == ["download-output:/tmp/İstanbul.mp4"])
        #expect(result.stdout == "download-output:/tmp/İstanbul.mp4\n")
    }
}
