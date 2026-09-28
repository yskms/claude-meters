import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en
    case ja

    var id: String { rawValue }
}

/// Lets the user override the OS language from in-app Settings instead of
/// only following `NSLocalizedString`'s default system-locale resolution.
/// Views that display localized text observe `shared` as an
/// `@ObservedObject` so they redraw immediately when `language` changes,
/// without requiring an app relaunch.
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private static let storageKey = "appLanguage"

    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageKey)
        language = AppLanguage(rawValue: saved ?? "") ?? .system
    }

    /// `nil` means "follow the system locale", matching `Locale.current`'s
    /// default behavior in date formatters. When overridden, carries over
    /// the user's region code (e.g. `_JP`) so region-default formatting
    /// (date order, calendar) isn't lost when only the display language is
    /// overridden. This is only the region's *default* conventions — a
    /// manually-toggled system preference such as "24-Hour Time" isn't part
    /// of a region code and is not reproduced here.
    var locale: Locale? {
        guard language != .system else { return nil }
        guard let region = Locale.current.region?.identifier else {
            return Locale(identifier: language.rawValue)
        }
        return Locale(identifier: "\(language.rawValue)_\(region)")
    }

    private func bundle(for language: AppLanguage) -> Bundle {
        guard language != .system,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let overrideBundle = Bundle(path: path) else {
            return .main
        }
        return overrideBundle
    }

    /// - Parameter language: Pass this explicitly when resolving a value
    ///   received from `$language`'s Combine publisher — `@Published`
    ///   sends the new value from `willSet`, before `self.language` is
    ///   actually updated, so reading `self.language` inside a `sink`
    ///   still observes the previous language.
    func string(_ key: String, for language: AppLanguage? = nil) -> String {
        bundle(for: language ?? self.language).localizedString(forKey: key, value: nil, table: nil)
    }
}
