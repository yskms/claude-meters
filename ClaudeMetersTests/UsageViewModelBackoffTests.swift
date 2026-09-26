import XCTest
@testable import Claude_Meters

final class UsageViewModelBackoffTests: XCTestCase {

    func testNoBackoffWhenNoFailures() {
        let delay = UsageViewModel.computeDelay(refreshInterval: 60, consecutiveFailures: 0, maxBackoffInterval: 300)
        XCTAssertEqual(delay, 60)
    }

    func testBackoffDoublesPerFailure() {
        XCTAssertEqual(UsageViewModel.computeDelay(refreshInterval: 60, consecutiveFailures: 1, maxBackoffInterval: 300), 120)
        XCTAssertEqual(UsageViewModel.computeDelay(refreshInterval: 60, consecutiveFailures: 2, maxBackoffInterval: 300), 240)
    }

    func testBackoffCapsAtMax() {
        let delay = UsageViewModel.computeDelay(refreshInterval: 60, consecutiveFailures: 10, maxBackoffInterval: 300)
        XCTAssertEqual(delay, 300)
    }
}
