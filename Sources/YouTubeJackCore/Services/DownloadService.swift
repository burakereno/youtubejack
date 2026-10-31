import CryptoKit
import Foundation

public final class DownloadService {
    private let dependencyResolver: DependencyResolver
    private let processRunner: ProcessRunner
    private let control = DownloadCancellationControl()

    public init(
        dependencyResolver: DependencyResolver = DependencyResolver(),
        processRunner: ProcessRunner = ProcessRunner()
    ) {
        self.dependencyResolver = dependencyResolver
        self.processRunner = processRunner
    }

    public func cancelCurrentDownload() {
        control.cancel()
    }

    public func download(
        item: DownloadItem,
        outputDirectory: String,
        onProgress: @escaping (DownloadProgress) -> Void,
        onOutputPath: @escaping (String) -> Void,
        onContainerChanged: @escaping (DownloadContainer) -> Void = { _ in },
        onSelectedMediaFormat: @escaping (SelectedMediaFormat?) -> Void = { _ in },
        onSubtitleMessage: @escaping (String?) -> Void = { _ in },
        onArtifactPath: @escaping (String) -> Void = { _ in }
    ) async throws -> String? {
        try Task.checkCancellation()
        control.begin()
        let ytdlp = try dependencyResolver.requireYTDLP()
        try ensureDirectoryExists(outputDirectory)
        let workspace = DownloadWorkspace(outputDirectory: outputDirectory, itemID: item.id)
        try workspace.prepare()

        var lastOutputPath: String?
        var firstForbiddenError: Error?
        var unavailableAudioError: Error?

        for attempt in attempts(for: item) {
            try checkCancellation()
            let arguments = arguments(
                for: item,
                attempt: attempt,
                outputDirectory: outputDirectory
            )

            do {
                onSelectedMediaFormat(nil)
                if attempt.container != item.container {
                    onContainerChanged(attempt.container)
                }

                _ = try await processRunner.run(
                    executablePath: ytdlp,
                    arguments: arguments,
                    onStdoutLine: { line in
                        if let format = ProgressParser.selectedMediaFormat(line) {
                            onSelectedMediaFormat(format)
                        }
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
                        self?.control.setProcess(process)
                    },
                    timeout: 21_600,
                    maxCollectedOutputBytes: 16_384,
                    collectOutput: false
                )
                control.setProcess(nil)
                try checkCancellation()
                if item.quality.isVideoQuality, item.subtitles.isEnabled, item.subtitles.languageCodes.isEmpty == false {
                    if let path = lastOutputPath {
                        var actualItem = item
                        actualItem.container = attempt.container
                        do {
                            let result = try await SubtitleService(dependencyResolver: dependencyResolver).download(
                                item: actualItem, videoPath: path, onMessage: onSubtitleMessage,
                                run: { executable, arguments in
                                    try self.checkCancellation()
                                    defer { self.control.setProcess(nil) }
                                    let result = try await self.processRunner.run(
                                        executablePath: executable, arguments: arguments,
                                        onProcessStarted: { process in
                                            self.control.setProcess(process)
                                        },
                                        timeout: 600, maxCollectedOutputBytes: arguments.contains("--dump-single-json") ? nil : 16_384
                                    )
                                    try self.checkCancellation()
                                    return result
                                }
                            )
                            result.outputPaths.forEach(onArtifactPath)
                            onSubtitleMessage(result.message)
                        } catch {
                            try checkCancellation()
                            onSubtitleMessage("Altyazı eklenemedi; video indirildi. \(error.localizedDescription)")
                        }
                    } else {
                        onSubtitleMessage("Altyazı eklenemedi: video dosyasının yolu bulunamadı.")
                    }
                }
                DownloadArtifactCleaner().removeWorkspace(at: workspace.directory.path, itemID: item.id)
                return lastOutputPath
            } catch {
                control.setProcess(nil)
                try checkCancellation()

                if isForbidden(error) {
                    firstForbiddenError = firstForbiddenError ?? error
                    continue
                }

                if item.audioLanguage.languageCode != nil,
                   error.localizedDescription.localizedCaseInsensitiveContains("requested format is not available") {
                    unavailableAudioError = AppError.processFailed(
                        "\(item.audioLanguage.title) ses bu videoda seçilen kalite ve formatta bulunamadı. Farklı bir kalite, format veya ses dili seçin."
                    )
                    continue
                }

                if item.videoCodecPreference != .automatic,
                   error.localizedDescription.localizedCaseInsensitiveContains("requested format is not available") {
                    throw AppError.processFailed(
                        "\(item.videoCodecPreference.title) bu videoda seçilen çözünürlük ve formatta bulunamadı."
                    )
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

        if let unavailableAudioError { throw unavailableAudioError }

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

        guard item.videoCodecPreference != .h264 else {
            return [
                DownloadAttempt(container: .mp4, usesChunking: false),
                DownloadAttempt(container: .mp4, usesChunking: true)
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
            "--ignore-config",
            "--no-write-subs", "--no-write-auto-subs", "--no-embed-subs",
            "--newline",
            "--no-warnings",
            "--no-cache-dir",
            "--no-playlist",
            "--paths", "home:\(outputDirectory)",
            "--paths", "temp:\(DownloadWorkspace(outputDirectory: outputDirectory, itemID: item.id).directory.path)",
            "--print", "after_move:download-output:%(filepath)s",
            "--no-simulate", "--no-quiet", "--progress",
            "--retries", "3",
            "--fragment-retries", "3",
            "--retry-sleep", "http:linear=1::1",
            "--retry-sleep", "fragment:linear=1::1",
            "--progress-template",
            "download:download-progress:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s"
        ]
        arguments.append(contentsOf: dependencyResolver.javaScriptRuntimeArguments())

        if attempt.usesChunking {
            arguments.append(contentsOf: ["--http-chunk-size", "10M"])
        }

        if item.quality.isAudioOnly {
            arguments.append(contentsOf: [
                "-f", item.quality.audioSelector(language: item.audioLanguage),
                "-x",
                "--audio-format", "m4a",
                "--audio-quality", "0"
            ])
        } else {
            arguments.append(contentsOf: [
                "-f", item.quality.formatSelector(container: attempt.container, codec: item.videoCodecPreference, audioLanguage: item.audioLanguage),
                "--merge-output-format", attempt.container.rawValue,
                "--remux-video", attempt.container.rawValue,
                "--print", "before_dl:download-codecs:%(height)s|%(vcodec)s|%(acodec)s|%(requested_formats.-1.language,language|NA)s"
            ])
        }

        if let ffmpegPath = dependencyResolver.ffmpegPath() {
            arguments.append(contentsOf: ["--ffmpeg-location", ffmpegPath])
        }

        arguments.append(contentsOf: ["-o", Self.outputTemplate(for: item)])
        arguments.append(item.url)
        return arguments
    }

    private func isForbidden(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("403") || message.contains("forbidden")
    }

    private func checkCancellation() throws {
        try Task.checkCancellation()
        if control.isCancelled { throw CancellationError() }
    }

    private func ensureDirectoryExists(_ path: String) throws {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            throw AppError.outputDirectoryUnavailable(path)
        }
    }

    static func outputTemplate(for item: DownloadItem) -> String {
        let prefix: String
        if let playlistIndex = item.playlistIndex {
            prefix = String(format: "%03d - ", playlistIndex)
        } else {
            prefix = ""
        }
        let languageSuffix = item.audioLanguage.isOriginal ? "" : item.audioLanguage.languageCode.map { " [\($0)]" } ?? ""
        let subtitles = item.subtitles.isEnabled ? item.subtitles : SubtitleOptions()
        let configuration = [item.quality.rawValue, item.container.rawValue, item.videoCodecPreference.rawValue,
                             item.audioLanguage.languageCode ?? "original", String(item.audioLanguage.isOriginal),
                             String(subtitles.isEnabled), subtitles.languageCodes.sorted().joined(separator: ","),
                             String(subtitles.includesAutomatic), subtitles.delivery.rawValue, subtitles.format.rawValue]
            .joined(separator: "|")
        let fingerprint = SHA256.hash(data: Data(configuration.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        return "\(prefix)%(title).120B [%(id)s] [\(item.quality.rawValue)-\(fingerprint)]\(languageSuffix).%(ext)s"
    }
}

private struct DownloadAttempt {
    let container: DownloadContainer
    let usesChunking: Bool
}

/// Process callbacks and the UI cancel from different executors. All mutable state is lock-protected.
private final class DownloadCancellationControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }

    func begin() {
        lock.withLock { cancelled = false; process = nil }
    }

    func setProcess(_ process: Process?) {
        let shouldTerminate = lock.withLock {
            self.process = process
            return cancelled
        }
        if shouldTerminate, process?.isRunning == true { process?.terminate() }
    }

    func cancel() {
        let process = lock.withLock { cancelled = true; return self.process }
        if process?.isRunning == true { process?.terminate() }
    }
}
