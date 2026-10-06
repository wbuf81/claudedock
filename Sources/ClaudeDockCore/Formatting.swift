import Foundation

/// Short time and number text used across the widget and panel.
public struct Formatting: Sendable {
    public var calendar: Calendar
    public var locale: Locale

    public init(calendar: Calendar = .current, locale: Locale = Locale(identifier: "en_US_POSIX")) {
        self.calendar = calendar
        self.locale = locale
    }

    /// "4:20 PM" or "4 PM" on the same day as `now`; "Fri 4 AM" or "Wed 9:30 PM" otherwise.
    public func dayTime(_ date: Date, now: Date) -> String {
        let time = format(date, calendar.component(.minute, from: date) == 0 ? "h a" : "h:mm a")
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
