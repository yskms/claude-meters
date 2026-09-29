import Foundation

protocol UsageProvider {
    func fetchUsage() async throws -> UsageSnapshot
}

enum UsageProviderError: Error {
    /// Claude Code's own stored credential couldn't be read (missing item,
    /// unparsable, or the Keychain access dialog hasn't been approved yet).
    case credentialUnavailable
    /// HTTP status outside 2xx. The code is kept so a transient failure
    /// (429, 5xx) can be told apart from an auth failure (401/403).
    case unexpectedStatus(Int)
    /// 2xx, but the body wasn't the expected JSON or lacked a required
    /// field — the API's undocumented shape may have changed.
    case invalidResponse
    /// Transport-level failure (offline, timeout, DNS, etc.).
    case network(Error)
}
