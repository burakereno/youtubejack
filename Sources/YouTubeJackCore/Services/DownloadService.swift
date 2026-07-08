import Foundation

public final class DownloadService {
    private let dependencyResolver: DependencyResolver
    private let processRunner: ProcessRunner
    private var activeProcess: Process?

    public init(
        dependencyResolver: DependencyResolver = DependencyResolver(),
        processRunner: ProcessRunner = ProcessRunner()
    ) {
        self.dependencyResolver = dependencyResolver
        self.processRunner = processRunner
    }

    public func cancelCurrentDownload() {
        activeProcess?.terminate()
    }

    public func download(
        item: DownloadItem,
        outputDirectory: String,
        onProgress: @escaping (DownloadProgress) -> Void,
        onOutputPath: @escaping (String) -> Void,
        onContainerChanged: @escaping (DownloadContainer) -> Void = { _ in }
    ) async throws -> String? {
        let ytdlp = try dependencyResolver.requireYTDLP()
        try ensureDirectoryExists(outputDirectory)

        var lastOutputPath: String?
        var firstForbiddenError: Error?

        for attempt in attempts(for: item) {
            let arguments = arguments(
                for: item,
                attempt: attempt,
                outputDirectory: outputDirectory
            )

            do {
                if attempt.container != item.container {
                    onContainerChanged(attempt.container)
                }

                _ = try await processRunner.run(
                    executablePath: ytdlp,
                    arguments: arguments,
                    onStdoutLine: { line in
                        if let progress = ProgressParser.parse(line) {
                            onProgress(progress)
                        }
                        if let destination = ProgressParser.destinationPath(line) {
                            lastOutputPath = destination
                            onOutputPath(destination)
                        }
                    },
                    onStderrLine: { _ in },
                    onProcessStarted: { [weak self] process in
                        self?.activeProcess = process
                    },
                    timeout: 21_600,
                    maxCollectedOutputBytes: 16_384,
                    collectOutput: false
                )
                activeProcess = nil
                return lastOutputPath
            } catch {
                activeProcess = nil

                if isForbidden(error) {
                    firstForbiddenError = firstForbiddenError ?? error
                    continue
                }

                if firstForbiddenError == nil {
                    throw AppError.processFailed(error.localizedDescription)
                }
            }
        }

        if let firstForbiddenError {
            throw AppError.processFailed(
                "YouTube bu medya akışını reddetti (403). Alternatif formatlar denendi. Son hata: \(firstForbiddenError.localizedDescription)"
            )
        }

        throw AppError.processFailed(
            "YouTube bu medya akışını reddetti (403). Alternatif formatlar denendi. yt-dlp güncellemesi veya farklı format gerekebilir."
        )
    }

    private func attempts(for item: DownloadItem) -> [DownloadAttempt] {
        guard item.quality.isVideoQuality else {
            return [
                DownloadAttempt(container: item.container, usesChunking: false),
                DownloadAttempt(container: item.container, usesChunking: true)
            ]
        }

        let alternate: DownloadContainer = item.container == .mp4 ? .webm : .mp4
        return [
            DownloadAttempt(container: item.container, usesChunking: false),
            DownloadAttempt(container: item.container, usesChunking: true),
            DownloadAttempt(container: alternate, usesChunking: false),
            DownloadAttempt(container: alternate, usesChunking: true)
        ]
    }

    private func arguments(
        for item: DownloadItem,
        attempt: DownloadAttempt,
        outputDirectory: String
    ) -> [String] {
        var arguments = [
            "--newline",
            "--no-warnings",
            "--no-cache-dir",
            "--no-playlist",
            "--retries", "3",
            "--fragment-retries", "3",
            "--retry-sleep", "http:linear=1::1",
            "--retry-sleep", "fragment:linear=1::1",
            "--progress-template",
            "download:download-progress:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s"
        ]

        if attempt.usesChunking {
            arguments.append(contentsOf: ["--http-chunk-size", "10M"])
        }

        if item.quality.isAudioOnly {
            arguments.append(contentsOf: [
                "-f", item.quality.audioSelector,
                "-x",
                "--audio-format", "m4a",
                "--audio-quality", "0"
            ])
        } else {
            arguments.append(contentsOf: [
                "-f", item.quality.formatSelector(container: attempt.container),
                "--merge-output-format", attempt.container.rawValue,
                "--remux-video", attempt.container.rawValue
            ])
        }

        if let ffmpegPath = dependencyResolver.ffmpegPath() {
            arguments.append(contentsOf: ["--ffmpeg-location", ffmpegPath])
        }

        arguments.append(contentsOf: ["-o", outputTemplate(for: item, outputDirectory: outputDirectory)])
        arguments.append(item.url)
        return arguments
    }

    private func isForbidden(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("403") || message.contains("forbidden")
    }

    private func ensureDirectoryExists(_ path: String) throws {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            throw AppError.outputDirectoryUnavailable(path)
        }
    }

    private func outputTemplate(for item: DownloadItem, outputDirectory: String) -> String {
        let prefix: String
        if let playlistIndex = item.playlistIndex {
            prefix = String(format: "%03d - ", playlistIndex)
        } else {
            prefix = ""
        }
        return URL(fileURLWithPath: outputDirectory)
            .appendingPathComponent("\(prefix)%(title).200B.%(ext)s")
            .path
    }
}

private struct DownloadAttempt {
    let container: DownloadContainer
    let usesChunking: Bool
}
