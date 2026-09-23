import Foundation

public struct MediaFormat: Equatable, Sendable {
    public let id: String
    public let ext: String?
    public let height: Int?
    public let vcodec: String?
    public let acodec: String?
    public let filesize: Int64?
    public let filesizeApprox: Int64?

    public init(
        id: String,
        ext: String?,
        height: Int?,
        vcodec: String?,
        acodec: String?,
        filesize: Int64? = nil,
        filesizeApprox: Int64? = nil
    ) {
        self.id = id
        self.ext = ext
        self.height = height
        self.vcodec = vcodec
        self.acodec = acodec
        self.filesize = filesize
        self.filesizeApprox = filesizeApprox
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

    public init(isKnown: Bool, formats: [MediaFormat]) {
        self.isKnown = isKnown
        self.formats = formats
    }

    public static let unknown = MediaFormatAvailability(isKnown: false, formats: [])

    public var maxVideoHeight: Int? {
        formats.compactMap(\.height).max()
    }

    public func maxVideoHeight(codec: VideoCodecPreference) -> Int? {
        formats
            .filter { format in
                guard format.hasVideo, codec.matches(format.vcodec),
                      let ext = format.ext, let container = DownloadContainer(rawValue: ext.lowercased())
                else { return false }
                return codec.allows(container) && hasAudio(container: container)
            }
            .compactMap(\.height)
            .max()
    }

    public func isResolutionAvailable(_ profile: QualityProfile, codec: VideoCodecPreference = .automatic) -> Bool {
        guard isKnown else { return true }

        if profile == .best {
            return DownloadContainer.allCases.contains { isContainerAvailable($0, for: profile, codec: codec) }
        }

        if profile == .audioM4A {
            return formats.contains(where: \.hasAudio)
        }

        guard profile.height != nil else { return true }
        return DownloadContainer.allCases.contains { isContainerAvailable($0, for: profile, codec: codec) }
    }

    public func isContainerAvailable(
        _ container: DownloadContainer,
        for profile: QualityProfile,
        codec: VideoCodecPreference = .automatic
    ) -> Bool {
        guard profile.isVideoQuality else { return false }
        guard codec.allows(container) else { return false }
        guard isKnown else { return true }

        return hasVideo(container: container, profile: profile, codec: codec) && hasAudio(container: container)
    }

    public func preferredContainer(
        for profile: QualityProfile,
        preferred: DownloadContainer,
        codec: VideoCodecPreference = .automatic
    ) -> DownloadContainer? {
        if isContainerAvailable(preferred, for: profile, codec: codec) {
            return preferred
        }
        return DownloadContainer.allCases.first { isContainerAvailable($0, for: profile, codec: codec) }
    }

    public func estimatedDownloadSizeBytes(
        for profile: QualityProfile,
        container: DownloadContainer,
        codec: VideoCodecPreference = .automatic
    ) -> Int64? {
        guard isKnown else { return nil }

        if profile.isAudioOnly {
            return bestAudioFormat()?.sizeBytes
        }

        guard let videoFormat = bestVideoFormat(container: container, profile: profile, codec: codec) else {
            return nil
        }

        var total: Int64 = 0
        var foundSize = false

        if let videoSize = videoFormat.sizeBytes {
            total += videoSize
            foundSize = true
        }

        if videoFormat.hasAudio == false, let audioSize = bestAudioFormat(container: container)?.sizeBytes {
            total += audioSize
            foundSize = true
        }

        return foundSize ? total : nil
    }

    private func hasVideo(container: DownloadContainer, profile: QualityProfile, codec: VideoCodecPreference) -> Bool {
        bestVideoFormat(container: container, profile: profile, codec: codec) != nil
    }

    private func matchesResolutionBand(_ value: Int?, profile: QualityProfile) -> Bool {
        guard let value, let upper = profile.height else { return false }
        if let lower = profile.lowerExclusiveHeight {
            return value > lower && value <= upper
        }
        return value <= upper
    }

    private func hasAudio(container: DownloadContainer) -> Bool {
        bestAudioFormat(container: container) != nil
    }

    private func bestVideoFormat(container: DownloadContainer, profile: QualityProfile, codec: VideoCodecPreference) -> MediaFormat? {
        formats
            .filter { format in
                guard format.hasVideo, normalized(format.ext) == container.rawValue else { return false }
                guard codec.matches(format.vcodec) else { return false }
                if profile == .best {
                    return true
                }
                return matchesResolutionBand(format.height, profile: profile)
            }
            .max { lhs, rhs in
                isLowerRanked(lhs, than: rhs)
            }
    }

    private func bestAudioFormat(container: DownloadContainer? = nil) -> MediaFormat? {
        formats
            .filter { format in
                guard format.hasAudio else { return false }
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
