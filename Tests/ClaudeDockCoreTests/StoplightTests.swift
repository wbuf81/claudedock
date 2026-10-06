import Foundation
import Testing
@testable import ClaudeDockCore

func forecastWith(unused: Double, early: Double? = nil) -> WeekForecast {
    WeekForecast(used: 50, hoursLeft: 50, elapsedFraction: 0.7, pacePerHour: 1,
                 forecastAtReset: 100 - unused, unused: unused, runsOutEarlyByHours: early,
                 runsOutAt: early.map { designNow.addingTimeInterval($0 * 3600) },
                 useItAllPerHour: 1, byMidnight: 5)
}

@Suite struct StoplightTests {
    let resetSoon = designNow.addingTimeInterval(50 * 3600)

    func light(week: Double = 50, session: Double = 0, unused: Double = 15, early: Double? = nil,
               _ t: Thresholds = Thresholds()) -> Light {
        Stoplight.light(reading(week: week, weekResetsAt: resetSoon, session: session),
                        forecastWith(unused: unused, early: early), t)
    }

    @Test func red() {
        #expect(light(week: 91) == .red)                      // under 10% left
        #expect(light(unused: 0, early: 12) == .red)          // runs out 12h early
        #expect(light(session: 95) == .red)                   // 5-hour window maxed
    }

    @Test func yellow() {
        #expect(light(unused: 0, early: 11.9) == .yellow)     // runs out slightly early
        #expect(light(session: 80) == .yellow)
        #expect(light(unused: 4.9) == .yellow)                // on pace
        #expect(light(week: 90) != .red)                      // exactly 10% left is not red
    }

    @Test func greenPulseBuckets() {
        #expect(light(unused: 5) == .green(.slow))
        #expect(light(unused: 9.9) == .green(.slow))
        #expect(light(unused: 10) == .green(.normal))
        #expect(light(unused: 25) == .green(.normal))
        #expect(light(unused: 25.1) == .green(.fast))
    }

    // Review Focus 1
    @Test func weekNotStartedIsSteadyGreen() {
        #expect(Stoplight.light(reading(week: 0, weekResetsAt: nil), nil) == .green(nil))
        #expect(Stoplight.light(reading(week: 0, weekResetsAt: nil, session: 85), nil) == .yellow)
    }

    @Test func thresholdsAreAdjustable() {
        var t = Thresholds()
        t.redWeekLeft = 20
        #expect(light(week: 85, t) == .red)
    }

    @Test func defaultsMatchTheSpec() {
        let t = Thresholds()
        #expect([t.redWeekLeft, t.redRunsOutEarlyHours, t.redSession, t.yellowSession, t.onPaceUnused,
                 t.normalPulseUnused, t.fastPulseUnused, t.eligibleWeekLeft, t.eligibleSessionBelow,
                 t.primaryReserveWeekLeft] == [10, 12, 95, 80, 5, 10, 25, 10, 80, 15])
        #expect(Pulse.slow.rawValue == 2.8 && Pulse.normal.rawValue == 1.6 && Pulse.fast.rawValue == 0.9)
    }
}
