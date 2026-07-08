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
            return "\(executable) \(exitCode) koduyla durdu."
        }
        return message
    }
}

public struct ProcessTimeoutError: LocalizedError, Sendable {
    public let executable: String
    public let timeout: TimeInterval

    public var errorDescription: String? {
        "\(executable) \(Int(timeout)) saniye içinde bitmedi."
    }
}

public final class ProcessRunner: Sendable {
    public init() {}

    public func run(
        executablePath: String,
        arguments: [String],
        onStdoutLine: ((String) -> Void)? = nil,
        onStderrLine: ((String) -> Void)? = nil,
        onProcessStarted: ((Process) -> Void)? = nil,
        timeout: TimeInterval? = 120,
        maxCollectedOutputBytes: Int = 1_048_576,
        collectOutput: Bool = true
    ) async throws -> ProcessResult {
        let runningProcess = RunningProcess()
        let process = runningProcess.process
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

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
            collectOutput: collectOutput
        )

        let didFinish = await withTaskCancellationHandler {
            await waitForTermination(runningProcess, timeout: timeout)
        } onCancel: {
            runningProcess.terminate()
        }

        if didFinish == false {
            runningProcess.terminate()
            try? await Task.sleep(nanoseconds: 150_000_000)
            runningProcess.forceTerminate()
            let stdoutValue = await stdout
            let stderrValue = await stderr
            _ = ProcessResult(exitCode: process.terminationStatus, stdout: stdoutValue, stderr: stderrValue)
            throw ProcessTimeoutError(executable: executablePath, timeout: timeout ?? 0)
        }

        try Task.checkCancellation()

        let stdoutValue = await stdout
        let stderrValue = await stderr
        let result = ProcessResult(exitCode: process.terminationStatus, stdout: stdoutValue, stderr: stderrValue)

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

    private func waitForTermination(_ runningProcess: RunningProcess, timeout: TimeInterval?) async -> Bool {
        await withCheckedContinuation { continuation in
            let box = ProcessWaitContinuation(continuation)
            runningProcess.process.terminationHandler = { _ in
                box.resume(true)
            }

            if let timeout {
                Task.detached(priority: .utility) {
                    let nanoseconds = UInt64(max(0, timeout) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: nanoseconds)
                    box.resume(false)
                }
            }

            if runningProcess.process.isRunning == false {
                box.resume(true)
            }
        }
    }

    private func readLines(
        from fileHandle: FileHandle,
        onLine: ((String) -> Void)?,
        maxCollectedOutputBytes: Int,
        collectOutput: Bool
    ) async -> String {
        await Task.detached(priority: .utility) {
            var collected = Data()
            var buffer = ""
            let maxLineBufferCharacters = 65_536

            while true {
                let data = fileHandle.availableData
                if data.isEmpty {
                    break
                }

                let chunk = String(data: data, encoding: .utf8) ?? ""
                if collectOutput, maxCollectedOutputBytes > 0, collected.count < maxCollectedOutputBytes {
                    let remaining = maxCollectedOutputBytes - collected.count
                    collected.append(contentsOf: data.prefix(remaining))
                }
                buffer += chunk

                while let newlineRange = buffer.range(of: "\n") {
                    let line = String(buffer[..<newlineRange.lowerBound])
                    onLine?(line.trimmingCharacters(in: .newlines))
                    buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
                }

                if buffer.count > maxLineBufferCharacters {
                    onLine?(buffer.trimmingCharacters(in: .newlines))
                    buffer.removeAll(keepingCapacity: true)
                }
            }

            if buffer.isEmpty == false {
                onLine?(buffer.trimmingCharacters(in: .newlines))
            }
            return String(data: collected, encoding: .utf8) ?? ""
        }.value
    }
}

private final class RunningProcess: @unchecked Sendable {
    let process = Process()

    func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }

    func forceTerminate() {
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
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
