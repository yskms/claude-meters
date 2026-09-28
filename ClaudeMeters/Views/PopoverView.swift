import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var l10n = LocalizationManager.shared

    var body: some View {
        VStack(spacing: 12) {
            Text("Claude Meters")
                .font(.headline)

            HStack(spacing: 32) {
                meterColumn(
                    title: l10n.string("meter.session"),
                    usage: displaySnapshot?.session
                )
                meterColumn(
                    title: l10n.string("meter.weekly"),
                    usage: displaySnapshot?.weekly
                )
            }

            Divider()

            statusLine

            Divider()

            Button(l10n.string("menu.settings")) {
                SettingsWindowController.shared.show(viewModel: viewModel)
            }
            .buttonStyle(.plain)

            Button(l10n.string("menu.quit")) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 260)
        // Our own labels already come from l10n.string(), but this keeps
        // any SwiftUI-native chrome (e.g. VoiceOver control descriptions)
        // consistent with the chosen language instead of the OS default.
        .environment(\.locale, l10n.locale ?? .current)
    }

    /// Suppresses the ring/percent display on fetch failure instead of
    /// leaving the previous successful snapshot's numbers on screen — the
    /// status line already switches to an error message, and showing a
    /// stale percentage alongside it reads as if that number is current.
    private var displaySnapshot: UsageSnapshot? {
        viewModel.lastFetchFailed ? nil : viewModel.snapshot
    }

    @ViewBuilder
    private var statusLine: some View {
        if let error = viewModel.lastError {
            Text(errorMessage(for: error))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else if let fetchedAt = viewModel.snapshot?.fetchedAt {
            Text(
                String(
                    format: l10n.string("status.last_updated"),
                    fetchedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: l10n.locale ?? .current))
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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
        case .invalidResponse, .network:
            return l10n.string("error.fetch_failed")
        }
    }
}
