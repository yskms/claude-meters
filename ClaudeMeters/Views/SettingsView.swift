import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Toggle(NSLocalizedString("settings.launch_at_login", comment: ""), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    updateLaunchAtLogin(newValue)
                }

            // 30 seconds is intentionally not offered: the usage endpoint is
            // undocumented and has known 429s under frequent polling, and no
            // safe minimum interval has been confirmed yet (see
            // docs/REQUIREMENTS.md, section 8/11).
            Picker(NSLocalizedString("settings.refresh_interval", comment: ""), selection: $viewModel.refreshInterval) {
                Text(NSLocalizedString("interval.1m", comment: "")).tag(60.0)
                Text(NSLocalizedString("interval.5m", comment: "")).tag(300.0)
            }
        }
        .padding()
        .frame(width: 320)
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
