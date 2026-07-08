import Foundation

public enum AppError: LocalizedError, Equatable, Sendable {
    case invalidYouTubeURL
    case missingDependency(String)
    case metadataDecodeFailed
    case noMediaLoaded
    case noPlaylistSelection
    case outputDirectoryUnavailable(String)
    case processFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidYouTubeURL:
            return "Geçerli bir YouTube video veya playlist linki değil."
        case .missingDependency(let name):
            return "\(name) uygulama içinde bulunamadı. Uygulamayı yeniden kur veya Araçlar bölümünden yt-dlp'yi güncelle."
        case .metadataDecodeFailed:
            return "Video bilgisi okunamadı."
        case .noMediaLoaded:
            return "Önce bir video veya playlist algılanmalı."
        case .noPlaylistSelection:
            return "Playlist içinde seçili video yok."
        case .outputDirectoryUnavailable(let path):
            return "İndirme klasörü hazırlanamadı: \(path)"
        case .processFailed(let message):
            return message
        }
    }
}
