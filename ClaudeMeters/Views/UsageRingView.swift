import SwiftUI

struct UsageRingView: View {
    let percent: Int?
    var diameter: CGFloat = 20
    @ObservedObject private var l10n = LocalizationManager.shared

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: 2)

            if let percent {
                Circle()
                    .trim(from: 0, to: CGFloat(min(max(percent, 0), 100)) / 100)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            valueText
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var valueText: some View {
        if let percent {
            Text(String(percent))
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
            + Text("\u{200A}%")
                .font(.system(size: fontSize * 0.55, weight: .medium, design: .monospaced))
        } else {
            Text("–")
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
        }
    }

    private var fontSize: CGFloat {
        let base = diameter * 0.4
        guard let percent, percent >= 100 else { return base }
        return base * 0.8
    }

    private var accessibilityText: String {
        guard let percent else {
            return l10n.string("accessibility.unavailable")
        }
        return String(format: l10n.string("accessibility.percent_used"), percent)
    }
}
