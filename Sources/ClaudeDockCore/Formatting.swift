import Foundation

/// Short time and number text used across the widget and panel. The words are English, so
/// day names are too; the clock is 12- or 24-hour as the Mac's region prefers.
public struct Formatting: Sendable {
    public var calendar: Calendar
    public var twentyFourHour: Bool
    private let locale = Locale(identifier: "en_US_POSIX")

    /// The calendar follows the Mac's time zone as it changes.
    public init(calendar: Calendar = .autoupdatingCurrent, twentyFourHour: Bool = Formatting.prefers24Hour()) {
        self.calendar = calendar
        self.twentyFourHour = twentyFourHour
    }

    /// Whether a region writes times on a 24-hour clock.
    public static func prefers24Hour(_ locale: Locale = .autoupdatingCurrent) -> Bool {
        !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "a").contains("a")
    }

    /// "4:20 PM" or "4 PM" on the same day as `now`; "Fri 4 AM" or "Wed 9:30 PM" otherwise.
    /// On a 24-hour clock: "16:20", "Fri 04:00".
    public func dayTime(_ date: Date, now: Date) -> String {
        let pattern = twentyFourHour ? "HH:mm" : calendar.component(.minute, from: date) == 0 ? "h a" : "h:mm a"
        let time = format(date, pattern)
        return calendar.isDate(date, inSameDayAs: now) ? time : "\(format(date, "EEE")) \(time)"
    }

    /// "Mon Oct 5"
    public func weekStartLabel(_ date: Date) -> String { format(date, "EEE MMM d") }

    /// "1d 10h", "3h 5m", "2h" or "12m". Negative intervals read as "0m".
    public static func compact(_ interval: TimeInterval) -> String {
        let minutes = max(Int(interval / 60), 0)
        let days = minutes / 1440, hours = (minutes % 1440) / 60, rest = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m" }
        return "\(rest)m"
    }

    /// "55%": whole numbers, rounded.
    public static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    private func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
