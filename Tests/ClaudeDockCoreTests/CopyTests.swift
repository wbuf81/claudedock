import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct CopyTests {
    let primary = reading(week: 55, weekResetsAt: local(2026, 10, 9, 4), session: 1,
                          sessionResetsAt: local(2026, 10, 6, 16, 20))
    let overflow = reading(org: "charizard", week: 95, weekResetsAt: local(2026, 10, 7, 21))

    func forecast(_ r: Reading) -> WeekForecast? { Pace.forecast(r, history: [], now: designNow, calendar: newYork) }
    func light(_ r: Reading) -> Light { Stoplight.light(r, forecast(r)) }

    @Test func todayForTheDesignDayPrimary() {
        let today = Copy.today(primary, forecast: forecast(primary), now: designNow, formatting: fmt)
        #expect(today.main == "Use about 9% more by midnight (to ~64% used), then about 17% a day.")
        #expect(today.warning == "At your current ~13% a day, about 11% goes unused by Fri 4 AM.")
    }

    @Test func todayForANearlyOutOrg() {
        let today = Copy.today(overflow, forecast: forecast(overflow), now: designNow, formatting: fmt)
        #expect(today.main == "Only 5% left until Wed 9 PM, about 7 hours at your recent pace.")
        #expect(today.warning == nil)
    }

    @Test func todayWhenResetComesBeforeMidnight() {
        let r = reading(week: 70, weekResetsAt: local(2026, 10, 6, 16))
        let today = Copy.today(r, forecast: forecast(r), now: designNow, formatting: fmt)
        #expect(today.main == "Use the last 30% before 4 PM.")
        #expect(today.warning == "At your current ~10% a day, about 28% goes unused by 4 PM.")
    }

    @Test func todayWhenRunningOutEarly() {
        let r = reading(week: 80, weekResetsAt: local(2026, 10, 9, 4))
        let today = Copy.today(r, forecast: forecast(r), now: designNow, formatting: fmt)
        #expect(today.main == "Ease off to about 7% a day to last until Fri 4 AM.")
        #expect(today.warning?.hasPrefix("At your current ~19% a day it runs out ") == true)
    }

    // Review Focus 1
    @Test func todayBeforeTheWeekStarts() {
        let r = reading(week: 0, weekResetsAt: nil)
        #expect(Copy.today(r, forecast: nil, now: designNow, formatting: fmt).main
                == "This week hasn't started. Nothing is used yet.")
        #expect(Copy.weekLine(r, forecast: nil, now: designNow, formatting: fmt) == "this week hasn't started")
    }

    @Test func weekLine() {
        #expect(Copy.weekLine(primary, forecast: forecast(primary), now: designNow, formatting: fmt)
                == "62% of the week gone · resets Fri 4 AM")
    }

    // Every org's caption has the same shape: the 5-hour window, then when the week resets.
    @Test func widgetSublinesShareOneShape() {
        #expect(Copy.widgetSubline(primary, now: designNow, formatting: fmt) == "5h 1% · ↺ Fri 4 AM")
        #expect(Copy.widgetSubline(overflow, now: designNow, formatting: fmt) == "5h 0% · ↺ Wed 9 PM")
        let idle = reading(week: 20, weekResetsAt: local(2026, 10, 9, 4))
        #expect(Copy.widgetSubline(idle, now: designNow, formatting: fmt) == "5h 0% · ↺ Fri 4 AM")
        let fresh = reading(week: 0, weekResetsAt: nil)
        #expect(Copy.widgetSubline(fresh, now: designNow, formatting: fmt) == "5h 0% · week not started")
    }
}
