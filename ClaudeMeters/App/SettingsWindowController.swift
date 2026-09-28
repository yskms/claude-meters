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
    private var languageObserver: AnyCancellable?

    private init() {}

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

        if windowController == nil {
            // NSWindow(contentViewController:) sizes the window to the
            // hosted SwiftUI content's fitting size before we call
            // center() below. Creating a zero-sized window and setting
            // contentView afterwards leaves center() centering a 0x0
            // rect, so the window ends up with its top-left corner (not
            // its center) at the screen's center once it grows to fit.
            let hostingController = NSHostingController(rootView: SettingsView(viewModel: viewModel))
            let window = NSWindow(contentViewController: hostingController)
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            windowController = NSWindowController(window: window)

            // Keeps the title bar in sync if the language is changed while
            // this window is open, instead of only updating on the next
            // show() call.
            languageObserver = LocalizationManager.shared.$language
                .sink { [weak window] newLanguage in
                    window?.title = LocalizationManager.shared.string("menu.settings", for: newLanguage)
                }
        }

        if let popoverFrame, let window = windowController?.window {
            var origin = window.frame.origin
            origin.x = popoverFrame.minX
            if let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame {
                origin.x = min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - window.frame.width)
            }
            window.setFrameOrigin(origin)
        }

        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }
}
