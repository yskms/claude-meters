import SwiftUI

struct UsageRingView: View {
    let percent: Int?
    var diameter: CGFloat = 20

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

            Text(percent.map(String.init) ?? "–")
                .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var fontSize: CGFloat {
        let base = diameter * 0.45
        guard let percent, percent >= 100 else { return base }
        return base * 0.8
    }

    private var accessibilityText: String {
        guard let percent else {
            return NSLocalizedString("accessibility.unavailable", comment: "")
        }
        return String(format: NSLocalizedString("accessibility.percent_used", comment: ""), percent)
    }
}
