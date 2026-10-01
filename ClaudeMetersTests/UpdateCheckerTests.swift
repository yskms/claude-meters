import XCTest
@testable import Claude_Meters

@MainActor
final class UpdateCheckerTests: XCTestCase {

    // MARK: - LatestRelease.parseTag

    func testParseTagReturnsTagName() throws {
        let data = Data(#"{"tag_name": "v0.1.8", "name": "v0.1.8"}"#.utf8)
        XCTAssertEqual(try LatestRelease.parseTag(statusCode: 200, data: data), "v0.1.8")
    }

    func testParseTagRejectsNon2xxStatus() {
        XCTAssertThrowsError(try LatestRelease.parseTag(statusCode: 404, data: Data("{}".utf8))) { error in
            guard case UpdateCheckError.unexpectedStatus(404) = error else {
                return XCTFail("expected .unexpectedStatus(404), got \(error)")
            }
        }
    }

    func testParseTagRejectsMissingOrNonStringTagName() {
        for body in ["{}", #"{"tag_name": 8}"#, #"{"tag_name": null}"#, "[]", "not json"] {
            XCTAssertThrowsError(try LatestRelease.parseTag(statusCode: 200, data: Data(body.utf8)), body) { error in
                guard case UpdateCheckError.invalidResponse = error else {
                    return XCTFail("expected .invalidResponse for \(body), got \(error)")
                }
            }
        }
    }

    // MARK: - UpdateChecker.check

    private func makeChecker(current: String = "0.1.8", fetch: @escaping () async throws -> String) -> UpdateChecker {
        UpdateChecker(currentVersion: current, fetchLatestTag: fetch)
    }

    func testNewerTagMakesUpdateAvailable() async {
        let checker = makeChecker { "v0.1.9" }
        await checker.check()
        XCTAssertEqual(checker.state, .updateAvailable(version: "0.1.9"))
    }

    func testSameTagIsUpToDate() async {
        let checker = makeChecker { "v0.1.8" }
        await checker.check()
        XCTAssertEqual(checker.state, .upToDate)
    }

    func testOlderTagIsUpToDate() async {
        let checker = makeChecker(current: "0.2.0") { "v0.1.9" }
        await checker.check()
        XCTAssertEqual(checker.state, .upToDate)
    }

    func testFetchErrorFails() async {
        let checker = makeChecker { throw UpdateCheckError.unexpectedStatus(403) }
        await checker.check()
        XCTAssertEqual(checker.state, .failed)
    }

    func testUnparseableTagFails() async {
        let checker = makeChecker { "v0.2.0-beta" }
        await checker.check()
        XCTAssertEqual(checker.state, .failed)
    }

    func testUnparseableCurrentVersionFails() async {
        let checker = makeChecker(current: "") { "v0.1.9" }
        await checker.check()
        XCTAssertEqual(checker.state, .failed)
    }

    func testResetIfFinishedClearsOnlyUpToDateAndFailed() async {
        let upToDate = makeChecker { "v0.1.8" }
        await upToDate.check()
        upToDate.resetIfFinished()
        XCTAssertEqual(upToDate.state, .idle)

        let failed = makeChecker { throw UpdateCheckError.invalidResponse }
        await failed.check()
        failed.resetIfFinished()
        XCTAssertEqual(failed.state, .idle)

        let available = makeChecker { "v0.1.9" }
        await available.check()
        available.resetIfFinished()
        XCTAssertEqual(available.state, .updateAvailable(version: "0.1.9"))
    }

    func testSecondCheckWhileCheckingIsIgnored() async {
        var fetchCount = 0
        let checker = makeChecker {
            fetchCount += 1
            try await Task.sleep(nanoseconds: 100_000_000)
            return "v0.1.9"
        }
        async let first: Void = checker.check()
        // Let the first call reach its suspension point so state is .checking.
        await Task.yield()
        XCTAssertEqual(checker.state, .checking)
        await checker.check()
        await first
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(checker.state, .updateAvailable(version: "0.1.9"))
    }
}
