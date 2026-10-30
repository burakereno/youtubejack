import Foundation

public struct MediaFormat: Equatable, Sendable {
    public let id: String
    public let ext: String?
    public let height: Int?
    public let vcodec: String?
    public let acodec: String?
    public let filesize: Int64?
    public let filesizeApprox: Int64?
    public let language: String?
    public let languagePreference: Int?
    public let formatNote: String?

    public init(
        id: String,
        ext: String?,
        height: Int?,
        vcodec: String?,
        acodec: String?,
        filesize: Int64? = nil,
        filesizeApprox: Int64? = nil,
        language: String? = nil,
        languagePreference: Int? = nil,
        formatNote: String? = nil
    ) {
        self.id = id
        self.ext = ext
        self.height = height
        self.vcodec = vcodec
        self.acodec = acodec
        self.filesize = filesize
        self.filesizeApprox = filesizeApprox
        self.language = language
        self.languagePreference = languagePreference
        self.formatNote = formatNote
    }

    public var sizeBytes: Int64? {
        filesize ?? filesizeApprox
    }

    var hasVideo: Bool {
        guard let vcodec, vcodec != "none" else { return false }
        return height != nil
    }

    var hasAudio: Bool {
        guard let acodec else { return false }
        return acodec != "none"
    }
}

public struct MediaFormatAvailability: Equatable, Sendable {
    public let isKnown: Bool
    public let formats: [MediaFormat]
    private let sourceLanguageCode: String?

    public init(isKnown: Bool, formats: [MediaFormat], sourceLanguageCode: String? = nil) {
        self.isKnown = isKnown
        self.formats = formats
        self.sourceLanguageCode = sourceLanguageCode
    }

    public static let unknown = MediaFormatAvailability(isKnown: false, formats: [])

    public var originalAudioLanguageCode: String? {
        let audio = formats.filter { $0.hasAudio && $0.language.map(AudioLanguageSelection.isValidCode) == true }
        if let original = audio.first(where: { ($0.languagePreference ?? -1) >= 10 || $0.formatNote?.localizedCaseInsensitiveContains("original") == true })?.language {
            return original
        }
        if let sourceLanguageCode, audio.contains(where: { $0.language == sourceLanguageCode }) { return sourceLanguageCode }
        let codes = Set(audio.compactMap(\.language))
        return codes.count == 1 ? codes.first : nil
    }

    public var audioLanguages: [AudioLanguage] {
        var groups: [String: [MediaFormat]] = [:]
        for format in formats where format.hasAudio {
            guard let code = format.language, AudioLanguageSelection.isValidCode(code) else { continue }
            groups[code, default: []].append(format)
        }
        let originalCode = originalAudioLanguageCode
        return groups.map { code, formats in
            AudioLanguage(code: code, isOriginal: code == originalCode, isAutomatic: formats.allSatisfy {
                let note = $0.formatNote?.lowercased() ?? ""
                return note.contains("auto-dubbed") || note.contains("auto dubbed") || note.contains("automatic dub")
            })
        }.sorted {
            func priority(_ code: String) -> Int { code == "tr" ? 0 : code == "en" ? 1 : 2 }
            let left = priority($0.code), right = priority($1.code)
            return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left < right
        }
    }

    public var maxVideoHeight: Int? {
        formats.compactMap(\.height).max()
    }

    public func maxVideoHeight(codec: VideoCodecPreference, audioLanguage: AudioLanguageSelection = .original) -> Int? {
        let resolved = audioLanguage.resolved(in: self)
        return formats
            .filter { format in
                guard format.hasVideo, codec.matches(format.vcodec),
                      let ext = format.ext, let container = DownloadContainer(rawValue: ext.lowercased())
                else { return false }
                return codec.allows(container) && hasAudio(container: container, language: audioLanguage)
                    && (format.hasAudio == false || resolved.matches(format))
            }
            .compactMap(\.height)
            .max()
    }

    public func isResolutionAvailable(_ profile: QualityProfile, codec: VideoCodecPreference = .automatic, audioLanguage: AudioLanguageSelection = .original) -> Bool {
        guard isKnown else { return true }

        if profile == .best {
            return DownloadContainer.allCases.contains { isContainerAvailable($0, for: profile, codec: codec, audioLanguage: audioLanguage) }
        }

        if profile == .audioM4A {
            return bestAudioFormat(language: audioLanguage) != nil
        }

        guard profile.height != nil else { return true }
        return DownloadContainer.allCases.contains { isContainerAvailable($0, for: profile, codec: codec, audioLanguage: audioLanguage) }
    }

