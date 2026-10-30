import XCTest
import SwiftUI
@testable import Claude_Meters

/// Regenerates the images on the introduction site (public/images/) by
/// rendering the app's own views with sample values. This is a tool, not a
/// test: it is skipped unless SITE_IMAGES_DIR is set, so normal test runs
/// never touch the disk. Run it through Tools/render-site-images.sh, which
/// also switches the app language with -testLanguage (never write a language
/// into LocalizationManager here: the test host shares the real app's
/// defaults domain).
@MainActor
final class SiteImageRenderTests: XCTestCase {

    private static let suiteName = "com.yskms.ClaudeMeters.SiteImageRenderTests"

    func testRenderSiteImages() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let dir = env["SITE_IMAGES_DIR"] else {
            throw XCTSkip("Set SITE_IMAGES_DIR (via Tools/render-site-images.sh) to render the site images.")
        }
        let lang = env["SITE_IMAGES_LANG"] ?? "en"
        let out = URL(fileURLWithPath: dir)

        // Sample values, matching the "values are samples" note on the pages.
        UserDefaults().removePersistentDomain(forName: Self.suiteName)
        defer { UserDefaults().removePersistentDomain(forName: Self.suiteName) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        let fetched = try XCTUnwrap(Calendar.current.date(bySettingHour: 10, minute: 24, second: 0, of: Date()))
        let snapshot = UsageSnapshot(
            session: MeterUsage(percentUsed: 11, resetsAt: Date(timeIntervalSinceNow: 3 * 3600 + 5 * 60)),
            weekly: MeterUsage(percentUsed: 12, resetsAt: Date(timeIntervalSinceNow: 4 * 86400 + 6 * 3600)),
            fetchedAt: fetched)
        let viewModel = UsageViewModel(provider: MockUsageProvider(outcomes: [.success(snapshot)]), defaults: defaults)
        for _ in 0..<100 where viewModel.snapshot == nil { try await Task.sleep(nanoseconds: 50_000_000) }
        XCTAssertNotNil(viewModel.snapshot)

        for (name, scheme, background) in [
            ("light", ColorScheme.light, Color(red: 0.94, green: 0.94, blue: 0.94)),
            ("dark", ColorScheme.dark, Color(red: 0.17, green: 0.17, blue: 0.18)),
        ] {
            let view = PopoverView(viewModel: viewModel)
                .background(background)
                .environment(\.colorScheme, scheme)
            try write(view, scale: 2, to: out.appendingPathComponent("popover-\(lang)-\(name).png"))
        }

        // The menu bar glyph is language-independent; the white one is the
        // black one inverted (the app uses a template image that macOS tints).
        guard lang == "en" else { return }
        for (name, invert) in [("black", false), ("white", true)] {
            let glyph = MetersGlyph(sessionPercent: 11, weeklyPercent: 12)
            let view = Group { if invert { glyph.colorInvert() } else { glyph } }
            try write(view, scale: 4, to: out.appendingPathComponent("glyph-\(name).png"))
        }
    }

    private func write<V: View>(_ view: V, scale: CGFloat, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let cgImage = try XCTUnwrap(renderer.cgImage)
        let data = try XCTUnwrap(NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}
