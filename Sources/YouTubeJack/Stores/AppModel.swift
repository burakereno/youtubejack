import AppKit
import Combine
import Foundation
import YouTubeJackCore

@MainActor
final class AppModel: ObservableObject {
    @Published var inputURL = "" {
        didSet {
            guard inputURL != oldValue else { return }
            invalidateAnalysis()
            if parser.parse(inputURL)?.normalizedURL != lastAnalyzedURL { clearLoadedMedia() }
        }
    }
    @Published var media: MediaInfo?
    @Published var playlistEntries: [PlaylistEntry] = [] {
        didSet {
            if playlistEntries.filter(\.isSelected).map(\.url) != oldValue.filter(\.isSelected).map(\.url),
               media?.kind == .playlist {
                startPlaylistFormatAnalysis()
            }
        }
    }
    @Published private(set) var playlistMetadata: [String: MediaInfo] = [:]
    @Published private(set) var failedPlaylistURLs: Set<String> = []
    @Published var selectedQuality: QualityProfile
    @Published var selectedContainer: DownloadContainer
    @Published var selectedVideoCodec: VideoCodecPreference
    @Published var selectedAudioLanguage = AudioLanguageSelection.original
    @Published var subtitleOptions = SubtitleOptions() {
        didSet {
            if let data = try? JSONEncoder().encode(subtitleOptions) {
                defaults.set(data, forKey: AppPreferenceKeys.subtitleOptions)
            }
        }
    }
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
    @Published var isSettingsPanelPresented = false
    @Published var isUpdatePanelPresented = false
    @Published private(set) var isPreparingAppUpdate = false

    private let parser = YouTubeURLParser()
    private let defaults: UserDefaults
    private let dependencyResolver: DependencyResolver
    private let metadataClient: MetadataClient
    private let downloadService: DownloadService
    private let ytdlpUpdateService: YTDLPUpdateService
    private let artifactCleaner = DownloadArtifactCleaner()
    private var analyzeTask: Task<Void, Never>?
    private var formatTask: Task<Void, Never>?
    private var queueTask: Task<Void, Never>?
    private var downloadTask: Task<String?, any Error>?
    private var pauseRequestedItemIDs = Set<UUID>()
    private var analysisID = UUID()
    private var lastAnalyzedURL = ""
    private var cancelledItems = Set<UUID>()
    private var formatAnalysisID = UUID()

    init(dependencyResolver resolver: DependencyResolver = DependencyResolver(), defaults: UserDefaults = .standard,
         metadataClient: MetadataClient? = nil) {
        self.defaults = defaults
        dependencyResolver = resolver
        self.metadataClient = metadataClient ?? MetadataClient(service: MetadataService(dependencyResolver: resolver))
        downloadService = DownloadService(dependencyResolver: resolver)
        ytdlpUpdateService = YTDLPUpdateService(dependencyResolver: resolver)
        dependencyStatus = resolver.resolveStatus()

        let storedQuality = defaults.string(forKey: AppPreferenceKeys.defaultQuality)
        selectedQuality = QualityProfile(rawValue: storedQuality ?? AppPreferenceDefaults.defaultQuality) ?? .q1080
        let storedContainer = defaults.string(forKey: AppPreferenceKeys.defaultContainer)
        selectedContainer = DownloadContainer(rawValue: storedContainer ?? AppPreferenceDefaults.defaultContainer) ?? .mp4
        let storedCodec = defaults.string(forKey: AppPreferenceKeys.defaultVideoCodec)
        selectedVideoCodec = VideoCodecPreference(rawValue: storedCodec ?? AppPreferenceDefaults.defaultVideoCodec) ?? .automatic
        var initialSubtitleOptions = SubtitleOptions()
        if let data = defaults.data(forKey: AppPreferenceKeys.subtitleOptions),
           let saved = try? JSONDecoder().decode(SubtitleOptions.self, from: data) {
            initialSubtitleOptions = saved
        }
        if defaults.bool(forKey: AppPreferenceKeys.subtitleAutomaticOptInMigrated) == false {
            // Earlier builds enabled automatic captions by default; require an explicit opt-in once.
            initialSubtitleOptions.includesAutomatic = false
            if let data = try? JSONEncoder().encode(initialSubtitleOptions) {
                defaults.set(data, forKey: AppPreferenceKeys.subtitleOptions)
            }
            defaults.set(true, forKey: AppPreferenceKeys.subtitleAutomaticOptInMigrated)
        }
        subtitleOptions = initialSubtitleOptions
        if selectedVideoCodec == .h264 {
            selectedContainer = .mp4
        }
        ensureDefaultDownloadDirectory()
        Task { await refreshYTDLPVersion() }
    }

