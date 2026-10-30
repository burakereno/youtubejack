import Foundation

struct YTDLPInfo: Decodable {
    let id: String?
    let title: String?
    let webpageURL: String?
    let originalURL: String?
    let uploader: String?
    let channel: String?
    let duration: Double?
    let thumbnail: String?
    let entries: [YTDLPEntry]?
    let formats: [YTDLPFormat]?
    let subtitles: [String: [YTDLPSubtitle]]?
    let automaticCaptions: [String: [YTDLPSubtitle]]?
    let language: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case webpageURL = "webpage_url"
        case originalURL = "original_url"
        case uploader
        case channel
        case duration
        case thumbnail
        case entries
        case formats
        case subtitles
        case automaticCaptions = "automatic_captions"
        case language
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeStringIfPresent(forKey: .id)
        title = container.decodeStringIfPresent(forKey: .title)
        webpageURL = container.decodeStringIfPresent(forKey: .webpageURL)
        originalURL = container.decodeStringIfPresent(forKey: .originalURL)
        uploader = container.decodeStringIfPresent(forKey: .uploader)
        channel = container.decodeStringIfPresent(forKey: .channel)
        duration = container.decodeDoubleIfPresent(forKey: .duration)
        thumbnail = container.decodeStringIfPresent(forKey: .thumbnail)
        entries = try container.decodeIfPresent([YTDLPEntry].self, forKey: .entries)
        formats = try container.decodeIfPresent([YTDLPFormat].self, forKey: .formats)
        subtitles = try container.decodeIfPresent([String: [YTDLPSubtitle]].self, forKey: .subtitles)
        automaticCaptions = try container.decodeIfPresent([String: [YTDLPSubtitle]].self, forKey: .automaticCaptions)
        language = container.decodeStringIfPresent(forKey: .language)
    }

    var subtitleAvailability: SubtitleAvailability {
        let manual = Set(validSubtitleCodes(subtitles).map(SubtitleLanguage.canonicalCode))
        let automatic = Set(validSubtitleCodes(automaticCaptions).map(SubtitleLanguage.canonicalCode))
        return SubtitleAvailability(isKnown: true, languages: manual.union(automatic).map {
            SubtitleLanguage(code: $0, hasManual: manual.contains($0), hasAutomatic: automatic.contains($0))
        })
    }

    func selectedSubtitles(for options: SubtitleOptions) -> [(code: String, trackCode: String, isAutomatic: Bool)] {
        let manual = validSubtitleCodes(subtitles)
        let automatic = validSubtitleCodes(automaticCaptions)
        return options.languageCodes.compactMap { code in
            let publisher = manual.filter { SubtitleLanguage.canonicalCode(for: $0) == code }
                .sorted { left, right in left == right ? false : left == code ? true : right == code ? false : left < right }.first
            if let publisher { return (code, publisher, false) }
            guard options.includesAutomatic else { return nil }
            let generated = automatic.filter { SubtitleLanguage.canonicalCode(for: $0) == code }
                .sorted { left, right in left.hasSuffix("-orig") != right.hasSuffix("-orig") ? left.hasSuffix("-orig") : left < right }.first
            return generated.map { (code, $0, true) }
        }
    }

    private func validSubtitleCodes(_ tracks: [String: [YTDLPSubtitle]]?) -> [String] {
        (tracks ?? [:]).filter { SubtitleLanguage.isValidCode($0.key) && $0.value.isEmpty == false }.map(\.key)
    }
}

struct YTDLPSubtitle: Decodable {
    let ext: String?
    let name: String?
}

struct YTDLPFormat: Decodable {
    let formatID: String?
    let ext: String?
    let height: Int?
    let vcodec: String?
    let acodec: String?
    let filesize: Int64?
    let filesizeApprox: Int64?
    let language: String?
    let languagePreference: Int?
    let formatNote: String?

    enum CodingKeys: String, CodingKey {
        case formatID = "format_id"
        case ext
        case height
        case vcodec
        case acodec
        case filesize
        case filesizeApprox = "filesize_approx"
        case language
        case languagePreference = "language_preference"
        case formatNote = "format_note"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatID = container.decodeStringIfPresent(forKey: .formatID)
        ext = container.decodeStringIfPresent(forKey: .ext)
        height = container.decodeIntIfPresent(forKey: .height)
        vcodec = container.decodeStringIfPresent(forKey: .vcodec)
        acodec = container.decodeStringIfPresent(forKey: .acodec)
        filesize = container.decodeInt64IfPresent(forKey: .filesize)
        filesizeApprox = container.decodeInt64IfPresent(forKey: .filesizeApprox)
        language = container.decodeStringIfPresent(forKey: .language)
        languagePreference = container.decodeIntIfPresent(forKey: .languagePreference)
        formatNote = container.decodeStringIfPresent(forKey: .formatNote)
    }
}

struct YTDLPEntry: Decodable {
    let id: String?
    let title: String?
    let url: String?
    let webpageURL: String?
    let uploader: String?
    let channel: String?
    let duration: Double?
    let thumbnail: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case webpageURL = "webpage_url"
        case uploader
        case channel
        case duration
        case thumbnail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeStringIfPresent(forKey: .id)
        title = container.decodeStringIfPresent(forKey: .title)
        url = container.decodeStringIfPresent(forKey: .url)
        webpageURL = container.decodeStringIfPresent(forKey: .webpageURL)
        uploader = container.decodeStringIfPresent(forKey: .uploader)
        channel = container.decodeStringIfPresent(forKey: .channel)
        duration = container.decodeDoubleIfPresent(forKey: .duration)
        thumbnail = container.decodeStringIfPresent(forKey: .thumbnail)
    }
}

extension KeyedDecodingContainer {
    func decodeStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func decodeDoubleIfPresent(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    func decodeIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }

    func decodeInt64IfPresent(forKey key: Key) -> Int64? {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int64(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int64(value)
        }
        return nil
    }
}
