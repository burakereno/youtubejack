import Foundation

public struct AudioLanguageSelection: Equatable, Hashable, Codable, Identifiable, Sendable {
    public let languageCode: String?
    public let isOriginal: Bool
    public var id: String { isOriginal ? "original" : languageCode ?? "original" }
    public static let original = AudioLanguageSelection(languageCode: nil, isOriginal: true)

    public init(languageCode: String?, isOriginal: Bool = false) {
        let valid = languageCode.flatMap { Self.isValidCode($0) ? $0 : nil }
        self.languageCode = valid
        self.isOriginal = isOriginal || valid == nil
    }

    public var title: String {
        guard let languageCode else { return L10n.string("Original") }
        let name = AudioLanguage.localizedName(for: languageCode)
        return isOriginal ? L10n.string("Original (%@)", defaultValue: "Original (\(name))") : name
    }

    public var formatFilter: String {
        languageCode.map { "[language=\($0)]" } ?? ""
    }

    public func resolved(in availability: MediaFormatAvailability) -> Self {
        guard isOriginal, languageCode == nil else { return self }
        return Self(languageCode: availability.originalAudioLanguageCode, isOriginal: true)
    }

    public func matches(_ format: MediaFormat) -> Bool {
        guard let languageCode else { return true }
        return format.language?.lowercased() == languageCode.lowercased()
    }

    public static func isValidCode(_ code: String) -> Bool {
        code.range(of: "^[A-Za-z]{2,3}([_-][A-Za-z0-9]{1,8})*$", options: .regularExpression) != nil
    }
}

public struct AudioLanguage: Identifiable, Equatable, Sendable {
    public let code: String
    public let isOriginal: Bool
    public let isAutomatic: Bool
    public init(code: String, isOriginal: Bool, isAutomatic: Bool) {
        self.code = code
        self.isOriginal = isOriginal
        self.isAutomatic = isAutomatic
    }
    public var id: String { code }
    public var name: String { Self.localizedName(for: code) }
    public var selection: AudioLanguageSelection { AudioLanguageSelection(languageCode: code) }
    public var title: String {
        isAutomatic ? L10n.string("%@ · Automatic dubbing", defaultValue: "\(name) · Automatic dubbing") : name
    }

    public static func localizedName(for code: String) -> String {
        let descriptive = code.hasSuffix("-desc")
        let base = descriptive ? String(code.dropLast(5)) : code
        let name = L10n.locale.localizedString(forIdentifier: base) ?? base
        return descriptive ? L10n.string("%@ (audio description)", defaultValue: "\(name) (audio description)") : name
    }
}
