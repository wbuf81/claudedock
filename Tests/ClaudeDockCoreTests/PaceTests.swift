import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct PaceTests {
    // The spec's worked example: 55% used, 103.4 h elapsed, 64.6 h left, 11:32 AM.
    let reset = designNow.addingTimeInterval(64.6 * 3600)

    @Test func workedExample() throws {
        let f = try #require(Pace.forecast(reading(week: 55, weekResetsAt: reset), history: [], now: designNow, calendar: newYork))
        #expect(near(f.useItAllPerDay, 16.72))
        #expect(near(f.pacePerDay, 12.77))
        #expect(near(f.unused, 10.64))
        #expect(near(f.byMidnight, 8.68))
        #expect(near(f.elapsedFraction, 103.4 / 168, 0.001))
        #expect(f.runsOutEarlyByHours == nil)
    }

    @Test func usesTheReadingFrom72HoursAgo() throws {
        let old = reading(week: 20, weekResetsAt: reset, at: designNow.addingTimeInterval(-80 * 3600))
        let f = try #require(Pace.forecast(reading(week: 55, weekResetsAt: reset), history: [old], now: designNow, calendar: newYork))
        #expect(near(f.pacePerHour, 35.0 / 80, 0.0001))
        #expect(near(f.unused, 100 - (55 + 35.0 / 80 * 64.6)))
    }

    @Test func ignoresReadingsFromAnotherWindow() throws {
        let old = reading(week: 20, weekResetsAt: reset.addingTimeInterval(-Pace.window), at: designNow.addingTimeInterval(-80 * 3600))
        let f = try #require(Pace.forecast(reading(week: 55, weekResetsAt: reset), history: [old], now: designNow, calendar: newYork))
        #expect(near(f.pacePerDay, 12.77))
    }

    @Test func ignoresOtherOrgs() throws {
        let old = reading(org: "charizard", week: 20, weekResetsAt: reset, at: designNow.addingTimeInterval(-80 * 3600))
        let f = try #require(Pace.forecast(reading(week: 55, weekResetsAt: reset), history: [old], now: designNow, calendar: newYork))
        #expect(near(f.pacePerDay, 12.77))
    }

    @Test func runsOutEarly() throws {
        let f = try #require(Pace.forecast(reading(week: 90, weekResetsAt: reset), history: [], now: designNow, calendar: newYork))
        let pace = 90 / 103.4
        #expect(near(f.runsOutEarlyByHours!, 64.6 - 10 / pace))
        #expect(f.unused == 0)
        #expect(f.forecastAtReset == 100)
        #expect(near(f.runsOutAt!.timeIntervalSince(designNow) / 3600, 10 / pace))
    }

    // Review Focus 3
    @Test func zeroPaceMeansEverythingLeftGoesUnused() throws {
        let old = reading(week: 55, weekResetsAt: reset, at: designNow.addingTimeInterval(-80 * 3600))
        let f = try #require(Pace.forecast(reading(week: 55, weekResetsAt: reset), history: [old], now: designNow, calendar: newYork))
        #expect(f.pacePerHour == 0)
        #expect(f.unused == 45)
        #expect(f.runsOutEarlyByHours == nil)
    }

    // Review Focus 1
    @Test func noForecastBeforeTheWeekStartsOrAfterItEnds() {
        #expect(Pace.forecast(reading(week: 0, weekResetsAt: nil), history: [], now: designNow, calendar: newYork) == nil)
        #expect(Pace.forecast(reading(week: 50, weekResetsAt: designNow.addingTimeInterval(-60)), history: [], now: designNow, calendar: newYork) == nil)
    }

    @Test func byMidnightIsCappedAtReset() throws {
        let soon = local(2026, 10, 6, 16, 0)
        let f = try #require(Pace.forecast(reading(week: 70, weekResetsAt: soon), history: [], now: designNow, calendar: newYork))
        #expect(near(f.byMidnight, 30))
    }
}
