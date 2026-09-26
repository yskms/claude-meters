import Foundation
@testable import Claude_Meters

/// Test double for UsageProvider. Not actor-isolated: UsageViewModel only
/// ever calls fetchUsage() sequentially (one await at a time), so a simple
/// lock is enough here.
final class MockUsageProvider: UsageProvider, @unchecked Sendable {
    enum Outcome {
        case success(UsageSnapshot)
        case failure(UsageProviderError)
    }

    private let lock = NSLock()
    private var outcomes: [Outcome]
    private(set) var callCount = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func fetchUsage() async throws -> UsageSnapshot {
        lock.lock()
        let index = min(callCount, outcomes.count - 1)
        let outcome = outcomes[index]
        callCount += 1
        lock.unlock()

        switch outcome {
        case .success(let snapshot):
            return snapshot
        case .failure(let error):
            throw error
        }
    }
}

enum SampleData {
    static let snapshot = UsageSnapshot(
        session: MeterUsage(percentUsed: 16, resetsAt: Date(timeIntervalSinceNow: 3600)),
        weekly: MeterUsage(percentUsed: 5, resetsAt: Date(timeIntervalSinceNow: 86400)),
        fetchedAt: Date()
    )
}
