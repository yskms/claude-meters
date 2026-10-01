import Foundation
import os

enum UpdateCheckError: Error {
    case unexpectedStatus(Int)
    case invalidResponse
    case invalidVersion
}

/// Asks GitHub Releases for the latest published version. `releases/latest`
/// never returns drafts or pre-releases, so the tag is always a stable one.
enum LatestRelease {
    private static let apiURL = URL(string: "https://api.github.com/repos/yskms/claude-meters/releases/latest")!

    static func fetchTag() async throws -> String {
        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateCheckError.invalidResponse
        }
        return try parseTag(statusCode: http.statusCode, data: data)
    }

    /// Pure so status/body handling is unit-testable without networking.
    static func parseTag(statusCode: Int, data: Data) throws -> String {
        guard (200..<300).contains(statusCode) else {
            throw UpdateCheckError.unexpectedStatus(statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            throw UpdateCheckError.invalidResponse
        }
        return tag
    }
}

/// Backs the Settings "Check for Updates" button. This only *tells* the user
/// a newer version exists — downloading and installing stay manual (the
/// notarized DMG from the Releases page); there is no auto-update mechanism.
@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(version: String)
        case failed
    }

    /// Opened instead of any URL from the API response, so nothing taken
    /// from the network is ever handed to `NSWorkspace.open`.
    static let releasesPageURL = URL(string: "https://github.com/yskms/claude-meters/releases/latest")!

    /// Failures are logged at .error so they persist and can be reviewed
    /// later with `log show --predicate 'subsystem == "com.yskms.ClaudeMeters"'`.
    private static let logger = Logger(subsystem: "com.yskms.ClaudeMeters", category: "update")

    @Published private(set) var state: State = .idle

    let currentVersion: String
    private let fetchLatestTag: () async throws -> String

    init(
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        fetchLatestTag: @escaping () async throws -> String = LatestRelease.fetchTag
    ) {
        self.currentVersion = currentVersion
        self.fetchLatestTag = fetchLatestTag
    }

    func check() async {
        guard state != .checking else { return }
        state = .checking
        do {
            let tag = try await fetchLatestTag()
            guard let latest = AppVersion(tag), let current = AppVersion(currentVersion) else {
                Self.logger.error("Unparseable version: tag=\(tag, privacy: .public) current=\(self.currentVersion, privacy: .public)")
                throw UpdateCheckError.invalidVersion
            }
            state = latest > current ? .updateAvailable(version: latest.description) : .upToDate
        } catch {
            if Task.isCancelled {
                state = .idle
            } else {
                Self.logger.error("Update check failed: \(String(describing: error), privacy: .public)")
                state = .failed
            }
        }
    }

    /// Called when the Settings window is shown again, so an old
    /// "up to date"/"failed" result doesn't linger. A found update is kept:
    /// it stays true until the user installs it.
    func resetIfFinished() {
        switch state {
        case .upToDate, .failed:
            state = .idle
        case .idle, .checking, .updateAvailable:
            break
        }
    }
}
