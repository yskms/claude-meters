import AppKit
import Combine
import SwiftUI

/// Manages the Settings window directly with AppKit instead of relying on
/// SwiftUI's `Settings` scene. This app runs as an accessory (LSUIElement,
/// no Dock icon, no visible menu bar), and on that setup the documented
/// `SettingsLink`/`showSettingsWindow:` mechanisms do not reliably open a
/// window — confirmed via Console logging
/// "Please use SettingsLink for opening the Settings scene." while the
/// window still never appeared. Owning the window ourselves works
/// regardless of macOS version or activation policy.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var windowController: NSWindowController?
    private var hostingController: NSHostingController<SettingsView>?
    private var languageObserver: AnyCancellable?
    private var updateStateObserver: AnyCancellable?
    private let updateChecker = UpdateChecker()

    private init() {
        // The update-check result changes the row's content (and so the
        // window's fitting size) after the user clicks. Same one-runloop
        // wait as the language observer in show(): `$state` also notifies
        // before the value is applied.
        updateStateObserver = updateChecker.$state
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.resizeToFitContent()
                }
            }
    }

    func show(viewModel: UsageViewModel) {
        // The "設定" button lives inside the MenuBarExtra popover, which is
        // that popover's key window at the moment it's clicked. Capture its
        // frame before closing it: closing mirrors clicking outside the
        // popover to dismiss it (so the Settings window doesn't open
        // stacked on top of it), and the frame lets us line the Settings
        // window's left edge up with the popover's instead of leaving it
        // dead-centered on screen, unrelated-looking to where it was
        // opened from.
        var popoverFrame: NSRect?
        if let popoverWindow = NSApp.keyWindow, popoverWindow !== windowController?.window {
            popoverFrame = popoverWindow.frame
            popoverWindow.close()
        }

        updateChecker.resetIfFinished()

        if windowController == nil {
            // NSWindow(contentViewController:) sizes the window to the
            // hosted SwiftUI content's fitting size before we call
            // center() below. Creating a zero-sized window and setting
            // contentView afterwards leaves center() centering a 0x0
            // rect, so the window ends up with its top-left corner (not
            // its center) at the screen's center once it grows to fit.
            let hostingController = NSHostingController(rootView: SettingsView(viewModel: viewModel, updateChecker: updateChecker))
            self.hostingController = hostingController
            let window = NSWindow(contentViewController: hostingController)
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            windowController = NSWindowController(window: window)

            // Keeps the title bar in sync if the language is changed while
            // this window is open, instead of only updating on the next
            // show() call. The resize has to wait a runloop turn: `language`
            // is `@Published`, which notifies from `willSet` — SwiftUI
            // hasn't re-rendered SettingsView with the new language yet at
            // the point this sink runs, so measuring fittingSize
            // synchronously here would still see the old (pre-switch) size.
            languageObserver = LocalizationManager.shared.$language
                .sink { [weak self] newLanguage in
                    self?.windowController?.window?.title = LocalizationManager.shared.string("menu.settings", for: newLanguage)
                    DispatchQueue.main.async {
                        self?.resizeToFitContent()
                    }
                }
        } else {
            // The window is reused across show() calls (see
            // isReleasedWhenClosed above), so its size otherwise stays
            // frozen at whatever it was when first created — including
            // across a close/reopen in a different language, which doesn't
            // go through the languageObserver above.
            resizeToFitContent()
        }

        if let popoverFrame, let window = windowController?.window {
            var origin = window.frame.origin
            origin.x = popoverFrame.minX
            window.setFrameOrigin(origin)
            clampToVisibleFrame(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }

    // setContentSize keeps frame.origin — the window's bottom-left corner —
    // fixed, so a height change would move the title bar instead of the
    // bottom edge. The top edge is restored below so the title bar stays
    // put and a taller window grows downward.
    //
    // Called before the popover-alignment step in show() touches origin.x,
    // and re-clamps to the screen itself: the menu bar (and this window) sit
    // near the screen's right edge, so growing the window for a longer
    // language can push it past visibleFrame.maxX. Both callers — show()'s
    // reuse branch and the language-switch observer above it — go through
    // here so neither can skip the clamp.
    private func resizeToFitContent() {
        guard let window = windowController?.window, let hostingController else { return }
        let topEdge = window.frame.maxY
        window.setContentSize(hostingController.view.fittingSize)
        window.setFrameOrigin(NSPoint(x: window.frame.origin.x, y: topEdge - window.frame.height))
        clampToVisibleFrame(window)
    }

    private func clampToVisibleFrame(_ window: NSWindow) {
        guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var origin = window.frame.origin
        origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - window.frame.width)
        origin.y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - window.frame.height)
        window.setFrameOrigin(origin)
    }
}
