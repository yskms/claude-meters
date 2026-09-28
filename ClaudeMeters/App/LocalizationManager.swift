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
    /// default behavior in date formatters. When overridden, keeps the
    /// user's region (e.g. `_JP`) so region-dependent formatting like the
    /// 24-hour clock survives switching only the display language.
    var locale: Locale? {
        guard language != .system else { return nil }
        guard let region = Locale.current.region?.identifier else {
            return Locale(identifier: language.rawValue)
        }
        return Locale(identifier: "\(language.rawValue)_\(region)")
    }

    private var bundle: Bundle {
        guard language != .system,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let overrideBundle = Bundle(path: path) else {
            return .main
        }
        return overrideBundle
    }

    func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