    var canAnalyze: Bool {
        parser.parse(inputURL) != nil && isAnalyzing == false && isAnyDrawerPresented == false
    }

    var isAnyDrawerPresented: Bool { isSettingsPanelPresented || isUpdatePanelPresented }

    var canAddToQueue: Bool {
        guard isPreparingAppUpdate == false, isAnyDrawerPresented == false else { return false }
        guard media != nil, isAnalyzing == false, isAnalyzingFormats == false else { return false }
        if canIncludeSubtitles, subtitleOptions.isEnabled, subtitleOptions.languageCodes.isEmpty { return false }
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
        guard isPreparingAppUpdate == false else { return false }
        return queue.contains { $0.status == .pending || $0.status == .running }
    }

    private var hasUnfinishedDownloads: Bool {
        isQueueProcessing || queueTask != nil || queue.contains { $0.status == .pending || $0.status == .running }
    }

    var canInstallAppUpdate: Bool { isPreparingAppUpdate == false && hasUnfinishedDownloads == false }

    @discardableResult
    func installAppUpdate(using updater: UpdateChecker) -> Task<Void, Never>? {
        guard canInstallAppUpdate else {
            updater.reportInstallationBlocked()
            presentUpdatePanel()
            return nil
        }
        return updater.downloadAndInstall(canInstall: { [weak self] in
            self?.hasUnfinishedDownloads == false
        }, onPreparationChanged: { [weak self] in
            self?.isPreparingAppUpdate = $0
        })
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
        if media?.kind == .playlist {
            let availability = playlistAvailability
            if availability.selectedEntries.isEmpty { return "Seçenekleri görmek için playlistten video seçin." }
            if isAnalyzingFormats {
                return "Seçili videolar kontrol ediliyor: \(availability.checkedCount + availability.failedCount)/\(availability.selectedEntries.count)."
            }
            if availability.failedCount > 0 {
                return "\(availability.failedCount) videonun seçenekleri kontrol edilemedi. Bu videolar indirilirken tekrar kontrol edilir."
            }
            let matching = availability.selectedMedia.filter {
                let formats = $0.formatAvailability
                return selectedQuality.isAudioOnly
                    ? formats.isResolutionAvailable(selectedQuality, audioLanguage: selectedAudioLanguage)
                    : formats.isContainerAvailable(selectedContainer, for: selectedQuality, codec: selectedVideoCodec, audioLanguage: selectedAudioLanguage)
            }.count
            return "Görüntü ve ses seçimi \(matching)/\(availability.selectedEntries.count) videoda kullanılabilir."
        }
        if isAnalyzingFormats {
            return "Formatlar analiz ediliyor..."
        }
        if media?.formatAvailability.isKnown == false {
            return "Playlistlerde uygunluk video bazında kontrol edilir."
        }
        if selectedQuality.isAudioOnly {
            return selectedQuality.detail
        }
        if isQualityAvailable(selectedQuality) == false || isContainerAvailable(selectedContainer, for: selectedQuality) == false {
            return "Seçilen video akışı bu çözünürlükte veya formatta yok. Başka bir seçim yapın."
        }
        return "\(selectedQuality.title) · \(selectedVideoCodec.title) · \(selectedContainer.title)"
    }

