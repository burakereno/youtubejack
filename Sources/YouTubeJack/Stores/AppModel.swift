import AppKit
import Combine
import Foundation
import YouTubeJackCore

@MainActor
final class AppModel: ObservableObject {
    @Published var inputURL = ""
    @Published var media: MediaInfo?
    @Published var playlistEntries: [PlaylistEntry] = []
    @Published var selectedQuality: QualityProfile
    @Published var selectedContainer: DownloadContainer
    @Published var queue: [DownloadItem] = []
    @Published var isQueuePaused = true
    @Published var isQueueProcessing = false
    @Published var isAnalyzing = false
    @Published var isAnalyzingFormats = false
    @Published var statusMessage: String?
    @Published var dependencyStatus: DependencyStatus
    @Published var ytdlpInstalledVersion: String?
    @Published var ytdlpLatestVersion: String?
    @Published var ytdlpUpdateMessage: String?
    @Published var isUpdatingYTDLP = false

    private let parser = YouTubeURLParser()
    private let dependencyResolver: DependencyResolver
    private let metadataService: MetadataService
    private let downloadService: DownloadService
    private let ytdlpUpdateService: YTDLPUpdateService
    private let artifactCleaner = DownloadArtifactCleaner()
    private var analyzeTask: Task<Void, Never>?
    private var formatTask: Task<Void, Never>?
    private var queueTask: Task<Void, Never>?
    private var lastAnalyzedURL = ""
    private var cancelledItems = Set<UUID>()

    init() {
        let resolver = DependencyResolver()
        dependencyResolver = resolver
        metadataService = MetadataService(dependencyResolver: resolver)
        downloadService = DownloadService(dependencyResolver: resolver)
        ytdlpUpdateService = YTDLPUpdateService(dependencyResolver: resolver)
        dependencyStatus = resolver.resolveStatus()

        let storedQuality = UserDefaults.standard.string(forKey: AppPreferenceKeys.defaultQuality)
        selectedQuality = QualityProfile(rawValue: storedQuality ?? AppPreferenceDefaults.defaultQuality) ?? .q1080
        let storedContainer = UserDefaults.standard.string(forKey: AppPreferenceKeys.defaultContainer)
        selectedContainer = DownloadContainer(rawValue: storedContainer ?? AppPreferenceDefaults.defaultContainer) ?? .mp4
        ensureDefaultDownloadDirectory()
        Task { await refreshYTDLPVersion() }
    }

    var canAnalyze: Bool {
        parser.parse(inputURL) != nil && isAnalyzing == false
    }

    var canAddToQueue: Bool {
        guard media != nil else { return false }
        if media?.kind == .video, media?.formatAvailability.isKnown == false {
            return false
        }
        guard isQualityAvailable(selectedQuality) else { return false }
        if selectedQuality.isVideoQuality, isContainerAvailable(selectedContainer, for: selectedQuality) == false {
            return false
        }
        if media?.kind == .playlist {
            return playlistEntries.contains(where: \.isSelected)
        }
        return true
    }

    var canToggleQueue: Bool {
        queue.contains { $0.status == .pending || $0.status == .running }
    }

    var canClearQueue: Bool {
        queue.contains { $0.status != .running }
    }

    var queueControlTitle: String {
        isQueuePaused ? "Başlat" : "Duraklat"
    }

    var queueControlIcon: String {
        isQueuePaused ? "play.fill" : "pause.fill"
    }

    var formatSelectionDetail: String {
        if isAnalyzingFormats {
            return "Formatlar analiz ediliyor..."
        }
        if media?.formatAvailability.isKnown == false {
            return "Playlistlerde uygunluk video bazında kontrol edilir."
        }
        if selectedQuality.isAudioOnly {
            return selectedQuality.detail
        }
        return "\(selectedQuality.title) · \(selectedContainer.title)"
    }

    var maxResolutionDetail: String? {
        guard
            let availability = media?.formatAvailability,
            availability.isKnown,
            let maxHeight = availability.maxVideoHeight
        else {
            return nil
        }
        return "Bu videoda maksimum \(maxHeight)p var."
    }

    func isQualityAvailable(_ profile: QualityProfile) -> Bool {
        media?.formatAvailability.isResolutionAvailable(profile) ?? true
    }

    func isContainerAvailable(_ container: DownloadContainer, for profile: QualityProfile) -> Bool {
        media?.formatAvailability.isContainerAvailable(container, for: profile) ?? true
    }

