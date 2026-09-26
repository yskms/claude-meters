import XCTest
@testable import Claude_Meters

final class ClaudeUsageProviderTests: XCTestCase {

    // MARK: - parseMeter

    func testParseMeterValidDict() {
        let dict: [String: Any] = [
            "utilization": 16.0,
            "resets_at": "2026-09-26T02:19:59.582064+00:00",
        ]
        let meter = ClaudeUsageProvider.parseMeter(dict)
        XCTAssertEqual(meter?.percentUsed, 16)
        XCTAssertNotNil(meter?.resetsAt)
    }

    func testParseMeterNilDict() {
        XCTAssertNil(ClaudeUsageProvider.parseMeter(nil))
    }

    func testParseMeterMissingUtilization() {
        let dict: [String: Any] = ["resets_at": "2026-09-26T02:19:59+00:00"]
        XCTAssertNil(ClaudeUsageProvider.parseMeter(dict))
    }

    func testParseMeterMissingResetsAt() {
        let dict: [String: Any] = ["utilization": 16.0]
        XCTAssertNil(ClaudeUsageProvider.parseMeter(dict))
    }

    func testParseMeterMalformedResetsAt() {
        let dict: [String: Any] = ["utilization": 16.0, "resets_at": "not a date"]
        XCTAssertNil(ClaudeUsageProvider.parseMeter(dict))
    }

    func testParseMeterRejectsNegativeUtilization() {
        let dict: [String: Any] = ["utilization": -0.4, "resets_at": "2026-09-26T02:19:59+00:00"]
        XCTAssertNil(ClaudeUsageProvider.parseMeter(dict))
    }

    func testParseMeterRejectsUtilizationOver100() {
        let dict: [String: Any] = ["utilization": 100.4, "resets_at": "2026-09-26T02:19:59+00:00"]
        XCTAssertNil(ClaudeUsageProvider.parseMeter(dict))
    }

    func testParseMeterAcceptsBoundaryValues() {
        let zero: [String: Any] = ["utilization": 0.0, "resets_at": "2026-09-26T02:19:59+00:00"]
        let hundred: [String: Any] = ["utilization": 100.0, "resets_at": "2026-09-26T02:19:59+00:00"]
        XCTAssertEqual(ClaudeUsageProvider.parseMeter(zero)?.percentUsed, 0)
        XCTAssertEqual(ClaudeUsageProvider.parseMeter(hundred)?.percentUsed, 100)
    }

    func testParseMeterRejectsNaN() {
        let dict: [String: Any] = ["utilization": Double.nan, "resets_at": "2026-09-26T02:19:59+00:00"]
        XCTAssertNil(ClaudeUsageProvider.parseMeter(dict))
    }

    func testParseMeterRejectsInfinity() {
        let dict: [String: Any] = ["utilization": Double.infinity, "resets_at": "2026-09-26T02:19:59+00:00"]
        XCTAssertNil(ClaudeUsageProvider.parseMeter(dict))
    }

    // MARK: - parseDate

    func testParseDateWithFractionalSeconds() {
        XCTAssertNotNil(ClaudeUsageProvider.parseDate("2026-09-26T02:19:59.582064+00:00"))
    }

    func testParseDateWithoutFractionalSeconds() {
        XCTAssertNotNil(ClaudeUsageProvider.parseDate("2026-09-26T02:19:59+00:00"))
    }

    func testParseDateRejectsGarbage() {
        XCTAssertNil(ClaudeUsageProvider.parseDate("not a date"))
    }
}
