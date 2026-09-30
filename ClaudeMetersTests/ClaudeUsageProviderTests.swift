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

    func testParseMeterNullResetsAtMeansNoRunningWindow() {
        let dict: [String: Any] = ["utilization": 0.0, "resets_at": NSNull()]
        let meter = ClaudeUsageProvider.parseMeter(dict)
        XCTAssertEqual(meter?.percentUsed, 0)
        XCTAssertNotNil(meter)
        XCTAssertNil(meter?.resetsAt)
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

    func testParseMeterRejectsBoolUtilization() {
        // Decoded through JSONSerialization so `true` is the CFBoolean-backed
        // NSNumber the real response yields (which `as? Double` would accept).
        let body = Data(#"{"utilization":true,"resets_at":"2026-09-26T02:19:59+00:00"}"#.utf8)
        let dict = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertNotNil(dict)
        XCTAssertNil(ClaudeUsageProvider.parseMeter(dict))
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

    /// The shape observed on 2026-10-01 while no 5-hour window was running.
    func testParseResponseAcceptsNullSessionResetsAt() throws {
        let body = Data(#"""
        {"five_hour":{"utilization":0.0,"resets_at":null},
         "seven_day":{"utilization":42.0,"resets_at":"2026-09-30T00:00:00+00:00"}}
        """#.utf8)
        let snapshot = try ClaudeUsageProvider.parseResponse(statusCode: 200, data: body, fetchedAt: Date())
        XCTAssertEqual(snapshot.session.percentUsed, 0)
        XCTAssertNil(snapshot.session.resetsAt)
        XCTAssertEqual(snapshot.weekly.percentUsed, 42)
        XCTAssertNotNil(snapshot.weekly.resetsAt)
    }

    func testParseResponseBoolUtilizationIsInvalidResponse() {
        let body = Data(#"""
        {"five_hour":{"utilization":true,"resets_at":"2026-09-26T02:19:59+00:00"},
         "seven_day":{"utilization":42.0,"resets_at":"2026-09-30T00:00:00+00:00"}}
        """#.utf8)
        assertThrows(statusCode: 200, body: body) {
            if case .invalidResponse = $0 { return true }
            return false
        }
        XCTAssertTrue(ClaudeUsageProvider.meterFieldTypes(of: body).hasPrefix("five_hour{utilization:bool,"))
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

    // MARK: - meterFieldTypes

    func testMeterFieldTypesValidBodyDropsValues() {
        let types = ClaudeUsageProvider.meterFieldTypes(of: validBody)
        XCTAssertEqual(types, "five_hour{utilization:number,resets_at:string} seven_day{utilization:number,resets_at:string}")
    }

    func testMeterFieldTypesLabelsEachRejectionReason() {
        let body = Data(#"""
        {"five_hour":{"utilization":150,"resets_at":null},
         "seven_day":{"utilization":true,"resets_at":"garbage 2026"}}
        """#.utf8)
        let types = ClaudeUsageProvider.meterFieldTypes(of: body)
        XCTAssertEqual(types, "five_hour{utilization:number(out-of-range),resets_at:null} seven_day{utilization:bool,resets_at:string(unparsable)}")
        XCTAssertFalse(types.contains("150"))
        XCTAssertFalse(types.contains("garbage"))
    }

    func testMeterFieldTypesMissingOrNonObjectMeter() {
        let body = Data(#"{"five_hour":null,"seven_day":{"utilization":"16"}}"#.utf8)
        XCTAssertEqual(
            ClaudeUsageProvider.meterFieldTypes(of: body),
            "five_hour:null seven_day{utilization:string,resets_at:missing}"
        )
        XCTAssertEqual(ClaudeUsageProvider.meterFieldTypes(of: Data("{}".utf8)), "five_hour:missing seven_day:missing")
        XCTAssertEqual(ClaudeUsageProvider.meterFieldTypes(of: Data("[1]".utf8)), "<not a JSON object>")
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