    var maxResolutionDetail: String? {
        guard media?.kind != .playlist else { return nil }
        guard selectedQuality.isVideoQuality else { return nil }
        guard
            let availability = media?.formatAvailability,
            availability.isKnown,
            let maxHeight = availability.maxVideoHeight(codec: selectedVideoCodec, audioLanguage: selectedAudioLanguage)
        else {
            return nil
        }
        if selectedVideoCodec == .automatic {
            return "Bu videoda maksimum \(maxHeight)p var."
        }
        return "\(selectedVideoCodec.title) için maksimum \(maxHeight)p var."
    }

    func isQualityAvailable(_ profile: QualityProfile) -> Bool {
        if media?.kind == .playlist {
            return playlistAvailability.supports { $0.isResolutionAvailable(profile, codec: selectedVideoCodec, audioLanguage: selectedAudioLanguage) }
        }
        return media?.formatAvailability.isResolutionAvailable(profile, codec: selectedVideoCodec, audioLanguage: selectedAudioLanguage) ?? true
    }

    func isContainerAvailable(_ container: DownloadContainer, for profile: QualityProfile) -> Bool {
        guard selectedVideoCodec.allows(container) else { return false }
        if media?.kind == .playlist {
            return playlistAvailability.supports { $0.isContainerAvailable(container, for: profile, codec: selectedVideoCodec, audioLanguage: selectedAudioLanguage) }
        }
        return media?.formatAvailability.isContainerAvailable(container, for: profile, codec: selectedVideoCodec, audioLanguage: selectedAudioLanguage) ?? true
    }

    func isVideoCodecAvailable(_ codec: VideoCodecPreference) -> Bool {
        guard selectedQuality.isVideoQuality else { return false }
        if media?.kind == .playlist {
            return playlistAvailability.supports { $0.isResolutionAvailable(selectedQuality, codec: codec, audioLanguage: selectedAudioLanguage) }
        }
        return media?.formatAvailability.isResolutionAvailable(selectedQuality, codec: codec, audioLanguage: selectedAudioLanguage) ?? true
    }

    func updateSelectedQuality(_ quality: QualityProfile) {
        selectedQuality = quality
        reconcileSelectionWithAvailability()
    }

    var audioLanguages: [AudioLanguage] {
        if media?.kind == .playlist { return playlistAvailability.audioLanguages }
        return media?.formatAvailability.audioLanguages ?? []
    }

    var playlistAvailability: PlaylistAvailability {
        PlaylistAvailability(entries: playlistEntries, metadataByURL: playlistMetadata, failedURLs: failedPlaylistURLs)
    }

    var formatAnalysisTitle: String {
        guard media?.kind == .playlist else { return "Formatlar analiz ediliyor" }
        let availability = playlistAvailability
        return "Videolar kontrol ediliyor · \(availability.checkedCount + availability.failedCount)/\(availability.selectedEntries.count)"
    }

    var formatAnalysisProgress: Double? {
        guard media?.kind == .playlist else { return nil }
        let availability = playlistAvailability
        let total = availability.selectedEntries.count
        guard total > 0 else { return nil }
        return Double(availability.checkedCount + availability.failedCount) / Double(total)
    }

    var formatAnalysisDetail: String? {
        guard media?.kind == .playlist else { return nil }
        let availability = playlistAvailability
        let total = availability.selectedEntries.count
        guard total > 0 else { return nil }
        // Keep 100% reserved for when every selected video has been checked.
        let percentage = (availability.checkedCount + availability.failedCount) * 100 / total
        return "\(percentage)% · \(availability.pendingCount) video kaldı"
    }

    var queuedAudioLanguage: AudioLanguageSelection {
        selectedAudioLanguage.resolved(in: media?.formatAvailability ?? .unknown)
    }

    func updateSelectedAudioLanguage(_ language: AudioLanguageSelection) {
        selectedAudioLanguage = language
        reconcileSelectionWithAvailability()
    }

    var subtitleLanguages: [SubtitleLanguage] {
        subtitleAvailability.languages
    }

    var selectableSubtitleLanguages: [SubtitleLanguage] {
        subtitleLanguages.filter { $0.hasManual || subtitleOptions.includesAutomatic && $0.hasAutomatic }
    }

    var hasOnlyAutomaticSubtitles: Bool {
        subtitleAvailability.isKnown && subtitleLanguages.isEmpty == false &&
            subtitleLanguages.allSatisfy { $0.hasManual == false && $0.hasAutomatic }
    }