    func updateSelectedQuality(_ quality: QualityProfile) {
        selectedQuality = quality
        UserDefaults.standard.set(quality.rawValue, forKey: AppPreferenceKeys.defaultQuality)
        reconcileSelectionWithAvailability()
    }

    func updateSelectedContainer(_ container: DownloadContainer) {
        selectedContainer = container
        UserDefaults.standard.set(container.rawValue, forKey: AppPreferenceKeys.defaultContainer)
        reconcileSelectionWithAvailability()
    }

    func refreshDependencies() {
        dependencyStatus = dependencyResolver.resolveStatus()
        Task { await refreshYTDLPVersion() }
    }

    func refreshYTDLPVersion() async {
        ytdlpInstalledVersion = await ytdlpUpdateService.installedVersion()
    }

    func checkYTDLPUpdate() async {
        guard isUpdatingYTDLP == false else { return }
        isUpdatingYTDLP = true
        ytdlpUpdateMessage = "yt-dlp kontrol ediliyor..."
        defer { isUpdatingYTDLP = false }

        let installedVersion = await ytdlpUpdateService.installedVersion()
        ytdlpInstalledVersion = installedVersion

        do {
            let latestRelease = try await ytdlpUpdateService.latestRelease()
            ytdlpLatestVersion = latestRelease.version

            if installedVersion == latestRelease.version {
                ytdlpUpdateMessage = "yt-dlp güncel."
            } else if installedVersion == nil {
                ytdlpUpdateMessage = "yt-dlp indirilmeye hazır."
            } else {
                ytdlpUpdateMessage = "Yeni sürüm hazır: \(latestRelease.version)"
            }
        } catch {
            ytdlpUpdateMessage = "Son sürüm kontrolü başarısız: \(error.localizedDescription)"
        }
    }

    func updateYTDLP() async {
        guard isUpdatingYTDLP == false else { return }
        isUpdatingYTDLP = true
        defer { isUpdatingYTDLP = false }
        ytdlpUpdateMessage = "yt-dlp indiriliyor..."

        do {
            let result = try await ytdlpUpdateService.installLatest()
            dependencyStatus = dependencyResolver.resolveStatus()
            ytdlpInstalledVersion = result.version
            ytdlpLatestVersion = result.version
            ytdlpUpdateMessage = "yt-dlp \(result.version) kuruldu."
        } catch {
            ytdlpUpdateMessage = error.localizedDescription
        }
    }

    func detectClipboardURL() {
        guard let value = NSPasteboard.general.string(forType: .string), parser.parse(value) != nil else {
            return
        }
        inputURL = value
        scheduleAnalyzeForCurrentURL()
    }

