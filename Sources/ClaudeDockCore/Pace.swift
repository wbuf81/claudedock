import Foundation

/// Where a week's usage is heading. Percentages are of the weekly limit.
public struct WeekForecast: Equatable, Sendable {
    public var used: Double
    public var hoursLeft: Double
    /// Share of the 7-day window gone, 0...1.
    public var elapsedFraction: Double
    public var pacePerHour: Double
    public var forecastAtReset: Double
    /// What would be left unused at reset at the current pace.
    public var unused: Double
    /// Set when the current pace uses everything before reset.
    public var runsOutEarlyByHours: Double?
    public var runsOutAt: Date?
    /// The pace that uses exactly everything by reset.
    public var useItAllPerHour: Double
    /// How much more to use before local midnight to stay on the use-it-all pace.
    public var byMidnight: Double

    public var pacePerDay: Double { pacePerHour * 24 }
    public var useItAllPerDay: Double { useItAllPerHour * 24 }
}

public enum Pace {
    public static let window: TimeInterval = 7 * 24 * 3600
    static let lookback: TimeInterval = 72 * 3600

    /// nil when the week hasn't started or has already reset.
    public static func forecast(_ reading: Reading, history: [Reading], now: Date,
                                calendar: Calendar = .current) -> WeekForecast? {
        guard let reset = reading.weekResetsAt, reset > now else { return nil }
        let used = reading.week
        let left = 100 - used
        let hoursLeft = reset.timeIntervalSince(now) / 3600
        let hoursElapsed = max(now.timeIntervalSince(reset.addingTimeInterval(-window)) / 3600, 1.0 / 60)

        // Pace over the last 72 hours, measured from the newest reading in this window that
        // is at least that old. Without one, the average since the window started.
        var pace = used / hoursElapsed
        let cutoff = now.addingTimeInterval(-lookback)
        if let past = history
            .filter({ $0.org == reading.org && $0.weekResetsAt == reset && $0.time <= cutoff })
            .max(by: { $0.time < $1.time }) {
            pace = max((used - past.week) / (now.timeIntervalSince(past.time) / 3600), 0)
        }

        var runsOutEarly: Double?
        var runsOutAt: Date?
        if pace > 0, pace * hoursLeft > left {
            let hoursToEmpty = left / pace
            runsOutEarly = hoursLeft - hoursToEmpty
            runsOutAt = now.addingTimeInterval(hoursToEmpty * 3600)
        }
        let forecast = min(100, used + pace * hoursLeft)
        let useItAll = left / hoursLeft
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let hoursToMidnight = min(midnight.timeIntervalSince(now) / 3600, hoursLeft)

        return WeekForecast(
            used: used,
            hoursLeft: hoursLeft,
            elapsedFraction: min(hoursElapsed * 3600 / window, 1),
            pacePerHour: pace,
            forecastAtReset: forecast,
            unused: 100 - forecast,
            runsOutEarlyByHours: runsOutEarly,
            runsOutAt: runsOutAt,
            useItAllPerHour: useItAll,
            byMidnight: useItAll * hoursToMidnight
        )
    }
}
