import XCTest
@testable import Claude_Meters

final class AppVersionTests: XCTestCase {

    func testParsesPlainAndPrefixedVersions() {
        XCTAssertEqual(AppVersion("0.1.8")?.components, [0, 1, 8])
        XCTAssertEqual(AppVersion("v0.1.8")?.components, [0, 1, 8])
        XCTAssertEqual(AppVersion("V0.2.0")?.components, [0, 2, 0])
        XCTAssertEqual(AppVersion(" v0.1.8\n")?.components, [0, 1, 8])
        XCTAssertEqual(AppVersion("v0.1.8")?.description, "0.1.8")
    }

    func testRejectsNonNumericOrMalformedVersions() {
        for text in ["", "v", "0.2.0-beta", "0.1.x", "1..2", "1.2.", ".1", "+1.2", "-1.2", "１.２", "latest"] {
            XCTAssertNil(AppVersion(text), "\"\(text)\" should be rejected")
        }
    }

    func testComparesNumericallyNotAsStrings() {
        XCTAssertLessThan(AppVersion("0.1.9")!, AppVersion("0.2.0")!)
        XCTAssertLessThan(AppVersion("0.1.9")!, AppVersion("0.1.10")!)
        XCTAssertLessThan(AppVersion("0.1.8")!, AppVersion("v0.1.9")!)
        XCTAssertGreaterThan(AppVersion("1.0.0")!, AppVersion("0.9.9")!)
    }

    func testMissingTrailingComponentsCountAsZero() {
        XCTAssertEqual(AppVersion("0.1")!, AppVersion("0.1.0")!)
        XCTAssertLessThan(AppVersion("0.1")!, AppVersion("0.1.1")!)
        XCTAssertGreaterThan(AppVersion("0.2")!, AppVersion("0.1.9")!)
    }
}
