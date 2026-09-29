import XCTest
@testable import Claude_Meters

final class UsageDisplayStateTests: XCTestCase {

    private let fetchedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Session resets 1 h after the fetch, weekly 3 days after.
    private var snapshot: UsageSnapshot {
        UsageSnapshot(
            session: MeterUsage(percentUsed: 16, resetsAt: fetchedAt.addingTimeInterval(3600)),
            weekly: MeterUsage(percentUsed: 42, resetsAt: fetchedAt.addingTimeInterval(3 * 86400)),
            fetchedAt: fetchedAt
        )
    }

    private func state(_ error: UsageProviderError?, after elapsed: TimeInterval) -> UsageDisplayState {
        UsageDisplayState.make(snapshot: snapshot, lastError: error, now: fetchedAt.addingTimeInterval(elapsed))
    }

    private var hidden: UsageDisplayState {
        UsageDisplayState(session: nil, weekly: nil, staleSince: nil)
    }

    // MARK: - No failure

    func testNoSnapshotShowsNothing() {
        XCTAssertEqual(UsageDisplayState.make(snapshot: nil, lastError: nil, now: fetchedAt), hidden)
        XCTAssertEqual(UsageDisplayState.make(snapshot: nil, lastError: .unexpectedStatus(429), now: fetchedAt), hidden)
    }

    func testSuccessShowsBothMetersAndIsNotStale() {
        let s = state(nil, after: 60)
        XCTAssertEqual(s.session, snapshot.session)
        XCTAssertEqual(s.weekly, snapshot.weekly)
        XCTAssertNil(s.staleSince)
    }

    // MARK: - Transient failure

    func testTransientFailureKeepsValuesAndMarksStale() {
        for error in [UsageProviderError.unexpectedStatus(429), .unexpectedStatus(503), .network(URLError(.timedOut))] {
            let s = state(error, after: 5 * 60)
            XCTAssertEqual(s.session, snapshot.session, "\(error)")
            XCTAssertEqual(s.weekly, snapshot.weekly, "\(error)")
            XCTAssertEqual(s.staleSince, fetchedAt, "\(error)")
        }
    }

    func testTransientFailureJustUnder15MinutesStillShows() {
        let s = state(.unexpectedStatus(429), after: UsageDisplayState.maxStaleAge - 1)
        XCTAssertEqual(s.session, snapshot.session)
        XCTAssertEqual(s.staleSince, fetchedAt)
    }

    func testTransientFailureAtExactly15MinutesHides() {
        XCTAssertEqual(state(.unexpectedStatus(429), after: UsageDisplayState.maxStaleAge), hidden)
    }

    func testTransientFailureAfterLongSleepHides() {
        // Wall-clock based: two hours asleep counts the same as two hours awake.
        XCTAssertEqual(state(.network(URLError(.notConnectedToInternet)), after: 2 * 3600), hidden)
    }

    // MARK: - Per-meter reset

    func testSessionResetHidesOnlySession() {
        let resetSnapshot = UsageSnapshot(
            session: MeterUsage(percentUsed: 16, resetsAt: fetchedAt.addingTimeInterval(60)),
            weekly: snapshot.weekly,
            fetchedAt: fetchedAt
        )
        let s = UsageDisplayState.make(snapshot: resetSnapshot, lastError: .unexpectedStatus(429), now: fetchedAt.addingTimeInterval(60))
        XCTAssertNil(s.session, "resets_at reached exactly → hidden")
        XCTAssertEqual(s.weekly, snapshot.weekly)
        XCTAssertEqual(s.staleSince, fetchedAt)
    }

    func testWeeklyResetHidesOnlyWeekly() {
        let resetSnapshot = UsageSnapshot(
            session: snapshot.session,
            weekly: MeterUsage(percentUsed: 42, resetsAt: fetchedAt.addingTimeInterval(60)),
            fetchedAt: fetchedAt
        )
        let s = UsageDisplayState.make(snapshot: resetSnapshot, lastError: .unexpectedStatus(429), now: fetchedAt.addingTimeInterval(120))
        XCTAssertEqual(s.session, snapshot.session)
        XCTAssertNil(s.weekly)
        XCTAssertEqual(s.staleSince, fetchedAt)
    }

    func testBothResetHidesBothAndIsNotStale() {
        let resetSnapshot = UsageSnapshot(
            session: MeterUsage(percentUsed: 16, resetsAt: fetchedAt.addingTimeInterval(60)),
            weekly: MeterUsage(percentUsed: 42, resetsAt: fetchedAt.addingTimeInterval(60)),
            fetchedAt: fetchedAt
        )
        let s = UsageDisplayState.make(snapshot: resetSnapshot, lastError: .unexpectedStatus(429), now: fetchedAt.addingTimeInterval(120))
        XCTAssertEqual(s, hidden, "nothing shown → no 'showing values from' message either")
    }

    func testResetAppliesWithoutFailureToo() {
        let resetSnapshot = UsageSnapshot(
            session: MeterUsage(percentUsed: 16, resetsAt: fetchedAt.addingTimeInterval(60)),
            weekly: snapshot.weekly,
            fetchedAt: fetchedAt
        )
        let s = UsageDisplayState.make(snapshot: resetSnapshot, lastError: nil, now: fetchedAt.addingTimeInterval(120))
        XCTAssertNil(s.session)
        XCTAssertEqual(s.weekly, snapshot.weekly)
        XCTAssertNil(s.staleSince)
    }

    // MARK: - Non-transient failure

    func testNonTransientFailureHidesEvenWhenFresh() {
        for error in [UsageProviderError.credentialUnavailable, .invalidResponse, .unexpectedStatus(401), .unexpectedStatus(403)] {
            XCTAssertEqual(state(error, after: 1), hidden, "\(error)")
        }
    }

    func testTransientThenNonTransientHides() {
        XCTAssertEqual(state(.unexpectedStatus(429), after: 60).session, snapshot.session)
        XCTAssertEqual(state(.unexpectedStatus(401), after: 120), hidden)
    }

    // MARK: - isTransient

    func testIsTransientClassification() {
        XCTAssertTrue(UsageProviderError.unexpectedStatus(429).isTransient)
        XCTAssertTrue(UsageProviderError.unexpectedStatus(500).isTransient)
        XCTAssertTrue(UsageProviderError.unexpectedStatus(599).isTransient)
        XCTAssertTrue(UsageProviderError.network(URLError(.timedOut)).isTransient)
        XCTAssertFalse(UsageProviderError.unexpectedStatus(400).isTransient)
        XCTAssertFalse(UsageProviderError.unexpectedStatus(401).isTransient)
        XCTAssertFalse(UsageProviderError.unexpectedStatus(403).isTransient)
        XCTAssertFalse(UsageProviderError.unexpectedStatus(404).isTransient)
        XCTAssertFalse(UsageProviderError.credentialUnavailable.isTransient)
        XCTAssertFalse(UsageProviderError.invalidResponse.isTransient)
    }
}
