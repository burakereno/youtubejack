import Darwin
import Foundation

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public struct ProcessExecutionError: LocalizedError, Sendable {
    public let executable: String
    public let arguments: [String]
    public let exitCode: Int32
    public let stderr: String

    public var errorDescription: String? {
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.isEmpty {
            return L10n.string("%@ exited with code %d.", defaultValue: "\(executable) exited with code \(exitCode).")
        }
        return message
    }
}

public struct ProcessTimeoutError: LocalizedError, Sendable {
    public let executable: String
    public let timeout: TimeInterval

    public var errorDescription: String? {
        L10n.string("%@ did not finish within %lld seconds.", defaultValue: "\(executable) did not finish within \(Int(timeout)) seconds.")
    }
}

public final class ProcessRunner: Sendable {
    public init() {}

    /// Pass `nil` for `maxCollectedOutputBytes` when complete output is required, such as JSON.
    public func run(
        executablePath: String,
        arguments: [String],
        onStdoutLine: ((String) -> Void)? = nil,
        onStderrLine: ((String) -> Void)? = nil,
        onProcessStarted: ((Process) -> Void)? = nil,
        timeout: TimeInterval? = 120,
        maxCollectedOutputBytes: Int? = 1_048_576,
        collectOutput: Bool = true
    ) async throws -> ProcessResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try Task.checkCancellation()
        try process.run()
        onProcessStarted?(process)

        async let stdout = readLines(
            from: stdoutPipe.fileHandleForReading,
            onLine: onStdoutLine,
            maxCollectedOutputBytes: maxCollectedOutputBytes,
            collectOutput: collectOutput
        )
        async let stderr = readLines(
            from: stderrPipe.fileHandleForReading,
            onLine: onStderrLine,
            maxCollectedOutputBytes: maxCollectedOutputBytes,
            collectOutput: true,
            keepRecentOutput: true
        )

        let didFinish = await withTaskCancellationHandler {
            await waitForTermination(process, timeout: timeout)
        } onCancel: {
            Self.stop(process)
        }

        if !didFinish {
            Self.stop(process)
            _ = await waitForTermination(process, timeout: nil)
            _ = await (stdout, stderr)
            try Task.checkCancellation()
            throw ProcessTimeoutError(executable: executablePath, timeout: timeout ?? 0)
        }

        try Task.checkCancellation()

        let stdoutValue = await stdout
        let stderrValue = await stderr
        let result = ProcessResult(
            exitCode: process.terminationStatus,
            stdout: stdoutValue,
            stderr: collectOutput ? stderrValue : ""
        )

        guard process.terminationStatus == 0 else {
            throw ProcessExecutionError(
                executable: executablePath,
                arguments: arguments,
                exitCode: process.terminationStatus,
                stderr: stderrValue
            )
        }
        return result
    }

    static func stop(_ process: Process) {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        let ownsGroup = getpgid(pid) == pid
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(300)) {
            // yt-dlp can leave an ffmpeg child holding the output pipes while it exits.
            if process.isRunning {
                kill(ownsGroup ? -pid : pid, SIGKILL)
            } else if ownsGroup, getpgid(pid) == -1 && errno == ESRCH {
                // A group with live children keeps its group ID reserved.
                kill(-pid, SIGKILL)
            }
        }
    }

    private func waitForTermination(_ process: Process, timeout: TimeInterval?) async -> Bool {
        await withCheckedContinuation { continuation in
            let box = ProcessWaitContinuation(continuation)
            process.terminationHandler = { _ in
                box.resume(true)
            }

            if let timeout {
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0, timeout)) { [weak box] in
                    box?.resume(false)
                }
            }

            if process.isRunning == false {
                box.resume(true)
            }
        }
    }

    private func readLines(
        from fileHandle: FileHandle,
        onLine: ((String) -> Void)?,
        maxCollectedOutputBytes: Int?,
        collectOutput: Bool,
        keepRecentOutput: Bool = false
    ) async -> String {
        // Blocking pipe reads must not occupy Swift's cooperative executor.
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var collected = Data()
                var buffer = Data()
                let maxLineBufferBytes = 262_144

                while true {
                    let data = fileHandle.availableData
                    if data.isEmpty {
                        break
                    }

                    if collectOutput, maxCollectedOutputBytes == nil {
                        collected.append(data)
                    } else if collectOutput, let maxCollectedOutputBytes, maxCollectedOutputBytes > 0 {
                        if keepRecentOutput {
                            // Failures usually appear at the end, after progress and warnings.
                            collected.append(contentsOf: data.suffix(maxCollectedOutputBytes))
                            if collected.count > maxCollectedOutputBytes {
                                collected.removeFirst(collected.count - maxCollectedOutputBytes)
                            }
                        } else if collected.count < maxCollectedOutputBytes {
                            let remaining = maxCollectedOutputBytes - collected.count
                            collected.append(contentsOf: data.prefix(remaining))
                        }
                    }
                    guard onLine != nil else { continue }
                    buffer.append(data)

                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let line = String(decoding: buffer[..<newline], as: UTF8.self)
                        onLine?(line.trimmingCharacters(in: .newlines))
                        buffer.removeSubrange(buffer.startIndex...newline)
                    }

                    if buffer.count > maxLineBufferBytes {
                        // Preserve up to three trailing bytes when a UTF-8 scalar is split across reads.
                        var completeBytes = buffer.count
                        for _ in 0..<3 {
                            if String(data: buffer.prefix(completeBytes), encoding: .utf8) != nil { break }
                            completeBytes -= 1
                        }
                        onLine?(String(decoding: buffer.prefix(completeBytes), as: UTF8.self).trimmingCharacters(in: .newlines))
                        buffer.removeFirst(completeBytes)
                    }
                }

                if buffer.isEmpty == false {
                    onLine?(String(decoding: buffer, as: UTF8.self).trimmingCharacters(in: .newlines))
                }
                continuation.resume(returning: String(decoding: collected, as: UTF8.self))
            }
        }
    }
}

private final class ProcessWaitContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(_ value: Bool) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(returning: value)
    }
}
