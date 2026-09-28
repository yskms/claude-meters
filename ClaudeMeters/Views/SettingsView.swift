import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var l10n = LocalizationManager.shared
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Toggle(l10n.string("settings.launch_at_login"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    updateLaunchAtLogin(newValue)
                }

            // 30 seconds is intentionally not offered: the usage endpoint is
            // undocumented and has known 429s under frequent polling, and no
            // safe minimum interval has been confirmed yet (see
            // docs/REQUIREMENTS.md, section 8/11).
            Picker(l10n.string("settings.refresh_interval"), selection: $viewModel.refreshInterval) {
                Text(l10n.string("interval.1m")).tag(60.0)
                Text(l10n.string("interval.5m")).tag(300.0)
            }

            // "English"/"日本語"/etc. are the languages' own native names, so
            // they are shown as-is rather than run through localization —
            // the point is that they stay recognizable no matter which
            // language the UI is currently displaying in.
            Picker(l10n.string("settings.language"), selection: $l10n.language) {
                Text(l10n.string("language.system")).tag(AppLanguage.system)
                Text("English").tag(AppLanguage.en)
                Text("日本語").tag(AppLanguage.ja)
                Text("한국어").tag(AppLanguage.ko)
                Text("Deutsch").tag(AppLanguage.de)
                Text("Français").tag(AppLanguage.fr)
                Text("Italiano").tag(AppLanguage.it)
                Text("Português (Brasil)").tag(AppLanguage.ptBR)
                Text("Español").tag(AppLanguage.es)
            }
        }
        .padding()
        // A fixed width clipped longer translations (Italian/Portuguese/
        // Spanish labels like "Intervalo de actualización" didn't fit in
        // 320pt). `minWidth` keeps the original size for short-label
        // languages while letting the window's fitting size (see
        // SettingsWindowController) grow for longer ones.
        .frame(minWidth: 320)
        .environment(\.locale, l10n.locale ?? .current)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = !enabled
        }
    }
}
