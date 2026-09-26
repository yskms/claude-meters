import Foundation

protocol UsageProvider {
    func fetchUsage() async throws -> UsageSnapshot
}

enum UsageProviderError: Error {
    case credentialUnavailable
    case invalidResponse
}