    func pasteFromClipboard() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        inputURL = value
        scheduleAnalyzeForCurrentURL()
    }

    func clearCurrentInput() {
        inputURL = ""
        statusMessage = nil
        clearLoadedMedia()
    }

    func scheduleAnalyzeForCurrentURL() {
        analyzeTask?.cancel()
        let trimmedURL = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmedURL.isEmpty == false else {
            statusMessage = nil
            clearLoadedMedia()
            return
        }

        guard parser.parse(trimmedURL) != nil else {
            if trimmedURL != lastAnalyzedURL {
                clearLoadedMedia()
            }
            return
        }

        guard isAnalyzing == false else { return }

        analyzeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard Task.isCancelled == false else { return }
            await self?.analyzeCurrentURL()
        }
    }

    func analyzeCurrentURL() async {
        let trimmedURL = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedURL = parser.parse(trimmedURL) else {
            clearLoadedMedia()
            statusMessage = AppError.invalidYouTubeURL.localizedDescription
            return
        }
        guard parsedURL.normalizedURL != lastAnalyzedURL || media == nil else { return }

        formatTask?.cancel()
        isAnalyzing = true
        isAnalyzingFormats = false
        statusMessage = nil
        refreshDependencies()

        do {
            let result = try await metadataService.fetchPreview(url: parsedURL.normalizedURL)
            media = result.media
            playlistEntries = result.entries
            lastAnalyzedURL = parsedURL.normalizedURL
            reconcileSelectionWithAvailability()
            isAnalyzing = false
            startFormatAnalysisIfNeeded(for: parsedURL.normalizedURL)
        } catch {
            clearLoadedMedia()
            statusMessage = error.localizedDescription
        }
    }

    private func startFormatAnalysisIfNeeded(for url: String) {
        guard media?.kind == .video else { return }

        isAnalyzingFormats = true
        formatTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.metadataService.fetch(url: url)
                guard Task.isCancelled == false, self.lastAnalyzedURL == url else { return }
                self.media = result.media
                self.playlistEntries = result.entries
                self.reconcileSelectionWithAvailability()
            } catch {
                guard Task.isCancelled == false, self.lastAnalyzedURL == url else { return }
                self.statusMessage = error.localizedDescription
            }
            self.isAnalyzingFormats = false
        }
    }

    func setAllPlaylistEntries(_ selected: Bool) {
        playlistEntries = playlistEntries.map { entry in
            var copy = entry
            copy.isSelected = selected
            return copy
        }
    }

    func addSelectedToQueue() {
        guard let media else {
            statusMessage = AppError.noMediaLoaded.localizedDescription
            return
        }

        let newItems: [DownloadItem]
        if media.kind == .playlist {
            let selectedEntries = playlistEntries.filter(\.isSelected)
            guard selectedEntries.isEmpty == false else {
                statusMessage = AppError.noPlaylistSelection.localizedDescription
                return
            }
            let validSelectedEntries = selectedEntries.compactMap { entry -> (entry: PlaylistEntry, normalizedURL: String)? in
                guard let parsed = parser.parse(entry.url) else { return nil }
                return (entry, parsed.normalizedURL)
            }
            guard validSelectedEntries.count == selectedEntries.count else {
                statusMessage = "Playlist içinde geçersiz YouTube bağlantısı var."
                return
            }
            newItems = validSelectedEntries
                .filter { candidate in
                    queue.contains(where: { $0.url == candidate.normalizedURL && $0.status != .failed && $0.status != .cancelled }) == false
                }
                .map { candidate in
	                    DownloadItem(
	                        url: candidate.normalizedURL,
	                        title: candidate.entry.title,
	                        quality: selectedQuality,
	                        container: selectedContainer,
	                        thumbnailURL: candidate.entry.thumbnailURL,
	                        playlistIndex: candidate.entry.index
	                    )
	                }
	        } else {
            guard let parsedMediaURL = parser.parse(media.webpageURL) else {
                statusMessage = AppError.invalidYouTubeURL.localizedDescription
                return
            }
            guard queue.contains(where: { $0.url == parsedMediaURL.normalizedURL && $0.status != .failed && $0.status != .cancelled }) == false else {
                statusMessage = "Bu video zaten kuyrukta."
                return
            }
            newItems = [
                DownloadItem(
	                    url: parsedMediaURL.normalizedURL,
	                    title: media.title,
	                    quality: selectedQuality,
	                    container: selectedContainer,
	                    thumbnailURL: media.thumbnailURL,
	                    estimatedSizeBytes: estimatedSizeBytes(for: media)
	                )
	            ]
	        }

        guard newItems.isEmpty == false else {
            statusMessage = "Seçilenler zaten kuyrukta."
            return
        }

        queue.append(contentsOf: newItems)
        if isQueuePaused == false {
            startQueueIfNeeded()
        }
    }

    func toggleQueuePlayback() {
        if isQueuePaused {
            resumeQueue()
        } else {
            pauseQueue()
        }
    }

    func resumeQueue() {
        guard canToggleQueue else { return }
        isQueuePaused = false
        startQueueIfNeeded()
    }

    func pauseQueue() {
        isQueuePaused = true
        if queue.contains(where: { $0.status == .running }) {
            downloadService.cancelCurrentDownload()
        }
    }

    func retry(_ item: DownloadItem) {
        guard let index = queue.firstIndex(where: { $0.id == item.id }) else { return }
        queue[index].status = .pending
        queue[index].progress = 0
	        queue[index].speed = ""
	        queue[index].eta = ""
	        queue[index].fileSizeBytes = nil
	        queue[index].errorMessage = nil
	        cancelledItems.remove(item.id)
	        if isQueuePaused == false {
	            startQueueIfNeeded()
	        }
    }

    func clearFinished() {
        queue
            .filter { $0.status == .failed || $0.status == .cancelled }
            .forEach { cleanupFiles(for: $0) }
        queue.removeAll { [.completed, .failed, .cancelled].contains($0.status) }
    }

    func clearQueue() {
        let removableItems = queue.filter { $0.status != .running }
        let removableIDs = Set(removableItems.map(\.id))

        removableItems
            .filter { $0.status != .completed }
            .forEach { cleanupFiles(for: $0) }

        queue.removeAll { removableIDs.contains($0.id) }
        cancelledItems.subtract(removableIDs)

        if queue.isEmpty {
            isQueuePaused = true
        }
    }

    func removeFromQueue(_ item: DownloadItem) {
        if item.status == .running {
            downloadService.cancelCurrentDownload()
        }
        if item.status != .completed {
            cleanupFiles(for: item)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                self.cleanupFiles(for: item)
            }
        }
        queue.removeAll { $0.id == item.id }
    }

    func moveQueueItemUp(_ item: DownloadItem) {
        guard
            item.status != .running,
            let index = queue.firstIndex(where: { $0.id == item.id }),
            index > 0
        else {
            return
        }
        queue.swapAt(index, index - 1)
    }

    func moveQueueItemDown(_ item: DownloadItem) {
        guard
            item.status != .running,
            let index = queue.firstIndex(where: { $0.id == item.id }),
            index < queue.count - 1
        else {
            return
        }
        queue.swapAt(index, index + 1)
    }

    func canMoveUp(_ item: DownloadItem) -> Bool {
        guard item.status != .running, let index = queue.firstIndex(where: { $0.id == item.id }) else {
            return false
        }
        return index > 0
    }

	func canMoveDown(_ item: DownloadItem) -> Bool {
	    guard item.status != .running, let index = queue.firstIndex(where: { $0.id == item.id }) else {
	        return false
	    }
	    return index < queue.count - 1
	}

	func moveQueueItem(draggedID: UUID, before targetID: UUID) {
	    guard
	        draggedID != targetID,
	        let sourceIndex = queue.firstIndex(where: { $0.id == draggedID }),
	        let targetIndex = queue.firstIndex(where: { $0.id == targetID }),
	        queue[sourceIndex].status != .running
	    else {
	        return
	    }

	    let movedItem = queue.remove(at: sourceIndex)
	    let destinationIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
	    queue.insert(movedItem, at: max(0, destinationIndex))
	}

	func moveQueueItemToEnd(_ draggedID: UUID) {
	    guard
	        let sourceIndex = queue.firstIndex(where: { $0.id == draggedID }),
	        queue[sourceIndex].status != .running,
	        sourceIndex < queue.count - 1
	    else {
	        return
	    }

	    let movedItem = queue.remove(at: sourceIndex)
	    queue.append(movedItem)
	}

    func revealInFinder(_ item: DownloadItem) {
        guard let outputPath = item.outputPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputPath)])
    }

    private func startQueueIfNeeded() {
        guard isQueuePaused == false, queueTask == nil else { return }
        queueTask = Task { [weak self] in
            await self?.runQueue()
        }
    }

    private func runQueue() async {
        isQueueProcessing = true
        defer {
            queueTask = nil
            isQueueProcessing = false
            if queue.contains(where: { $0.status == .pending }) == false {
                isQueuePaused = true
            }
        }
        while isQueuePaused == false, let index = queue.firstIndex(where: { $0.status == .pending }) {
            queue[index].status = .running
            queue[index].speed = ""
            queue[index].eta = ""
            queue[index].errorMessage = nil

            let item = queue[index]
            let outputDirectoryURL = currentDownloadDirectoryURL()
            let isAccessingSecurityScopedResource = outputDirectoryURL.startAccessingSecurityScopedResource()
            defer {
                if isAccessingSecurityScopedResource {
                    outputDirectoryURL.stopAccessingSecurityScopedResource()
                }
            }
            let outputDirectory = outputDirectoryURL.path

            do {
                let outputPath = try await downloadService.download(
                    item: item,
                    outputDirectory: outputDirectory,
                    onProgress: { [weak self] progress in
                        Task { @MainActor in
                            self?.apply(progress, to: item.id)
                        }
                    },
                    onOutputPath: { [weak self] path in
                        Task { @MainActor in
                            self?.setOutputPath(path, for: item.id)
                        }
                    },
                    onContainerChanged: { [weak self] container in
                        Task { @MainActor in
                            self?.setContainer(container, for: item.id)
                        }
                    }
                )

                if cancelledItems.contains(item.id) {
                    mark(item.id, status: .cancelled)
                } else {
                    setOutputPath(outputPath, for: item.id)
                    mark(item.id, status: .completed)
                }
            } catch {
                if isQueuePaused {
                    mark(item.id, status: .pending)
                    clearTransientProgress(for: item.id)
                    break
                } else if cancelledItems.contains(item.id) {
                    mark(item.id, status: .cancelled)
                } else {
                    mark(item.id, status: .failed, errorMessage: error.localizedDescription)
                }
            }
        }
    }

    private func apply(_ progress: DownloadProgress, to id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        if let fraction = progress.fraction {
            queue[index].progress = fraction
        }
        queue[index].speed = progress.speed
        queue[index].eta = progress.eta
    }

    private func setOutputPath(_ path: String?, for id: UUID) {
        guard let path, let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].outputPath = path
        if queue[index].outputPaths.contains(path) == false {
            queue[index].outputPaths.append(path)
        }
    }

	private func setContainer(_ container: DownloadContainer, for id: UUID) {
	    guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
	    queue[index].container = container
	}

    private func mark(_ id: UUID, status: DownloadState, errorMessage: String? = nil) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].status = status
	    queue[index].errorMessage = errorMessage
	    if status == .completed {
	        queue[index].progress = 1
	        queue[index].fileSizeBytes = fileSizeBytes(for: queue[index])
	    }
	}

    private func clearTransientProgress(for id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].speed = ""
        queue[index].eta = ""
        queue[index].errorMessage = nil
    }

    private func currentDownloadDirectory() -> String {
        UserDefaults.standard.string(forKey: AppPreferenceKeys.downloadDirectory) ?? AppPreferenceDefaults.downloadDirectory
    }

    private func currentDownloadDirectoryURL() -> URL {
        let defaults = UserDefaults.standard
        if let bookmark = defaults.data(forKey: AppPreferenceKeys.downloadDirectoryBookmark) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale, let refreshedBookmark = try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    defaults.set(refreshedBookmark, forKey: AppPreferenceKeys.downloadDirectoryBookmark)
                }
                return url
            }
        }
        return URL(fileURLWithPath: currentDownloadDirectory())
    }

    private func ensureDefaultDownloadDirectory() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: AppPreferenceKeys.downloadDirectory) == nil {
            defaults.set(AppPreferenceDefaults.downloadDirectory, forKey: AppPreferenceKeys.downloadDirectory)
        }
        if defaults.string(forKey: AppPreferenceKeys.defaultQuality) == nil {
            defaults.set(AppPreferenceDefaults.defaultQuality, forKey: AppPreferenceKeys.defaultQuality)
        }
        if defaults.string(forKey: AppPreferenceKeys.defaultContainer) == nil {
            defaults.set(AppPreferenceDefaults.defaultContainer, forKey: AppPreferenceKeys.defaultContainer)
        }
    }

	private func reconcileSelectionWithAvailability() {
        guard let media else { return }

        if media.formatAvailability.isResolutionAvailable(selectedQuality) == false {
            selectedQuality = QualityProfile.allCases.first { media.formatAvailability.isResolutionAvailable($0) } ?? .best
            UserDefaults.standard.set(selectedQuality.rawValue, forKey: AppPreferenceKeys.defaultQuality)
        }

        guard selectedQuality.isVideoQuality else { return }

        if let container = media.formatAvailability.preferredContainer(for: selectedQuality, preferred: selectedContainer) {
            selectedContainer = container
            UserDefaults.standard.set(container.rawValue, forKey: AppPreferenceKeys.defaultContainer)
	    }
	}

	private func estimatedSizeBytes(for media: MediaInfo) -> Int64? {
	    media.formatAvailability.estimatedDownloadSizeBytes(
	        for: selectedQuality,
	        container: selectedContainer
	    )
	}

	private func fileSizeBytes(for item: DownloadItem) -> Int64? {
	    let paths = [item.outputPath].compactMap { $0 } + item.outputPaths
	    for path in paths {
	        if let size = fileSizeBytes(at: path) {
	            return size
	        }
	    }
	    return nil
	}

	private func fileSizeBytes(at path: String) -> Int64? {
	    guard
	        let attributes = try? FileManager.default.attributesOfItem(atPath: path),
	        let size = attributes[.size] as? NSNumber
	    else {
	        return nil
	    }
	    return size.int64Value
	}

	private func cleanupFiles(for item: DownloadItem) {
        let paths = Set(item.outputPaths + [item.outputPath].compactMap { $0 })
        artifactCleaner.removeArtifacts(for: Array(paths))
    }

    private func clearLoadedMedia() {
        formatTask?.cancel()
        media = nil
        playlistEntries = []
        lastAnalyzedURL = ""
        isAnalyzing = false
        isAnalyzingFormats = false
    }
}
