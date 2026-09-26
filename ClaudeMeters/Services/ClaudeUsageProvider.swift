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

        let (data, response) = try await URLSession.shared.data(for: request)
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
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
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

    private static func parseMeter(_ dict: [String: Any]?) -> MeterUsage? {
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

    private static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }

        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        return withoutFraction.date(from: string)
    }
}
