import Foundation

public enum DownloadState: String, Codable, Sendable {
    case pending
    case running
    case completed
    case failed
    case cancelled

    public var title: String {
        switch self {
        case .pending:
            return "Bekliyor"
        case .running:
            return "İndiriliyor"
        case .completed:
            return "Tamamlandı"
        case .failed:
            return "Hata"
        case .cancelled:
            return "İptal"
        }
    }
}

public struct DownloadItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: String
    public let title: String
    public let quality: QualityProfile
    public var container: DownloadContainer
    public let thumbnailURL: URL?
    public let estimatedSizeBytes: Int64?
    public let playlistIndex: Int?
    public var status: DownloadState
    public var progress: Double
    public var speed: String
    public var eta: String
    public var outputPath: String?
    public var outputPaths: [String]
    public var fileSizeBytes: Int64?
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        url: String,
        title: String,
        quality: QualityProfile,
        container: DownloadContainer,
        thumbnailURL: URL? = nil,
        estimatedSizeBytes: Int64? = nil,
        playlistIndex: Int? = nil,
        status: DownloadState = .pending,
        progress: Double = 0,
        speed: String = "",
        eta: String = "",
        outputPath: String? = nil,
        outputPaths: [String] = [],
        fileSizeBytes: Int64? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.quality = quality
        self.container = container
        self.thumbnailURL = thumbnailURL
        self.estimatedSizeBytes = estimatedSizeBytes
        self.playlistIndex = playlistIndex
        self.status = status
        self.progress = progress
        self.speed = speed
        self.eta = eta
        self.outputPath = outputPath
        self.outputPaths = outputPaths
        self.fileSizeBytes = fileSizeBytes
        self.errorMessage = errorMessage
    }
}
