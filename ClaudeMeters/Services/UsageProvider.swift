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

    /// Likely to clear up on its own, so the last good values may stay on
    /// screen (see UsageDisplayState). The endpoint returns 429 when polled
    /// faster than about once per 2 minutes (seen at a 1-minute interval).
    /// Everything else needs the user's attention or
    /// signals an API change, and must show as "–".
    var isTransient: Bool {
        switch self {
        case .network:
            return true
        case .unexpectedStatus(let status):
            return status == 429 || (500...599).contains(status)
        case .credentialUnavailable, .invalidResponse:
            return false
        }
    }
}
