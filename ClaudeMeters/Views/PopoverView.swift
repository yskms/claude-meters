import SwiftUI
import AppKit

struct PopoverView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Claude Meters")
                .font(.headline)

            HStack(spacing: 32) {
                meterColumn(
                    title: NSLocalizedString("meter.session", comment: ""),
                    usage: displaySnapshot?.session
                )
                meterColumn(
                    title: NSLocalizedString("meter.weekly", comment: ""),
                    usage: displaySnapshot?.weekly
                )
            }

            Divider()

            statusLine

            Divider()

            Button(NSLocalizedString("menu.settings", comment: "")) {
                SettingsWindowController.shared.show(viewModel: viewModel)
            }
            .buttonStyle(.plain)

            Button(NSLocalizedString("menu.quit", comment: "")) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 260)
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
                    format: NSLocalizedString("status.last_updated", comment: ""),
                    fetchedAt.formatted(date: .omitted, time: .shortened)
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
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func errorMessage(for error: UsageProviderError) -> String {
        switch error {
        case .credentialUnavailable:
            return NSLocalizedString("error.credential_unavailable", comment: "")
        case .invalidResponse, .network:
            return NSLocalizedString("error.fetch_failed", comment: "")
        }
    }
}
