import Foundation

protocol UsageProvider {
    func fetchUsage() async throws -> UsageSnapshot
}

enum UsageProviderError: Error {
    /// Claude Code's own stored credential couldn't be read (missing item,
    /// unparsable, or the Keychain access dialog hasn't been approved yet).
    case credentialUnavailable
    /// HTTP status outside 2xx, or the response body was missing a required
    /// field — the API's undocumented shape may have changed.
    case invalidResponse
    /// Transport-level failure (offline, timeout, DNS, etc.).
    case network(Error)
}