    var subtitleAvailability: SubtitleAvailability {
        media?.kind == .playlist ? playlistAvailability.subtitleAvailability : media?.subtitleAvailability ?? .unknown
    }

    var canIncludeSubtitles: Bool {
        guard selectedQuality.isVideoQuality else { return false }
        if media?.kind == .playlist, playlistAvailability.selectedEntries.isEmpty { return false }
        // Unknown availability is not evidence that captions are absent.
        return subtitleAvailability.isKnown == false || selectableSubtitleLanguages.isEmpty == false
    }

    var includesSubtitles: Bool {
        get { canIncludeSubtitles && subtitleOptions.isEnabled }
        set { subtitleOptions.isEnabled = newValue }
    }

    var includesAutomaticSubtitles: Bool {
        get { subtitleOptions.includesAutomatic }
        set {
            subtitleOptions.includesAutomatic = newValue
            reconcileSubtitleSelection()
        }
    }

    var queuedSubtitleOptions: SubtitleOptions {
        guard canIncludeSubtitles else { return SubtitleOptions() }
        return subtitleOptions
    }

    func setSubtitleLanguage(_ code: String, selected: Bool) {
        var codes = Set(subtitleOptions.languageCodes)
        if selected { codes.insert(code) } else { codes.remove(code) }
        subtitleOptions.languageCodes = codes.sorted()
    }

    func reconcileSubtitleSelection() {
        let availability = subtitleAvailability
        guard availability.isKnown else { return }
        let eligible = selectableSubtitleLanguages
        guard eligible.isEmpty == false else {
            subtitleOptions.languageCodes = []
            return
        }
        let availableCodes = Set(eligible.map(\.code))
        let selected = subtitleOptions.languageCodes.filter { availableCodes.contains($0) }
        subtitleOptions.languageCodes = selected.isEmpty ? [eligible[0].code] : selected
    }

    func updateSelectedContainer(_ container: DownloadContainer) {
        if selectedVideoCodec.allows(container) == false {
            selectedVideoCodec = .automatic
        }
        selectedContainer = container
        reconcileSelectionWithAvailability()
    }

    func updateSelectedVideoCodec(_ codec: VideoCodecPreference) {
        selectedVideoCodec = codec
        if codec == .h264 {
            selectedContainer = .mp4
        }
        reconcileSelectionWithAvailability()
    }

    func updateDefaultQuality(_ quality: QualityProfile) {
        defaults.set(quality.rawValue, forKey: AppPreferenceKeys.defaultQuality)
        updateSelectedQuality(quality)
    }

    func updateDefaultContainer(_ container: DownloadContainer) {
        defaults.set(container.rawValue, forKey: AppPreferenceKeys.defaultContainer)
        let codec = VideoCodecPreference(rawValue: defaults.string(forKey: AppPreferenceKeys.defaultVideoCodec) ?? "") ?? .automatic
        if codec.allows(container) == false { defaults.set(VideoCodecPreference.automatic.rawValue, forKey: AppPreferenceKeys.defaultVideoCodec) }
        updateSelectedContainer(container)
    }

    func updateDefaultVideoCodec(_ codec: VideoCodecPreference) {
        defaults.set(codec.rawValue, forKey: AppPreferenceKeys.defaultVideoCodec)
        if codec == .h264 { defaults.set(DownloadContainer.mp4.rawValue, forKey: AppPreferenceKeys.defaultContainer) }
        updateSelectedVideoCodec(codec)
    }

