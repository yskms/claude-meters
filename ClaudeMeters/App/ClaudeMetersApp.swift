import SwiftUI

@main
struct ClaudeMetersApp: App {
    @StateObject private var viewModel = UsageViewModel(
        provider: Self.isRunningAsTestHost ? TestHostUsageProvider() : ClaudeUsageProvider()
    )

    var body: some Scene {
        MenuBarExtra {
            PopoverView(viewModel: viewModel)
        } label: {
            MenuBarMetersView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }

    /// Unit tests run inside this app (TEST_HOST), so without this the app's
    /// own loop would read the real Keychain item and call the real usage
    /// API during `xcodebuild test` — consuming the user's rate limit (the
    /// endpoint returns 429 readily) and depending on local credentials.
    private static var isRunningAsTestHost: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestSessionIdentifier"] != nil
    }
}

/// Stands in for ClaudeUsageProvider while hosting unit tests: never touches
/// the Keychain or the network.
private struct TestHostUsageProvider: UsageProvider {
    func fetchUsage() async throws -> UsageSnapshot {
        throw UsageProviderError.credentialUnavailable
    }
}
