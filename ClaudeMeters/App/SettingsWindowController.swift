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
                .sink { [weak window] _ in
                    window?.title = LocalizationManager.shared.string("menu.settings")
                }
        }
        NSApp.activate(ignoringOtherApps: true)
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }
}
