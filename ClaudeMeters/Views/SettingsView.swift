import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var updateChecker: UpdateChecker
    @ObservedObject private var l10n = LocalizationManager.shared
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Toggle(l10n.string("settings.launch_at_login"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    updateLaunchAtLogin(newValue)
                }

            // Must match UsageViewModel.allowedRefreshIntervals. Nothing
            // shorter than 2 minutes is offered: at 1 minute the undocumented
            // usage endpoint answered every third request with 429 and
            // still updated only about every 2 minutes (see
            // docs/REQUIREMENTS.md, section 8/11).
            Picker(l10n.string("settings.refresh_interval"), selection: $viewModel.refreshInterval) {
                Text(l10n.string("interval.2m")).tag(120.0)
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

            // The result text and the button swap in place rather than
            // appearing on a new line; the window re-fits its content when
            // `updateChecker.state` changes (see SettingsWindowController).
            LabeledContent(String(format: l10n.string("settings.version"), updateChecker.currentVersion)) {
                HStack {
                    if let status = updateStatusText {
                        Text(status)
                            .foregroundColor(.secondary)
                    }
                    updateButton
                }
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

    private var updateStatusText: String? {
        switch updateChecker.state {
        case .idle:
            return nil
        case .checking:
            return l10n.string("update.checking")
        case .upToDate:
            return l10n.string("update.up_to_date")
        case .updateAvailable(let version):
            return String(format: l10n.string("update.available"), version)
        case .failed:
            return l10n.string("update.failed")
        }
    }

    @ViewBuilder
    private var updateButton: some View {
        switch updateChecker.state {
        case .updateAvailable:
            // Opens the Releases page; installing stays a manual DMG download.
            Button(l10n.string("update.download")) {
                NSWorkspace.shared.open(UpdateChecker.releasesPageURL)
            }
        case .upToDate:
            // Nothing left to do. The button returns the next time the
            // window is shown (see UpdateChecker.resetIfFinished).
            EmptyView()
        case .idle, .checking, .failed:
            Button(l10n.string("settings.check_for_updates")) {
                Task { await updateChecker.check() }
            }
            .disabled(updateChecker.state == .checking)
        }
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
