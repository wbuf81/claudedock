import Foundation

/// "Should I be using this org right now?" Green (tokens would go unused), yellow (on
/// pace) or red (nearly out).
public enum Light: Equatable, Sendable {
    case green
    case yellow
    case red
}

/// Every adjustable threshold, in percent or hours. Defaults are the spec's values.
public struct Thresholds: Codable, Equatable, Sendable {
    public var redWeekLeft = 10.0
    public var redRunsOutEarlyHours = 12.0
    public var redSession = 95.0
    public var yellowSession = 80.0
    public var onPaceUnused = 5.0
    public var eligibleWeekLeft = 10.0
    public var eligibleSessionBelow = 80.0
    public var primaryReserveWeekLeft = 15.0

    public init() {}
}

public enum Stoplight {
    /// First match wins: red, then yellow, then green.
    public static func light(_ reading: Reading, _ forecast: WeekForecast?, _ t: Thresholds = Thresholds()) -> Light {
        let early = forecast?.runsOutEarlyByHours ?? 0
        if reading.weekLeft < t.redWeekLeft || early >= t.redRunsOutEarlyHours || reading.session >= t.redSession {
            return .red
        }
        guard let forecast else {
            return reading.session >= t.yellowSession ? .yellow : .green
        }
        if reading.session >= t.yellowSession || forecast.unused < t.onPaceUnused || forecast.runsOutEarlyByHours != nil {
            return .yellow
        }
        return .green
    }
}
