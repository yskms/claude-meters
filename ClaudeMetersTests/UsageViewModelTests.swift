import XCTest
@testable import Claude_Meters

@MainActor
final class UsageViewModelTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // The loop's very first fetch fires immediately on init, before any
        // refreshInterval read matters for these tests — but a stale value
        // saved by a previous run could still affect it, so start clean.
        UserDefaults.standard.removeObject(forKey: "refreshInterval")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "refreshInterval")
        super.tearDown()
    }

    func testSuccessfulFetchUpdatesSnapshotAndClearsError() async {
        let mock = MockUsageProvider(outcomes: [.success(SampleData.snapshot)])
        let viewModel = UsageViewModel(provider: mock)

        await waitUntil { viewModel.snapshot != nil }

        XCTAssertEqual(viewModel.snapshot?.session.percentUsed, 16)
        XCTAssertEqual(viewModel.snapshot?.weekly.percentUsed, 5)
        XCTAssertNil(viewModel.lastError)
        XCTAssertFalse(viewModel.lastFetchFailed)
    }

    func testFailedFetchSetsLastErrorAndKeepsSnapshotNil() async {
        let mock = MockUsageProvider(outcomes: [.failure(.credentialUnavailable)])
        let viewModel = UsageViewModel(provider: mock)

        await waitUntil { viewModel.lastError != nil }

        XCTAssertNil(viewModel.snapshot)
        XCTAssertTrue(viewModel.lastFetchFailed)
        if case .credentialUnavailable = viewModel.lastError {
            // expected
        } else {
            XCTFail("expected .credentialUnavailable, got \(String(describing: viewModel.lastError))")
        }
    }

    /// Guards the contract UsageDisplayState relies on to decide whether to
    /// hide stale numbers: on failure, the ViewModel keeps the last
    /// successful snapshot around (it does not clear it to nil) while
    /// setting lastError — hiding is UsageDisplayState's job, not the model's.
    /// A later successful fetch must still fully replace the old snapshot.
    func testFetchFailureAfterSuccessKeepsSnapshotThenRecovers() async {
        let secondSnapshot = UsageSnapshot(
            session: MeterUsage(percentUsed: 40, resetsAt: Date(timeIntervalSinceNow: 3600)),
            weekly: MeterUsage(percentUsed: 12, resetsAt: Date(timeIntervalSinceNow: 86400)),
            fetchedAt: Date()
        )
        let mock = MockUsageProvider(outcomes: [
            .success(SampleData.snapshot),
            .failure(.credentialUnavailable),
            .success(secondSnapshot)
        ])
        let viewModel = UsageViewModel(provider: mock)

        // 成功
        await waitUntil { viewModel.snapshot != nil }
        XCTAssertEqual(viewModel.snapshot?.session.percentUsed, 16)
        XCTAssertFalse(viewModel.lastFetchFailed)

        // 失敗: refreshNow() でループを再起動し、待機時間なしで次のフェッチを発生させる
        viewModel.refreshNow()
        await waitUntil { viewModel.lastFetchFailed }
        XCTAssertEqual(viewModel.snapshot?.session.percentUsed, 16, "失敗時も直前のスナップショットは保持される")
        if case .credentialUnavailable = viewModel.lastError {
            // expected
        } else {
            XCTFail("expected .credentialUnavailable, got \(String(describing: viewModel.lastError))")
        }

        // 再成功
        viewModel.refreshNow()
        await waitUntil { viewModel.snapshot?.session.percentUsed == 40 }
        XCTAssertFalse(viewModel.lastFetchFailed)
        XCTAssertNil(viewModel.lastError)
        XCTAssertEqual(viewModel.snapshot?.weekly.percentUsed, 12)
    }

    func testRefreshIntervalPersistsToUserDefaults() {
        let mock = MockUsageProvider(outcomes: [.success(SampleData.snapshot)])
        let viewModel = UsageViewModel(provider: mock)

        viewModel.refreshInterval = 300

        XCTAssertEqual(UserDefaults.standard.double(forKey: "refreshInterval"), 300)
    }

    /// Polls a condition on the main actor instead of a fixed sleep, so the
    /// test finishes as soon as the async fetch lands rather than always
    /// waiting out a worst-case delay.
    private func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
    }
}
