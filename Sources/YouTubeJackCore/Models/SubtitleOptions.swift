import Foundation

public enum SubtitleDelivery: String, CaseIterable, Codable, Identifiable, Sendable {
    case embedded
    case separateFile
    public var id: String { rawValue }
    public var title: String { self == .embedded ? "Videoya göm" : "Ayrı dosya" }
}

public enum SubtitleFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case srt
    case vtt
    public var id: String { rawValue }
    public var title: String { rawValue.uppercased() }
}

public struct SubtitleOptions: Equatable, Codable, Sendable {
    public var isEnabled: Bool
    public var languageCodes: [String]
    public var includesAutomatic: Bool
    public var delivery: SubtitleDelivery
    public var format: SubtitleFormat

    public init(
        isEnabled: Bool = false,
        languageCodes: [String] = ["tr"],
        includesAutomatic: Bool = true,
        delivery: SubtitleDelivery = .embedded,
        format: SubtitleFormat = .srt
    ) {
        self.isEnabled = isEnabled
        self.languageCodes = Array(Set(languageCodes.filter(SubtitleLanguage.isValidCode))).sorted()
        self.includesAutomatic = includesAutomatic
        self.delivery = delivery
        self.format = format
    }

    public var languageSelector: String {
        languageCodes.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: ",")
    }

    public var summary: String {
        languageCodes.map { SubtitleLanguage.localizedName(for: $0) }.joined(separator: ", ")
    }
}

public struct SubtitleLanguage: Identifiable, Equatable, Sendable {
    public let code: String
    public let name: String
    public let hasManual: Bool
    public let hasAutomatic: Bool
    public var id: String { code }

    public init(code: String, name: String? = nil, hasManual: Bool, hasAutomatic: Bool) {
        self.code = code
        self.name = name ?? Self.localizedName(for: code)
        self.hasManual = hasManual
        self.hasAutomatic = hasAutomatic
    }

    public static func localizedName(for code: String) -> String {
        let base = code.replacingOccurrences(of: "-orig", with: "")
        let name = Locale(identifier: "tr").localizedString(forIdentifier: base) ?? base
        return code.hasSuffix("-orig") ? "\(name) (orijinal)" : name
    }

    public static func canonicalCode(for code: String) -> String {
        let base = code.replacingOccurrences(of: "-orig", with: "")
        // YouTube can suffix publisher tracks with an opaque caption-track ID.
        let parts = base.split(separator: "-")
        if parts.dropFirst().contains(where: { $0.count > 8 }) {
            return String(parts.first ?? Substring(base))
        }
        return base
    }

    public static func isValidCode(_ code: String) -> Bool {
        code != "live_chat" && code.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil
    }

    public var sourceTitle: String {
        hasManual ? "Yayıncı" : "Otomatik / çeviri"
    }

    /// ffmpeg/MP4 use ISO 639-2 codes for track language metadata.
    public var metadataLanguage: String {
        let base = String(code.split(separator: "-").first ?? Substring(code))
        return ["tr": "tur", "en": "eng", "de": "deu", "fr": "fra", "es": "spa",
                "it": "ita", "pt": "por", "ru": "rus", "ja": "jpn", "ko": "kor",
                "zh": "zho", "ar": "ara", "nl": "nld", "pl": "pol", "uk": "ukr",
                "hi": "hin", "el": "ell", "sv": "swe", "da": "dan", "fi": "fin",
                "no": "nor", "cs": "ces", "ro": "ron", "hu": "hun", "id": "ind",
                "vi": "vie", "th": "tha", "he": "heb", "fa": "fas"][base] ?? "und"
    }
}

public struct SubtitleAvailability: Equatable, Sendable {
    public let isKnown: Bool
    public let languages: [SubtitleLanguage]
    public static let unknown = SubtitleAvailability(isKnown: false, languages: [])

    public init(isKnown: Bool, languages: [SubtitleLanguage]) {
        self.isKnown = isKnown
        self.languages = languages.sorted {
            func priority(_ code: String) -> Int { code == "tr" ? 0 : code == "en" ? 1 : 2 }
            let left = priority($0.code)
            let right = priority($1.code)
            return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left < right
        }
    }
}
