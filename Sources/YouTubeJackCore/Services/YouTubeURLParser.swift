import Foundation

public struct ParsedYouTubeURL: Equatable, Sendable {
    public let original: String
    public let normalizedURL: String
    public let videoID: String?
    public let playlistID: String?
    public let isPlaylist: Bool
}

public struct YouTubeURLParser: Sendable {
    public init() {}

    public func parse(_ rawValue: String) -> ParsedYouTubeURL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let urlString: String
        if trimmed.contains("://") {
            urlString = trimmed
        } else if trimmed.hasPrefix("youtube.com") || trimmed.hasPrefix("www.youtube.com") || trimmed.hasPrefix("youtu.be") {
            urlString = "https://\(trimmed)"
        } else {
            urlString = trimmed
        }

        guard
            var components = URLComponents(string: urlString),
            let host = components.host?.lowercased()
        else {
            return nil
        }

        if let scheme = components.scheme?.lowercased() {
            guard scheme == "http" || scheme == "https" else { return nil }
        }

        let acceptedHosts = [
            "youtube.com",
            "www.youtube.com",
            "m.youtube.com",
            "music.youtube.com",
            "youtu.be"
        ]
        guard acceptedHosts.contains(host) else { return nil }

        let queryItems = components.queryItems ?? []
        let videoID = queryItems.first(where: { $0.name == "v" })?.value ?? videoIDFromPath(components.path, host: host)
        let playlistID = queryItems.first(where: { $0.name == "list" })?.value
        let pathSuggestsPlaylist = components.path == "/playlist"
        let isPlaylist = playlistID != nil || pathSuggestsPlaylist

        guard videoID != nil || playlistID != nil else { return nil }

        components.scheme = "https"
        components.host = host
        guard let normalizedURL = components.string else { return nil }

        return ParsedYouTubeURL(
            original: rawValue,
            normalizedURL: normalizedURL,
            videoID: videoID,
            playlistID: playlistID,
            isPlaylist: isPlaylist
        )
    }

    private func videoIDFromPath(_ path: String, host: String) -> String? {
        let components = path.split(separator: "/").map(String.init)
        if host == "youtu.be" {
            return components.first
        }
        if components.count >= 2, ["shorts", "embed", "live"].contains(components[0]) {
            return components[1]
        }
        return nil
    }
}
