import XCTest
@testable import Claude_Meters

final class ResetTimeFormatTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    /// 2026-11-04 is a Wednesday.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func format(_ reset: Date, now: Date, _ identifier: String) -> String {
        ResetTimeFormat.string(for: reset, now: now, locale: Locale(identifier: identifier), calendar: calendar)
    }

    func testSameDayShowsTimeOnly() {
        XCTAssertEqual(format(date(4, 22), now: date(4, 15), "ja_JP"), "22:00")
        XCTAssertEqual(format(date(4, 22), now: date(4, 15), "en_GB"), "22:00")
    }

    func testOtherDayAddsWeekday() {
        XCTAssertEqual(format(date(4, 22), now: date(2, 10), "ja_JP"), "水曜日 22:00")
        XCTAssertEqual(format(date(4, 22), now: date(2, 10), "en_GB"), "Wed 22:00")
    }

    /// A session that crosses midnight is the day after, not "later today".
    func testResetPastMidnightAddsWeekday() {
        XCTAssertEqual(format(date(5, 2, 30), now: date(4, 23), "ja_JP"), "木曜日 2:30")
    }

    /// The weekly reset can land on today's weekday a week from now; it is a
    /// different day, so the weekday still shows.
    func testSameWeekdayNextWeekAddsWeekday() {
        XCTAssertEqual(format(date(11, 22), now: date(4, 23), "en_GB"), "Wed 22:00")
    }

    /// The day boundary is the calendar's (local) midnight: one hour apart,
    /// but different days.
    func testDayBoundaryFollowsCalendarTimeZone() {
        XCTAssertEqual(format(date(5, 0, 30), now: date(4, 23, 30), "en_GB"), "Thu 00:30")
    }
}
