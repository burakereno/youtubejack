import Foundation

public enum MediaKind: String, Codable, Sendable {
    case video
    case playlist
}

public struct MediaInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let sourceURL: String
    public let webpageURL: String
    public let title: String
    public let creator: String
    public let duration: Double?
    public let thumbnailURL: URL?
    public let kind: MediaKind
    public let entryCount: Int
    public let formatAvailability: MediaFormatAvailability

    public init(
        id: String,
        sourceURL: String,
        webpageURL: String,
        title: String,
        creator: String,
        duration: Double?,
        thumbnailURL: URL?,
        kind: MediaKind,
        entryCount: Int,
        formatAvailability: MediaFormatAvailability = .unknown
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.webpageURL = webpageURL
        self.title = title
        self.creator = creator
        self.duration = duration
        self.thumbnailURL = thumbnailURL
        self.kind = kind
        self.entryCount = entryCount
        self.formatAvailability = formatAvailability
    }
}

public struct PlaylistEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let url: String
    public let title: String
    public let creator: String
    public let duration: Double?
    public let thumbnailURL: URL?
    public let index: Int
    public var isSelected: Bool

    public init(
        id: String,
        url: String,
        title: String,
        creator: String,
        duration: Double?,
        thumbnailURL: URL?,
        index: Int,
        isSelected: Bool = true
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.creator = creator
        self.duration = duration
        self.thumbnailURL = thumbnailURL
        self.index = index
        self.isSelected = isSelected
    }
}

public struct MetadataResult: Sendable {
    public let media: MediaInfo
    public let entries: [PlaylistEntry]

    public init(media: MediaInfo, entries: [PlaylistEntry]) {
        self.media = media
        self.entries = entries
    }
}
