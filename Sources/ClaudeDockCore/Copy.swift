import Foundation

/// The sentences the widget and panel show, kept here so they can be tested.
public enum Copy {
    public struct Today: Equatable, Sendable {
        public var main: String
        public var warning: String?
    }

    /// Under the widget's 5-hour bar.
    public static func widgetSubline(_ r: Reading, light: Light, forecast: WeekForecast?, now: Date,
                                     formatting: Formatting, _ t: Thresholds = Thresholds()) -> String {
        if light == .red, let back = backTime(r, t) {
            return "back \(formatting.dayTime(back, now: now))" + (r.sessionResetsAt == nil ? " · 5h idle" : "")
        }
        guard let reset = r.sessionResetsAt else { return "5h idle" }
        let into = now.timeIntervalSince(reset.addingTimeInterval(-5 * 3600))
        return "5h: \(Formatting.percent(r.session)) used · \(Formatting.compact(into)) in"
    }

    /// When a red org can be used again: its week reset if the week is nearly out, its
    /// 5-hour reset if that window is maxed; nil when it's red only for running out early.
    public static func backTime(_ r: Reading, _ t: Thresholds) -> Date? {
        if r.weekLeft < t.redWeekLeft { return r.weekResetsAt }
        if r.session >= t.redSession { return r.sessionResetsAt }
        return nil
    }

    /// "62% of the week gone · resets Fri 4 AM"
    public static func weekLine(_ r: Reading, forecast: WeekForecast?, now: Date, formatting: Formatting) -> String {
        guard let forecast, let reset = r.weekResetsAt else { return "this week hasn't started" }
        return "\(Formatting.percent(forecast.elapsedFraction * 100)) of the week gone · resets \(formatting.dayTime(reset, now: now))"
    }

    /// The panel's TODAY box.
    public static func today(_ r: Reading, forecast: WeekForecast?, now: Date,
                             formatting: Formatting, _ t: Thresholds = Thresholds()) -> Today {
        guard let f = forecast, let reset = r.weekResetsAt else {
            return Today(main: "This week hasn't started. Nothing is used yet.", warning: nil)
        }
        let resetText = formatting.dayTime(reset, now: now)
        if r.weekLeft < t.redWeekLeft {
            var main = "Only \(Formatting.percent(r.weekLeft)) left until \(resetText)"
            if f.pacePerHour > 0 { main += ", about \(hours(r.weekLeft / f.pacePerHour)) at your recent pace" }
            return Today(main: main + ".", warning: nil)
        }
        if let out = f.runsOutAt, let early = f.runsOutEarlyByHours {
            return Today(
                main: "Ease off to about \(Formatting.percent(f.useItAllPerDay)) a day to last until \(resetText).",
                warning: "At your current ~\(Formatting.percent(f.pacePerDay)) a day it runs out \(formatting.dayTime(out, now: now)), \(Formatting.compact(early * 3600)) early.")
        }
        let main: String
        if f.byMidnight >= r.weekLeft - 0.001 {
            main = "Use the last \(Formatting.percent(r.weekLeft)) before \(resetText)."
        } else {
            main = "Use about \(Formatting.percent(f.byMidnight)) more by midnight (to ~\(Formatting.percent(r.week + f.byMidnight)) used), then about \(Formatting.percent(f.useItAllPerDay)) a day."
        }
        let warning = f.unused >= t.onPaceUnused
            ? "At your current ~\(Formatting.percent(f.pacePerDay)) a day, about \(Formatting.percent(f.unused)) goes unused by \(resetText)."
            : nil
        return Today(main: main, warning: warning)
    }

    static func hours(_ h: Double) -> String {
        h < 1 ? "\(max(Int(h * 60), 1)) minutes" : "\(Int(h.rounded())) hours"
    }
}
