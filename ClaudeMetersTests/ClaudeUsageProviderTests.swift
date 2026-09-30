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

    // MARK: - parseResponse

    private let validBody = Data("""
        {"five_hour":{"utilization":16.0,"resets_at":"2026-09-26T02:19:59.582064+00:00"},
         "seven_day":{"utilization":42.0,"resets_at":"2026-09-30T00:00:00+00:00"}}
        """.utf8)

    private func assertThrows(
        statusCode: Int, body: Data, file: StaticString = #filePath, line: UInt = #line,
        _ check: (UsageProviderError) -> Bool
    ) {
        do {
            _ = try ClaudeUsageProvider.parseResponse(statusCode: statusCode, data: body, fetchedAt: Date())
            XCTFail("expected an error", file: file, line: line)
        } catch let error as UsageProviderError {
            XCTAssertTrue(check(error), "unexpected error \(error)", file: file, line: line)
        } catch {
            XCTFail("unexpected error type \(error)", file: file, line: line)
        }
    }

    func testParseResponseSuccess() throws {
        let fetchedAt = Date()
        let snapshot = try ClaudeUsageProvider.parseResponse(statusCode: 200, data: validBody, fetchedAt: fetchedAt)
        XCTAssertEqual(snapshot.session.percentUsed, 16)
        XCTAssertEqual(snapshot.weekly.percentUsed, 42)
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
    }

    func testParseResponseKeepsStatusCodeForNon2xx() {
        for status in [401, 403, 429, 500, 503] {
            assertThrows(statusCode: status, body: Data(#"{"error":{}}"#.utf8)) {
                if case .unexpectedStatus(let code) = $0 { return code == status }
                return false
            }
        }
    }

    func testParseResponseNon2xxIsNotInvalidResponseEvenWithValidBody() {
        assertThrows(statusCode: 429, body: validBody) {
            if case .unexpectedStatus(429) = $0 { return true }
            return false
        }
    }

    func testParseResponseMalformedJSONIsInvalidResponse() {
        assertThrows(statusCode: 200, body: Data("not json".utf8)) {
            if case .invalidResponse = $0 { return true }
            return false
        }
    }

    func testParseResponseMissingMeterIsInvalidResponse() {
        let body = Data(#"{"five_hour":{"utilization":16.0,"resets_at":"2026-09-26T02:19:59+00:00"}}"#.utf8)
        assertThrows(statusCode: 200, body: body) {
            if case .invalidResponse = $0 { return true }
            return false
        }
    }

    // MARK: - keyStructure

    func testKeyStructureDropsValues() {
        let structure = ClaudeUsageProvider.keyStructure(of: validBody)
        XCTAssertEqual(structure, "five_hour{resets_at,utilization} seven_day{resets_at,utilization}")
        XCTAssertFalse(structure.contains("16"))
        XCTAssertFalse(structure.contains("2026"))
    }

    func testKeyStructureNonObject() {
        XCTAssertEqual(ClaudeUsageProvider.keyStructure(of: Data("[1,2]".utf8)), "<not a JSON object>")
    }

    // MARK: - errorSummary

    func testErrorSummaryLogsTypeButNeverMessage() {
        let body = Data(#"{"error":{"type":"rate_limit_error","message":"secret user@example.com","extra":"x"}}"#.utf8)
        let summary = ClaudeUsageProvider.errorSummary(of: body)
        XCTAssertEqual(summary, "type=rate_limit_error bytes=\(body.count)")
        XCTAssertFalse(summary.contains("secret"))
    }

    func testErrorSummaryRejectsFreeFormType() {
        let body = Data(#"{"error":{"type":"see https://example.com/?token=abc"}}"#.utf8)
        XCTAssertEqual(ClaudeUsageProvider.errorSummary(of: body), "type=<unrecognized> bytes=\(body.count)")
    }

    func testSanitizedRetryAfter() {
        XCTAssertEqual(ClaudeUsageProvider.sanitizedRetryAfter(nil), "-")
        XCTAssertEqual(ClaudeUsageProvider.sanitizedRetryAfter("0"), "0")
        XCTAssertEqual(ClaudeUsageProvider.sanitizedRetryAfter("120"), "120")
        XCTAssertEqual(ClaudeUsageProvider.sanitizedRetryAfter("Wed, 30 Sep 2026 07:00:00 GMT"), "<non-numeric>")
        XCTAssertEqual(ClaudeUsageProvider.sanitizedRetryAfter("-1"), "<non-numeric>")
    }

    func testErrorSummaryOmitsNonErrorBody() {
        let body = Data("<html>secret page</html>".utf8)
        let summary = ClaudeUsageProvider.errorSummary(of: body)
        XCTAssertEqual(summary, "body=<\(body.count) bytes, not an API error object>")
        XCTAssertFalse(summary.contains("secret"))
    }

    // MARK: - runProcess

    func testRunProcessReturnsStdoutOnSuccess() {
        let result = ClaudeUsageProvider.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/echo"), arguments: ["hello"], timeout: 5)
        XCTAssertEqual(result, .success(Data("hello\n".utf8)))
    }

    func testRunProcessNonZeroExitIsFailed() {
        let result = ClaudeUsageProvider.runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/false"), arguments: [], timeout: 5)
        XCTAssertEqual(result, .failed)
    }

    func testRunProcessEmptyOutputIsFailed() {
        let result = ClaudeUsageProvider.runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/true"), arguments: [], timeout: 5)
        XCTAssertEqual(result, .failed)
    }

    func testRunProcessMissingExecutableIsFailed() {
        let result = ClaudeUsageProvider.runProcess(
            executableURL: URL(fileURLWithPath: "/nonexistent/binary"), arguments: [], timeout: 5)
        XCTAssertEqual(result, .failed)
    }

    func testRunProcessTimesOutAndReturnsPromptly() {
        let start = Date()
        let result = ClaudeUsageProvider.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 0.5)
        XCTAssertEqual(result, .timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }
}
