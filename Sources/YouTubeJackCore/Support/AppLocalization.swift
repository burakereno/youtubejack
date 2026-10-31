import Foundation
import Observation

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case turkish = "tr"

    public var id: String { rawValue }
    public var nativeName: String { self == .english ? "English" : "Türkçe" }
    public var locale: Locale { Locale(identifier: rawValue) }
}

/// UserDefaults and ObservationRegistrar provide synchronized access. No mutable
/// state is held outside those facilities, so service errors can read the language
/// safely while SwiftUI observes the same preference on the main thread.
@Observable
public final class AppLanguageSettings: @unchecked Sendable {
    public static let preferenceKey = "appLanguage"
    public static let shared = AppLanguageSettings()
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var language: AppLanguage {
        get {
            access(keyPath: \.language)
            return defaults.string(forKey: Self.preferenceKey).flatMap(AppLanguage.init(rawValue:)) ?? .english
        }
        set {
            withMutation(keyPath: \.language) {
                defaults.set(newValue.rawValue, forKey: Self.preferenceKey)
                applySystemLanguage(newValue)
            }
        }
    }

    public func applySystemLanguageAtLaunch() {
        applySystemLanguage(language)
    }

    private func applySystemLanguage(_ language: AppLanguage) {
        // This is the current application's preference domain, never the global
        // macOS language setting. AppKit reads it when creating system menus.
        defaults.set([language.rawValue], forKey: "AppleLanguages")
    }
}

public enum L10n {
    public static var locale: Locale { AppLanguageSettings.shared.language.locale }

    private static let resourceBundle: Bundle = {
        // SwiftPM's generated accessor assumes the resource bundle sits beside
        // the executable product. Native app bundles keep it in Resources.
        if let url = Bundle.main.url(forResource: "YouTubeJack_YouTubeJackCore", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return .module
    }()

    /// Resolve explicitly from the selected language bundle, rather than the
    /// system's preferred localization. Reading the preference also registers
    /// SwiftUI observation, including text produced by core model properties.
    public static func string(_ value: String.LocalizationValue, language: AppLanguage? = nil) -> String {
        let selected = language ?? AppLanguageSettings.shared.language
        return String(localized: value, bundle: bundle(for: selected), locale: selected.locale)
    }

    public static func string(_ key: StaticString, defaultValue: String.LocalizationValue, language: AppLanguage? = nil) -> String {
        let selected = language ?? AppLanguageSettings.shared.language
        return String(localized: key, defaultValue: defaultValue, bundle: bundle(for: selected), locale: selected.locale)
    }

    public static func bundle(for language: AppLanguage) -> Bundle {
        guard let url = resourceBundle.url(forResource: language.rawValue, withExtension: "lproj"),
              let bundle = Bundle(url: url) else { return resourceBundle }
        return bundle
    }
}
