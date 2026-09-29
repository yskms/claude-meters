import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var l10n = LocalizationManager.shared

    var body: some View {
        let state = viewModel.displayState()
        VStack(spacing: 12) {
            Text("Claude Meters")
                .font(.headline)

            HStack(spacing: 32) {
                meterColumn(
                    title: l10n.string("meter.session"),
                    usage: state.session
                )
                meterColumn(
                    title: l10n.string("meter.weekly"),
                    usage: state.weekly
                )
            }

            Divider()

            statusLine(state)

            Divider()

            menuButton(l10n.string("menu.settings")) {
                SettingsWindowController.shared.show(viewModel: viewModel)
            }

            menuButton(l10n.string("menu.quit")) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 260)
        // Our own labels already come from l10n.string(), but this keeps
        // any SwiftUI-native chrome (e.g. VoiceOver control descriptions)
        // consistent with the chosen language instead of the OS default.
        .environment(\.locale, l10n.locale ?? .current)
    }

    @ViewBuilder
    private func statusLine(_ state: UsageDisplayState) -> some View {
        if let staleSince = state.staleSince {
            statusText(String(format: l10n.string("status.stale_values"), timeString(staleSince)))
        } else if let error = viewModel.lastError {
            statusText(errorMessage(for: error))
        } else if let fetchedAt = viewModel.snapshot?.fetchedAt {
            statusText(String(format: l10n.string("status.last_updated"), timeString(fetchedAt)))
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private func timeString(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: l10n.locale ?? .current))
    }

    /// Expands the button's hit area to the full row instead of just the
    /// text glyphs, which `.buttonStyle(.plain)` alone leaves too narrow
    /// to click comfortably.
    private func menuButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func meterColumn(title: String, usage: MeterUsage?) -> some View {
        VStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            UsageRingView(percent: usage?.percentUsed, diameter: 44)
            if let resetsAt = usage?.resetsAt {
                Text(resetLabel(for: resetsAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func resetLabel(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        if let locale = l10n.locale {
            formatter.locale = locale
        }
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func errorMessage(for error: UsageProviderError) -> String {
        switch error {
        case .credentialUnavailable:
            return l10n.string("error.credential_unavailable")
        case .unexpectedStatus, .invalidResponse, .network:
            return l10n.string("error.fetch_failed")
        }
    }
}
