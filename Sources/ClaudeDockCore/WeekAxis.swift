import Foundation

/// One day on the week axis: its name, where it starts, and its middle (for the label).
public struct DayMark: Equatable, Sendable {
    public var name: String
    public var start: Double
    public var center: Double
}

/// The Monday-to-Sunday calendar week every chart is drawn on, so both orgs' days line
/// up even though their limits reset at different times. Positions are shares of the
/// week: 0 at Monday 00:00, 1 at the next Monday 00:00.
public struct WeekAxis: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let calendar: Calendar

    public init(containing date: Date, calendar: Calendar = .autoupdatingCurrent) {
        var monday = calendar
        monday.firstWeekday = 2
        let week = monday.dateInterval(of: .weekOfYear, for: date)!
        start = week.start
        end = week.end
        self.calendar = monday
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Not clamped: dates outside the week map below 0 or above 1.
    public func x(_ date: Date) -> Double { date.timeIntervalSince(start) / duration }

    public func contains(_ date: Date) -> Bool { date >= start && date <= end }

    /// The eight midnights from this Monday to the next.
    public var midnights: [Date] {
        (0...7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    public var days: [DayMark] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        let nights = midnights
        return (0..<7).map { i in
            let a = x(nights[i]), b = x(nights[i + 1])
            return DayMark(name: formatter.string(from: nights[i]), start: a, center: (a + b) / 2)
        }
    }

    /// Where today's column sits.
    public func today(_ now: Date) -> ClosedRange<Double> {
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return x(dayStart)...x(dayEnd)
    }
}