    public func isContainerAvailable(
        _ container: DownloadContainer,
        for profile: QualityProfile,
        codec: VideoCodecPreference = .automatic,
        audioLanguage: AudioLanguageSelection = .original
    ) -> Bool {
        guard profile.isVideoQuality else { return false }
        guard codec.allows(container) else { return false }
        guard isKnown else { return true }

        return bestVideoFormat(container: container, profile: profile, codec: codec, audioLanguage: audioLanguage) != nil && hasAudio(container: container, language: audioLanguage)
    }

    public func preferredContainer(
        for profile: QualityProfile,
        preferred: DownloadContainer,
        codec: VideoCodecPreference = .automatic,
        audioLanguage: AudioLanguageSelection = .original
    ) -> DownloadContainer? {
        if isContainerAvailable(preferred, for: profile, codec: codec, audioLanguage: audioLanguage) {
            return preferred
        }
        return DownloadContainer.allCases.first { isContainerAvailable($0, for: profile, codec: codec, audioLanguage: audioLanguage) }
    }

    public func estimatedDownloadSizeBytes(
        for profile: QualityProfile,
        container: DownloadContainer,
        codec: VideoCodecPreference = .automatic,
        audioLanguage: AudioLanguageSelection = .original
    ) -> Int64? {
        guard isKnown else { return nil }

        if profile.isAudioOnly {
            return bestAudioFormat(language: audioLanguage)?.sizeBytes
        }

        guard let videoFormat = bestVideoFormat(container: container, profile: profile, codec: codec, audioLanguage: audioLanguage) else {
            return nil
        }

        var total: Int64 = 0
        var foundSize = false

        if let videoSize = videoFormat.sizeBytes {
            total += videoSize
            foundSize = true
        }

        if videoFormat.hasAudio == false, let audioSize = bestAudioFormat(container: container, language: audioLanguage)?.sizeBytes {
            total += audioSize
            foundSize = true
        }

        return foundSize ? total : nil
    }

    private func matchesResolutionBand(_ value: Int?, profile: QualityProfile) -> Bool {
        guard let value, let upper = profile.height else { return false }
        if let lower = profile.lowerExclusiveHeight {
            return value > lower && value <= upper
        }
        return value <= upper
    }

    private func hasAudio(container: DownloadContainer, language: AudioLanguageSelection) -> Bool {
        bestAudioFormat(container: container, language: language) != nil
    }

    private func bestVideoFormat(container: DownloadContainer, profile: QualityProfile, codec: VideoCodecPreference, audioLanguage: AudioLanguageSelection) -> MediaFormat? {
        let resolved = audioLanguage.resolved(in: self)
        return formats
            .filter { format in
                guard format.hasVideo, normalized(format.ext) == container.rawValue else { return false }
                guard codec.matches(format.vcodec) else { return false }
                // A combined stream carries its own audio; it cannot satisfy another language.
                if format.hasAudio, resolved.matches(format) == false { return false }
                if profile == .best {
                    return true
                }
                return matchesResolutionBand(format.height, profile: profile)
            }
            .max { lhs, rhs in
                isLowerRanked(lhs, than: rhs)
            }
    }

    private func bestAudioFormat(container: DownloadContainer? = nil, language: AudioLanguageSelection = .original) -> MediaFormat? {
        let resolved = language.resolved(in: self)
        return formats
            .filter { format in
                guard format.hasAudio else { return false }
                guard resolved.matches(format) else { return false }
                if let container {
                    return isAudioFormat(format, compatibleWith: container)
                }
                return true
            }
            .max { lhs, rhs in
                isLowerRanked(lhs, than: rhs)
            }
    }

    private func isAudioFormat(_ format: MediaFormat, compatibleWith container: DownloadContainer) -> Bool {
        let ext = normalized(format.ext)
        let acodec = normalized(format.acodec)

        switch container {
        case .mp4:
            return ext == "m4a" || ext == "mp4" || acodec.hasPrefix("mp4a") || acodec.hasPrefix("aac")
        case .webm:
            return ext == "webm" || acodec.hasPrefix("opus") || acodec.hasPrefix("vorbis")
        }
    }

    private func isLowerRanked(_ lhs: MediaFormat, than rhs: MediaFormat) -> Bool {
        let leftHeight = lhs.height ?? 0
        let rightHeight = rhs.height ?? 0
        if leftHeight != rightHeight {
            return leftHeight < rightHeight
        }

        let leftSize = lhs.sizeBytes ?? 0
        let rightSize = rhs.sizeBytes ?? 0
        if leftSize != rightSize {
            return leftSize < rightSize
        }

        return lhs.id < rhs.id
    }

    private func normalized(_ value: String?) -> String {
        value?.lowercased() ?? ""
    }
}
