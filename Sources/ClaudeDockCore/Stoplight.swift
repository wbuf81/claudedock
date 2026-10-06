import Foundation

/// How fast a green dot pulses, in seconds per pulse.
public enum Pulse: Double, Equatable, Sendable {
    case slow = 2.8, normal = 1.6, fast = 0.9
}

/// "Should I be using this org right now?" Green (with a pulse, or steady when the week
/// hasn't started), yellow, or red.
public enum Light: Equatable, Sendable {
    case green(Pulse?)
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
    public var normalPulseUnused = 10.0
    public var fastPulseUnused = 25.0
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
            return reading.session >= t.yellowSession ? .yellow : .green(nil)
        }
        if reading.session >= t.yellowSession || forecast.unused < t.onPaceUnused || forecast.runsOutEarlyByHours != nil {
            return .yellow
        }
        if forecast.unused > t.fastPulseUnused { return .green(.fast) }
        if forecast.unused >= t.normalPulseUnused { return .green(.normal) }
        return .green(.slow)
    }
}
