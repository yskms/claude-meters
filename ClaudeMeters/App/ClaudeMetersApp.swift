import SwiftUI

@main
struct ClaudeMetersApp: App {
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(viewModel: viewModel)
        } label: {
            MenuBarMetersView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
