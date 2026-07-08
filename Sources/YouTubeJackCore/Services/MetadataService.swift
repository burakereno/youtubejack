import Foundation

public final class MetadataService: Sendable {
    private let dependencyResolver: DependencyResolver
    private let processRunner: ProcessRunner
    private let parser: YouTubeURLParser
    private let session: URLSession

    public init(
        dependencyResolver: DependencyResolver = DependencyResolver(),
        processRunner: ProcessRunner = ProcessRunner(),
        parser: YouTubeURLParser = YouTubeURLParser(),
        session: URLSession = .shared
    ) {
        self.dependencyResolver = dependencyResolver
        self.processRunner = processRunner
        self.parser = parser
        self.session = session
    }

    public func fetchPreview(url rawURL: String) async throws -> MetadataResult {
        guard let parsed = parser.parse(rawURL) else {
            throw AppError.invalidYouTubeURL
        }

        if parsed.isPlaylist {
            return try await fetch(url: rawURL)
        }

        do {
            return try await fetchOEmbedPreview(parsed: parsed)
        } catch {
            return try await fetch(url: rawURL)
        }
    }

    public func fetch(url rawURL: String) async throws -> MetadataResult {
        guard let parsed = parser.parse(rawURL) else {
            throw AppError.invalidYouTubeURL
        }

        let ytdlp = try dependencyResolver.requireYTDLP()
        var arguments = [
            "--dump-single-json",
            "--skip-download",
            "--no-warnings",
            "--no-cache-dir"
        ]

        if parsed.isPlaylist {
            arguments.append("--flat-playlist")
        } else {
            arguments.append("--no-playlist")
        }
        arguments.append(parsed.normalizedURL)

        let result = try await processRunner.run(executablePath: ytdlp, arguments: arguments)
        guard let data = result.stdout.data(using: .utf8) else {
            throw AppError.metadataDecodeFailed
        }

        let decoded = try JSONDecoder().decode(YTDLPInfo.self, from: data)
        return map(decoded, sourceURL: parsed.normalizedURL, isPlaylist: parsed.isPlaylist)
    }

    private func map(_ info: YTDLPInfo, sourceURL: String, isPlaylist: Bool) -> MetadataResult {
        let entries = (info.entries ?? []).enumerated().compactMap { offset, entry -> PlaylistEntry? in
            guard let entryURL = resolvedEntryURL(entry) else { return nil }
            let entryID = entry.id ?? "\(offset + 1)-\(entryURL)"
            return PlaylistEntry(
                id: entryID,
                url: entryURL,
                title: entry.title ?? "Video \(offset + 1)",
                creator: entry.uploader ?? entry.channel ?? "",
                duration: entry.duration,
                thumbnailURL: entry.thumbnail.flatMap(URL.init(string:)),
                index: offset + 1
            )
        }

        let kind: MediaKind = isPlaylist || entries.isEmpty == false ? .playlist : .video
        let webpageURL = [info.webpageURL, info.originalURL, sourceURL]
            .compactMap { candidate -> String? in
                guard let candidate else { return nil }
                return parser.parse(candidate)?.normalizedURL
            }
            .first ?? sourceURL
        let media = MediaInfo(
            id: info.id ?? sourceURL,
            sourceURL: sourceURL,
            webpageURL: webpageURL,
            title: info.title ?? (kind == .playlist ? "Playlist" : "Video"),
            creator: info.uploader ?? info.channel ?? "",
            duration: info.duration,
            thumbnailURL: info.thumbnail.flatMap(URL.init(string:)),
            kind: kind,
            entryCount: kind == .playlist ? entries.count : 1,
            formatAvailability: mapFormats(info.formats, isPlaylist: kind == .playlist)
        )
        return MetadataResult(media: media, entries: entries)
    }

    private func fetchOEmbedPreview(parsed: ParsedYouTubeURL) async throws -> MetadataResult {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "url", value: parsed.normalizedURL)
        ]

        guard let url = components.url else {
            throw AppError.invalidYouTubeURL
        }

        let (data, _) = try await session.data(from: url)
        let decoded = try JSONDecoder().decode(YouTubeOEmbedPreview.self, from: data)
        let media = MediaInfo(
            id: parsed.videoID ?? parsed.normalizedURL,
            sourceURL: parsed.normalizedURL,
            webpageURL: parsed.normalizedURL,
            title: decoded.title,
            creator: decoded.authorName,
            duration: nil,
            thumbnailURL: URL(string: decoded.thumbnailURL),
            kind: .video,
            entryCount: 1,
            formatAvailability: .unknown
        )
        return MetadataResult(media: media, entries: [])
    }

    private func mapFormats(_ formats: [YTDLPFormat]?, isPlaylist: Bool) -> MediaFormatAvailability {
        guard isPlaylist == false, let formats else {
            return .unknown
        }

        return MediaFormatAvailability(
            isKnown: true,
            formats: formats.enumerated().map { offset, format in
	                MediaFormat(
	                    id: format.formatID ?? "\(offset)",
	                    ext: format.ext,
	                    height: format.height,
	                    vcodec: format.vcodec,
	                    acodec: format.acodec,
	                    filesize: format.filesize,
	                    filesizeApprox: format.filesizeApprox
	                )
	            }
	        )
    }

    private func resolvedEntryURL(_ entry: YTDLPEntry) -> String? {
        for candidate in [entry.webpageURL, entry.url].compactMap({ $0 }) {
            if let parsed = parser.parse(candidate) {
                return parsed.normalizedURL
            }
        }
        if let id = entry.id, id.isEmpty == false {
            return parser.parse("https://www.youtube.com/watch?v=\(id)")?.normalizedURL
        }
        if let url = entry.url, url.isEmpty == false {
            return parser.parse("https://www.youtube.com/watch?v=\(url)")?.normalizedURL
        }
        return nil
    }
}

private struct YouTubeOEmbedPreview: Decodable {
    let title: String
    let authorName: String
    let thumbnailURL: String

    enum CodingKeys: String, CodingKey {
        case title
        case authorName = "author_name"
        case thumbnailURL = "thumbnail_url"
    }
}
