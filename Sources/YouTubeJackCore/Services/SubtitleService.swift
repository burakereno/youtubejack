import Foundation

struct SubtitleResult {
    let message: String
    let outputPaths: [String]
}

/// Caption failures are handled separately by DownloadService so completed media survives.
struct SubtitleService {
    let dependencyResolver: DependencyResolver

    func download(
        item: DownloadItem,
        videoPath: String,
        onMessage: (String?) -> Void,
        run: (String, [String]) async throws -> ProcessResult
    ) async throws -> SubtitleResult {
        let options = item.subtitles
        let videoURL = URL(fileURLWithPath: videoPath)
        let temporaryDirectory = videoURL.deletingLastPathComponent()
            .appendingPathComponent(".youtubejack-subtitles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        onMessage(L10n.string("Checking subtitles…"))
        var metadataArguments = ["--ignore-config", "--no-playlist", "--no-cache-dir", "--skip-download", "--dump-single-json", "--no-warnings", "--socket-timeout", "20", "--retries", "2"]
        metadataArguments.append(contentsOf: dependencyResolver.javaScriptRuntimeArguments())
        metadataArguments.append(item.url)
        let metadata = try await run(dependencyResolver.requireYTDLP(), metadataArguments)
        let info = try JSONDecoder().decode(YTDLPInfo.self, from: Data(metadata.stdout.utf8))
        let tracks = info.selectedSubtitles(for: options)
        guard tracks.isEmpty == false else {
            return SubtitleResult(message: L10n.string("Missing subtitles: %@. The video was downloaded without subtitles.", defaultValue: "Missing subtitles: \(options.summary). The video was downloaded without subtitles."), outputPaths: [])
        }

        guard let ffmpeg = dependencyResolver.ffmpegPath() else {
            throw AppError.missingDependency("ffmpeg")
        }
        let format = options.delivery == .embedded ? (item.container == .webm ? SubtitleFormat.vtt : .srt) : options.format
        var arguments = [
            "--ignore-config", "--no-playlist", "--no-cache-dir", "--skip-download",
            "--no-simulate", "--write-subs",
            options.includesAutomatic ? "--write-auto-subs" : "--no-write-auto-subs",
            "--no-embed-subs", "--sub-langs", tracks.map { NSRegularExpression.escapedPattern(for: $0.trackCode) }.joined(separator: ","),
            "--sub-format", "vtt/srt/best", "--convert-subs", format.rawValue,
            "--retries", "2", "--socket-timeout", "20",
            "--ffmpeg-location", ffmpeg,
            "-o", temporaryDirectory.appendingPathComponent("subtitle.%(ext)s").path
        ]
        arguments.append(contentsOf: dependencyResolver.javaScriptRuntimeArguments())
        arguments.append(item.url)
        onMessage(L10n.string("Downloading subtitles…"))
        var downloadWarning: String?
        do {
            _ = try await run(dependencyResolver.requireYTDLP(), arguments)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Keep other successfully fetched languages when one caption request fails.
            downloadWarning = L10n.string("Some subtitles could not be downloaded: %@", defaultValue: "Some subtitles could not be downloaded: \(error.localizedDescription)")
        }

        let files = try FileManager.default.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil)
        let captions: [(code: String, url: URL, isAutomatic: Bool)] = tracks.compactMap { track in
            let name = "subtitle.\(track.trackCode).\(format.rawValue)"
            guard let url = files.first(where: { $0.lastPathComponent == name }) else { return nil }
            return (track.code, url, track.isAutomatic)
        }
        let missing = options.languageCodes.filter { code in captions.contains(where: { $0.code == code }) == false }
        let missingMessage = missing.isEmpty ? nil : L10n.string("Missing subtitles: %@.", defaultValue: "Missing subtitles: \(missing.map { SubtitleLanguage.localizedName(for: $0) }.joined(separator: ", ")).")
        guard captions.isEmpty == false else {
            return SubtitleResult(message: [missingMessage ?? L10n.string("No subtitles found."), downloadWarning].compactMap { $0 }.joined(separator: " "), outputPaths: [])
        }

        var outputPaths: [String] = []
        var existingFiles: [String] = []
        if options.delivery == .separateFile {
            for caption in captions {
                let destination = videoURL.deletingPathExtension()
                    .appendingPathExtension(caption.code).appendingPathExtension(format.rawValue)
                if FileManager.default.fileExists(atPath: destination.path) {
                    existingFiles.append(caption.code)
                    continue
                }
                try FileManager.default.moveItem(at: caption.url, to: destination)
                outputPaths.append(destination.path)
            }
        } else {
            onMessage(L10n.string("Embedding subtitles…"))
            let embeddedVideo = temporaryDirectory.appendingPathComponent("embedded.\(item.container.rawValue)")
            var ffmpegArguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-y", "-i", videoPath]
            for caption in captions { ffmpegArguments.append(contentsOf: ["-i", caption.url.path]) }
            ffmpegArguments.append(contentsOf: ["-map", "0:v?", "-map", "0:a?"])
            for index in captions.indices { ffmpegArguments.append(contentsOf: ["-map", "\(index + 1):0"]) }
            ffmpegArguments.append(contentsOf: ["-map_metadata", "0", "-map_chapters", "0", "-c", "copy", "-c:s", item.container == .webm ? "webvtt" : "mov_text"])
            for (index, caption) in captions.enumerated() {
                let language = SubtitleLanguage(code: caption.code, hasManual: false, hasAutomatic: false)
                ffmpegArguments.append(contentsOf: [
                    "-metadata:s:s:\(index)", "language=\(language.metadataLanguage)",
                    "-metadata:s:s:\(index)", "title=\(language.name)\(caption.isAutomatic ? L10n.string(" (automatic)") : "")",
                    "-disposition:s:\(index)", "0"
                ])
            }
            if item.container == .mp4 { ffmpegArguments.append(contentsOf: ["-movflags", "+faststart"]) }
            ffmpegArguments.append(embeddedVideo.path)
            _ = try await run(ffmpeg, ffmpegArguments)
            // Replacement happens only after ffmpeg succeeds; the original survives errors/cancellation.
            _ = try FileManager.default.replaceItemAt(videoURL, withItemAt: embeddedVideo)
        }

        let languageSummary = captions.map { "\(SubtitleLanguage.localizedName(for: $0.code))\($0.isAutomatic ? L10n.string(" (automatic)") : "")" }.joined(separator: ", ")
        let success = options.delivery == .embedded
            ? L10n.string("Subtitles embedded: %@.", defaultValue: "Subtitles embedded: \(languageSummary).")
            : L10n.string("Subtitles saved (%@): %@.", defaultValue: "Subtitles saved (\(format.title)): \(languageSummary).")
        let existingMessage = existingFiles.isEmpty ? nil : L10n.string("Existing subtitle files were preserved: %@.", defaultValue: "Existing subtitle files were preserved: \(existingFiles.joined(separator: ", ")).")
        return SubtitleResult(message: [success, missingMessage, existingMessage, downloadWarning].compactMap { $0 }.joined(separator: " "), outputPaths: outputPaths)
    }
}