    private func applySavedDownloadDefaults() {
        selectedQuality = QualityProfile(rawValue: defaults.string(forKey: AppPreferenceKeys.defaultQuality) ?? "") ?? .q1080
        selectedContainer = DownloadContainer(rawValue: defaults.string(forKey: AppPreferenceKeys.defaultContainer) ?? "") ?? .mp4
        selectedVideoCodec = VideoCodecPreference(rawValue: defaults.string(forKey: AppPreferenceKeys.defaultVideoCodec) ?? "") ?? .automatic
        if selectedVideoCodec == .h264 { selectedContainer = .mp4 }
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

    func presentSettingsPanel() {
        clearKeyboardFocus()
        isUpdatePanelPresented = false
        isSettingsPanelPresented = true
    }

    func toggleSettingsPanel() {
        if isSettingsPanelPresented {
            isSettingsPanelPresented = false
        } else {
            presentSettingsPanel()
        }
    }

    func presentUpdatePanel() {
        clearKeyboardFocus()
        isSettingsPanelPresented = false
        isUpdatePanelPresented = true
    }

    func toggleUpdatePanel() {
        if isUpdatePanelPresented {
            isUpdatePanelPresented = false
        } else {
            presentUpdatePanel()
        }
    }

    private func clearKeyboardFocus() {
        NSApp?.keyWindow?.makeFirstResponder(nil)
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
        guard parsedURL.normalizedURL != lastAnalyzedURL || media == nil else {
            if media?.kind == .playlist, isAnalyzingFormats == false, failedPlaylistURLs.isEmpty == false {
                failedPlaylistURLs = []
                startPlaylistFormatAnalysis()
            } else if media?.kind == .video, media?.formatAvailability.isKnown == false, isAnalyzingFormats == false {
                statusMessage = nil
                startFormatAnalysisIfNeeded(for: parsedURL.normalizedURL)
            }
            return
        }
        if parsedURL.normalizedURL != lastAnalyzedURL {
            selectedAudioLanguage = .original
            applySavedDownloadDefaults()
        }

        analysisID = UUID()
        let requestID = analysisID

        formatTask?.cancel()
        formatAnalysisID = UUID()
        isAnalyzing = true
        isAnalyzingFormats = false
        media = nil
        playlistEntries = []
        playlistMetadata = [:]
        failedPlaylistURLs = []
        statusMessage = nil
        refreshDependencies()

        do {
            let result = try await metadataClient.fetchPreview(parsedURL.normalizedURL)
            guard isCurrentAnalysis(requestID, url: parsedURL.normalizedURL), Task.isCancelled == false else { return }
            media = result.media
            playlistEntries = result.entries
            lastAnalyzedURL = parsedURL.normalizedURL
            reconcileSelectionWithAvailability()
            isAnalyzing = false
            startFormatAnalysisIfNeeded(for: parsedURL.normalizedURL)
        } catch {
            guard isCurrentAnalysis(requestID, url: parsedURL.normalizedURL) else { return }
            if error is CancellationError { isAnalyzing = false; return }
            clearLoadedMedia()
            statusMessage = error.localizedDescription
        }
    }

    private func startFormatAnalysisIfNeeded(for url: String) {
        if media?.kind == .playlist {
            startPlaylistFormatAnalysis()
            return
        }
        guard media?.kind == .video, media?.formatAvailability.isKnown == false else { return }

        formatTask?.cancel()
        formatAnalysisID = UUID()
        let requestID = formatAnalysisID
        isAnalyzingFormats = true
        formatTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.metadataClient.fetch(url)
                guard Task.isCancelled == false, self.formatAnalysisID == requestID, self.lastAnalyzedURL == url,
                      self.parser.parse(self.inputURL)?.normalizedURL == url else { return }
                self.media = result.media
                self.playlistEntries = result.entries
                self.reconcileSelectionWithAvailability()
                self.statusMessage = nil
            } catch {
                guard Task.isCancelled == false, self.formatAnalysisID == requestID, self.lastAnalyzedURL == url else { return }
                self.statusMessage = error.localizedDescription
            }
            self.isAnalyzingFormats = false
        }
    }

    private func startPlaylistFormatAnalysis() {
        guard media?.kind == .playlist, isAnalyzing == false else { return }
        formatTask?.cancel()
        formatAnalysisID = UUID()
        let analysisID = formatAnalysisID
        var seen = Set<String>()
        let urls = playlistEntries.filter(\.isSelected).map(\.url).filter {
            seen.insert($0).inserted && playlistMetadata[$0] == nil && failedPlaylistURLs.contains($0) == false
        }
        isAnalyzingFormats = urls.isEmpty == false
        reconcileSelectionWithAvailability()
        guard urls.isEmpty == false else { return }

        let service = metadataClient
        formatTask = Task { [weak self] in
            await withTaskGroup(of: (String, MediaInfo?).self) { group in
                var remaining = urls.makeIterator()
                // Limit extraction processes so large playlists remain responsive.
                for _ in 0..<3 {
                    guard let url = remaining.next() else { break }
                    group.addTask { (url, try? await service.fetch(url).media) }
                }
                for await (url, info) in group {
                    guard let self, Task.isCancelled == false, self.formatAnalysisID == analysisID else {
                        group.cancelAll()
                        break
                    }
                    if let info, info.kind == .video, info.formatAvailability.isKnown {
                        self.playlistMetadata[url] = info
                    } else {
                        self.failedPlaylistURLs.insert(url)
                    }
                    if let next = remaining.next() {
                        group.addTask { (next, try? await service.fetch(next).media) }
                    }
                }
            }
            guard let self, Task.isCancelled == false, self.formatAnalysisID == analysisID else { return }
            self.isAnalyzingFormats = false
            self.reconcileSelectionWithAvailability()
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
        guard canAddToQueue else { return }

        let newItems: [DownloadItem]
        if media.kind == .playlist {
            let selectedEntries = playlistEntries.filter(\.isSelected)
            guard selectedEntries.isEmpty == false else {
                statusMessage = AppError.noPlaylistSelection.localizedDescription
                return
            }
            let validSelectedEntries = selectedEntries.compactMap { entry -> (entry: PlaylistEntry, normalizedURL: String, audioLanguage: AudioLanguageSelection)? in
                guard let parsed = parser.parse(entry.url) else { return nil }
                return (entry, parsed.normalizedURL, selectedAudioLanguage.resolved(in: playlistMetadata[entry.url]?.formatAvailability ?? .unknown))
            }
            guard validSelectedEntries.count == selectedEntries.count else {
                statusMessage = "Playlist içinde geçersiz YouTube bağlantısı var."
                return
            }
            newItems = validSelectedEntries
                .filter { candidate in
                    queue.contains(where: { $0.url == candidate.normalizedURL && $0.quality == selectedQuality && $0.container == selectedContainer && $0.videoCodecPreference == selectedVideoCodec && $0.subtitles == queuedSubtitleOptions && $0.audioLanguage == candidate.audioLanguage && $0.status != .failed && $0.status != .cancelled }) == false
                }
                .map { candidate in
	                    DownloadItem(
	                        url: candidate.normalizedURL,
	                        title: candidate.entry.title,
	                        quality: selectedQuality,
	                        container: selectedContainer,
	                        videoCodecPreference: selectedVideoCodec,
	                        audioLanguage: candidate.audioLanguage,
	                        subtitles: queuedSubtitleOptions,
	                        thumbnailURL: candidate.entry.thumbnailURL,
	                        playlistIndex: candidate.entry.index
	                    )
	                }
	        } else {
            guard let parsedMediaURL = parser.parse(media.webpageURL) else {
                statusMessage = AppError.invalidYouTubeURL.localizedDescription
                return
            }
            guard queue.contains(where: { $0.url == parsedMediaURL.normalizedURL && $0.quality == selectedQuality && $0.container == selectedContainer && $0.videoCodecPreference == selectedVideoCodec && $0.subtitles == queuedSubtitleOptions && $0.audioLanguage == queuedAudioLanguage && $0.status != .failed && $0.status != .cancelled }) == false else {
                statusMessage = "Bu video aynı kalite, format, ses ve altyazı seçimiyle zaten kuyrukta."
                return
            }
            newItems = [
                DownloadItem(
	                    url: parsedMediaURL.normalizedURL,
	                    title: media.title,
	                    quality: selectedQuality,
	                    container: selectedContainer,
	                    videoCodecPreference: selectedVideoCodec,
	                    audioLanguage: queuedAudioLanguage,
	                    subtitles: queuedSubtitleOptions,
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
        guard canToggleQueue, isPreparingAppUpdate == false else { return }
        isQueuePaused = false
        startQueueIfNeeded()
    }

    func pauseQueue() {
        isQueuePaused = true
        if let item = queue.first(where: { $0.status == .running }) {
            pauseRequestedItemIDs.insert(item.id)
            downloadTask?.cancel()
            downloadService.cancelCurrentDownload()
        }
    }

    func retry(_ item: DownloadItem) {
        guard isPreparingAppUpdate == false else { return }
        guard let index = queue.firstIndex(where: { $0.id == item.id }) else { return }
        queue[index].status = .pending
        queue[index].progress = 0
        queue[index].selectedMediaFormat = nil
        queue[index].speed = ""
        queue[index].eta = ""
        queue[index].fileSizeBytes = nil
        queue[index].errorMessage = nil
        queue[index].subtitleMessage = nil
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
            downloadTask?.cancel()
            downloadService.cancelCurrentDownload()
        } else if item.status != .completed {
            cleanupFiles(for: item)
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
        guard isQueuePaused == false, queueTask == nil, isPreparingAppUpdate == false else { return }
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
            queue[index].selectedMediaFormat = nil
            queue[index].errorMessage = nil
            queue[index].subtitleMessage = nil

            let outputDirectoryURL = currentDownloadDirectoryURL()
            queue[index].temporaryDirectoryPath = DownloadWorkspace(outputDirectory: outputDirectoryURL.path, itemID: queue[index].id).directory.path
            let item = queue[index]
            let isAccessingSecurityScopedResource = outputDirectoryURL.startAccessingSecurityScopedResource()
            defer {
                downloadTask = nil
                pauseRequestedItemIDs.remove(item.id)
                if queue.contains(where: { $0.id == item.id }) == false { cleanupFiles(for: item) }
                if isAccessingSecurityScopedResource {
                    outputDirectoryURL.stopAccessingSecurityScopedResource()
                }
            }
            let outputDirectory = outputDirectoryURL.path

            do {
                let operation = Task { [self] in
                    try await downloadService.download(
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
                        },
                        onSelectedMediaFormat: { [weak self] format in
                            Task { @MainActor in
                                self?.setSelectedMediaFormat(format, for: item.id)
                            }
                        },
                        onSubtitleMessage: { [weak self] message in
                            Task { @MainActor in
                                self?.setSubtitleMessage(message, for: item.id)
                            }
                        },
                        onArtifactPath: { [weak self] path in
                            Task { @MainActor in
                                self?.trackArtifact(path, for: item.id)
                            }
                        }
                    )
                }
                downloadTask = operation
                let outputPath = try await operation.value

                if cancelledItems.contains(item.id) {
                    mark(item.id, status: .cancelled)
                } else {
                    setOutputPath(outputPath, for: item.id)
                    mark(item.id, status: .completed)
                }
            } catch {
                if pauseRequestedItemIDs.remove(item.id) != nil {
                    mark(item.id, status: .pending)
                    clearTransientProgress(for: item.id)
                    if isQueuePaused { break }
                    continue
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

    private func setSelectedMediaFormat(_ format: SelectedMediaFormat?, for id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].selectedMediaFormat = format
    }

    private func setSubtitleMessage(_ message: String?, for id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        queue[index].subtitleMessage = message
    }

    private func trackArtifact(_ path: String, for id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        if queue[index].outputPaths.contains(path) == false { queue[index].outputPaths.append(path) }
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
        defaults.string(forKey: AppPreferenceKeys.downloadDirectory) ?? AppPreferenceDefaults.downloadDirectory
    }

    private func currentDownloadDirectoryURL() -> URL {
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
        if defaults.string(forKey: AppPreferenceKeys.downloadDirectory) == nil {
            defaults.set(AppPreferenceDefaults.downloadDirectory, forKey: AppPreferenceKeys.downloadDirectory)
        }
        if defaults.string(forKey: AppPreferenceKeys.defaultQuality) == nil {
            defaults.set(AppPreferenceDefaults.defaultQuality, forKey: AppPreferenceKeys.defaultQuality)
        }
        if defaults.string(forKey: AppPreferenceKeys.defaultContainer) == nil {
            defaults.set(AppPreferenceDefaults.defaultContainer, forKey: AppPreferenceKeys.defaultContainer)
        }
        if defaults.string(forKey: AppPreferenceKeys.defaultVideoCodec) == nil {
            defaults.set(AppPreferenceDefaults.defaultVideoCodec, forKey: AppPreferenceKeys.defaultVideoCodec)
        }
    }

    private func reconcileSelectionWithAvailability() {
        guard let media else { return }
        reconcileSubtitleSelection()

        if media.kind == .playlist {
            let availability = playlistAvailability
            guard availability.selectedEntries.isEmpty == false, availability.pendingCount == 0 else { return }
            if availability.isComplete, selectedAudioLanguage.isOriginal == false,
               audioLanguages.contains(where: { $0.code == selectedAudioLanguage.languageCode }) == false {
                selectedAudioLanguage = .original
            }
            if selectedQuality.isVideoQuality, isVideoCodecAvailable(selectedVideoCodec) == false {
                selectedVideoCodec = .automatic
            }
            if isQualityAvailable(selectedQuality) == false,
               let quality = QualityProfile.allCases.first(where: { $0.isAudioOnly == selectedQuality.isAudioOnly && isQualityAvailable($0) }) {
                selectedQuality = quality
            }
            if selectedQuality.isVideoQuality, isContainerAvailable(selectedContainer, for: selectedQuality) == false,
               let container = DownloadContainer.allCases.first(where: { isContainerAvailable($0, for: selectedQuality) }) {
                selectedContainer = container
            }
            return
        }

        if media.kind == .video, media.formatAvailability.isKnown,
           selectedAudioLanguage.isOriginal == false,
           media.formatAvailability.audioLanguages.contains(where: { $0.code == selectedAudioLanguage.languageCode }) == false {
            selectedAudioLanguage = .original
        }

        if media.formatAvailability.isKnown, selectedQuality.isVideoQuality,
           isVideoCodecAvailable(selectedVideoCodec) == false {
            selectedVideoCodec = .automatic
        }

        if media.formatAvailability.isResolutionAvailable(selectedQuality, codec: selectedVideoCodec, audioLanguage: selectedAudioLanguage) == false {
            selectedQuality = QualityProfile.allCases.first {
                $0.isAudioOnly == selectedQuality.isAudioOnly && media.formatAvailability.isResolutionAvailable($0, codec: selectedVideoCodec, audioLanguage: selectedAudioLanguage)
            } ?? selectedQuality
        }

        guard selectedQuality.isVideoQuality else { return }

        if let container = media.formatAvailability.preferredContainer(
            for: selectedQuality, preferred: selectedContainer, codec: selectedVideoCodec, audioLanguage: selectedAudioLanguage
        ) {
            selectedContainer = container
        }
    }

    private func estimatedSizeBytes(for media: MediaInfo) -> Int64? {
        media.formatAvailability.estimatedDownloadSizeBytes(
            for: selectedQuality,
            container: selectedContainer,
            codec: selectedVideoCodec,
            audioLanguage: selectedAudioLanguage
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
        guard let path = item.temporaryDirectoryPath else { return }
        artifactCleaner.removeWorkspace(at: path, itemID: item.id)
    }

    private func clearLoadedMedia() {
        invalidateAnalysis()
        formatTask?.cancel()
        formatAnalysisID = UUID()
        media = nil
        selectedAudioLanguage = .original
        playlistEntries = []
        playlistMetadata = [:]
        failedPlaylistURLs = []
        lastAnalyzedURL = ""
        isAnalyzing = false
        isAnalyzingFormats = false
    }

    private func invalidateAnalysis() {
        analysisID = UUID()
        analyzeTask?.cancel()
        formatTask?.cancel()
        formatAnalysisID = UUID()
        isAnalyzing = false
        isAnalyzingFormats = false
    }

    private func isCurrentAnalysis(_ requestID: UUID, url: String) -> Bool {
        analysisID == requestID && parser.parse(inputURL)?.normalizedURL == url
    }
}
