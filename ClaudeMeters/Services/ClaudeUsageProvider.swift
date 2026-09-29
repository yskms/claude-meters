import Foundation
import Security

/// Reads Claude Code's own locally-stored OAuth credential (never manages
/// credentials of its own) and calls Anthropic's usage endpoint.
///
/// This endpoint (`/api/oauth/usage`) is undocumented — see
/// docs/REQUIREMENTS.md "開発前提・技術検証" for the PoC that verified it
/// and the risks of depending on it. Session/Weekly reset timestamps are
/// used exactly as returned; this type never computes a reset time itself.
final class ClaudeUsageProvider: UsageProvider {
    private let keychainService = "Claude Code-credentials"
    private let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    func fetchUsage() async throws -> UsageSnapshot {
        let token = try readAccessToken()

        var request = URLRequest(url: usageURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw UsageProviderError.network(error)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UsageProviderError.invalidResponse
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageProviderError.invalidResponse
        }
        // This endpoint is undocumented (see docs/REQUIREMENTS.md). If its
        // shape changes and a required field goes missing, that must surface
        // as a fetch failure, not as a silent "0%"/"–" display.
        guard let session = Self.parseMeter(json["five_hour"] as? [String: Any]),
              let weekly = Self.parseMeter(json["seven_day"] as? [String: Any]) else {
            throw UsageProviderError.invalidResponse
        }

        return UsageSnapshot(session: session, weekly: weekly, fetchedAt: Date())
    }

    private func readAccessToken() throws -> String {
        guard let data = readCredentialViaSecurityCLI() ?? readCredentialViaSecItem(),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageProviderError.credentialUnavailable
        }

        if let token = json["accessToken"] as? String {
            return token
        }
        if let oauth = json["claudeAiOauth"] as? [String: Any],
           let token = oauth["accessToken"] as? String {
            return token
        }
        throw UsageProviderError.credentialUnavailable
    }

    /// Reads the item through `/usr/bin/security` instead of calling
    /// SecItemCopyMatching directly. Claude Code writes this item with
    /// `security add-generic-password -U` on every token refresh, which
    /// resets the item's ACL to trust only `/usr/bin/security` — so any
    /// "Always Allow" granted to this app is lost a few times a day and the
    /// Keychain password prompt reappears. Going through the same binary
    /// keeps us on the ACL and avoids the prompt. Do not replace this with
    /// SecItemCopyMatching.
    private func readCredentialViaSecurityCLI() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }

    /// Fallback for when the CLI path fails (e.g. the item was written by
    /// something other than `/usr/bin/security`). May show the Keychain prompt.
    private func readCredentialViaSecItem() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func parseMeter(_ dict: [String: Any]?) -> MeterUsage? {
        guard let dict,
              let utilization = dict["utilization"] as? Double,
              let resetsAtString = dict["resets_at"] as? String,
              let resetsAt = Self.parseDate(resetsAtString) else {
            return nil
        }
        guard utilization.isFinite, (0.0...100.0).contains(utilization) else { return nil }
        let percent = Int(utilization.rounded())
        return MeterUsage(percentUsed: percent, resetsAt: resetsAt)
    }

    static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        return withoutFraction.date(from: string)
    }
}
