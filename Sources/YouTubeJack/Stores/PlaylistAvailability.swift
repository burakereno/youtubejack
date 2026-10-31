import Foundation
import YouTubeJackCore

/// Availability belongs to each video: streams from different entries must never be combined.
struct PlaylistAvailability {
    let entries: [PlaylistEntry]
    let metadataByURL: [String: MediaInfo]
    let failedURLs: Set<String>

    var selectedEntries: [PlaylistEntry] { entries.filter(\.isSelected) }
    var selectedMedia: [MediaInfo] { selectedEntries.compactMap { metadataByURL[$0.url] } }
    var checkedCount: Int { selectedMedia.count }
    var failedCount: Int { selectedEntries.filter { failedURLs.contains($0.url) }.count }
    var pendingCount: Int { selectedEntries.count - checkedCount - failedCount }
    var isComplete: Bool { selectedEntries.isEmpty == false && pendingCount == 0 && failedCount == 0 }

    func supports(_ predicate: (MediaFormatAvailability) -> Bool) -> Bool {
        selectedMedia.contains { predicate($0.formatAvailability) } || pendingCount > 0 || failedCount > 0
    }

    var audioLanguages: [AudioLanguage] {
        let alternatives = selectedMedia.flatMap { $0.formatAvailability.audioLanguages.filter { $0.isOriginal == false } }
        let groups = Dictionary(grouping: alternatives, by: \.code)
        return groups.map { code, languages in
            AudioLanguage(code: code, isOriginal: false, isAutomatic: languages.allSatisfy(\.isAutomatic))
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var subtitleAvailability: SubtitleAvailability {
        let groups = Dictionary(grouping: selectedMedia.flatMap { $0.subtitleAvailability.languages }, by: \.code)
        return SubtitleAvailability(isKnown: isComplete, languages: groups.map { code, languages in
            SubtitleLanguage(code: code, hasManual: languages.contains(where: \.hasManual), hasAutomatic: languages.contains(where: \.hasAutomatic))
        })
    }
}
