import SwiftUI
import AppKit

// MenuBarExtra's `label` does not reliably host a live nested SwiftUI view
// tree containing custom Shapes (Circle strokes were dropped, and only the
// first item of an HStack of two rings rendered). Rendering to a flat
// NSImage via ImageRenderer and using that as the label sidesteps both
// issues and is the standard workaround for MenuBarExtra + custom content.
struct MenuBarMetersView: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject private var l10n = LocalizationManager.shared

    var body: some View {
        Image(nsImage: renderedImage)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }

    // Suppresses stale percentages on fetch failure instead of leaving the
    // previous successful snapshot's numbers on screen — matches PopoverView,
    // which hides the same numbers via `displaySnapshot`.
    private var displaySnapshot: UsageSnapshot? {
        viewModel.lastFetchFailed ? nil : viewModel.snapshot
    }

    // The rendered NSImage carries no accessibility info of its own — the
    // labels set on UsageRingView never reach VoiceOver once flattened to a
    // bitmap, so the combined label has to be built and attached here.
    private var accessibilityLabel: String {
        let sessionText: String
        if let percent = displaySnapshot?.session.percentUsed {
            sessionText = String(format: l10n.string("accessibility.session_percent_used"), percent)
        } else {
            sessionText = l10n.string("accessibility.session_unavailable")
        }

        let weeklyText: String
        if let percent = displaySnapshot?.weekly.percentUsed {
            weeklyText = String(format: l10n.string("accessibility.weekly_percent_used"), percent)
        } else {
            weeklyText = l10n.string("accessibility.weekly_unavailable")
        }

        var parts = [sessionText, weeklyText]
        if viewModel.lastFetchFailed {
            parts.append(l10n.string("accessibility.update_failed"))
        }
        return parts.joined(separator: " ")
    }

    private var renderedImage: NSImage {
        let content = MetersGlyph(
            sessionPercent: displaySnapshot?.session.percentUsed,
            weeklyPercent: displaySnapshot?.weekly.percentUsed
        )
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        renderer.proposedSize = ProposedViewSize(width: 44, height: 20)
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: 44, height: 20))
        // Template = macOS tints it to match the menu bar (white on dark,
        // black on light) exactly like every built-in status item, and
        // re-tints automatically on appearance changes. Only alpha matters
        // once this is set, which is why MeterRingGlyph paints in black with
        // opacity standing in for the accent color the Popover still uses.
        image.isTemplate = true
        return image
    }
}

private struct MetersGlyph: View {
    let sessionPercent: Int?
    let weeklyPercent: Int?

    var body: some View {
        HStack(spacing: 4) {
            MenuBarRingGlyph(percent: sessionPercent)
            MenuBarRingGlyph(percent: weeklyPercent)
        }
        .frame(width: 44, height: 20)
    }
}

/// Monochrome, alpha-only counterpart of UsageRingView for the menu bar
/// template image. Progress is conveyed by opacity, not by accent color,
/// since a template image discards hue and keeps only alpha.
private struct MenuBarRingGlyph: View {
    let percent: Int?
    private let diameter: CGFloat = 20
    private let lineWidth: CGFloat = 2

    // Circle().stroke() centers its line on the circle's edge, so half the
    // line width bleeds outside the shape's own bounding box. In a normal
    // view hierarchy that bleed just falls into surrounding padding, but
    // this glyph gets flattened by ImageRenderer into a fixed-size bitmap
    // (see renderedImage), which hard-clips anything outside that box —
    // without the inset, the outer edge of the ring gets cut off. Sizing
    // the circles to (diameter - lineWidth) keeps the stroke's outer edge
    // exactly at the glyph's frame boundary instead of past it.
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.35), lineWidth: lineWidth)
                .frame(width: diameter - lineWidth, height: diameter - lineWidth)

            if let percent {
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                    .stroke(Color.black, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: diameter - lineWidth, height: diameter - lineWidth)
            }

            Text(percent.map(String.init) ?? "–")
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundColor(.black)
        }
        .frame(width: diameter, height: diameter)
    }

    private var fontSize: CGFloat {
        let base = diameter * 0.45
        guard let percent, percent >= 100 else { return base }
        return base * 0.8
    }
}
