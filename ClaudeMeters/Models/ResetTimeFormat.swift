import Foundation

/// The absolute reset time shown under the relative "in 3d" label in the
/// Popover: just the time when the reset is later today, otherwise the weekday
/// and time ("Wed 22:00"). No date, since the reset is at most a week away.
enum ResetTimeFormat {
    static func string(for date: Date, now: Date, locale: Locale, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone

        // `j` follows the locale's 12/24-hour convention instead of forcing one.
        var template = "jmm"
        if !calendar.isDate(date, inSameDayAs: now) {
            // Abbreviated: some languages' full weekday names are long enough
            // to crowd the two-column layout.
            template = "EEE \(template)"
        }
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
