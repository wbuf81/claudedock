import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct WeekChartModelTests {
    let axis = WeekAxis(containing: designNow, calendar: newYork)

    func chart(_ r: Reading, history: [Reading] = []) -> WeekChartModel {
        WeekChartModel.make(axis: axis, now: designNow, reading: r,
                            forecast: Pace.forecast(r, history: history, now: designNow, calendar: newYork), history: history)
    }

    @Test func primaryOnDesignDay() {
        let c = chart(reading(week: 55, weekResetsAt: local(2026, 10, 9, 4)))
        #expect(near(c.nowX, 35.5333 / 168, 0.0001))
        #expect(c.nowY == 0.55)
        // The window began Friday, before this Monday: the line enters at the average value.
        #expect(c.past.count == 2)
        #expect(c.past[0].x == 0)
        #expect(near(c.past[0].y, 0.55 * 68 / 103.5333, 0.001))
        #expect(near(c.resetX!, 100.0 / 168, 0.0001))   // Mon 00:00 → Fri 4 AM = 100 h
        #expect(c.useItAll.last == ChartPoint(x: c.resetX!, y: 1))
        #expect(c.unused.count == 3)
        #expect(near(c.nextWindow.last!.y, 68.0 / 168, 0.001))
        #expect(c.nextWindow.last!.x == 1)
        #expect(c.days.count == 7)
    }

    @Test func historyFromThisWindowIsDrawn() {
        let reset = local(2026, 10, 9, 4)
        let earlier = reading(week: 40, weekResetsAt: reset, at: local(2026, 10, 5, 12))
        let c = chart(reading(week: 55, weekResetsAt: reset), history: [earlier])
        #expect(c.past.count == 3)
        #expect(c.past[1] == ChartPoint(x: axis.x(local(2026, 10, 5, 12)), y: 0.4))
    }

    @Test func runningOutFlattensAtTheTop() {
        let c = chart(reading(org: "charizard", week: 95, weekResetsAt: local(2026, 10, 7, 21)))
        #expect(c.yourPace.count == 3)
        #expect(c.yourPace[1].y == 1)
        #expect(c.yourPace[2].y == 1)
        #expect(c.unused.isEmpty)
    }

    @Test func resetAfterThisWeekIsClippedAtSunday() {
        let c = chart(reading(week: 10, weekResetsAt: local(2026, 10, 12, 6)))
        #expect(c.resetX == nil)
        #expect(c.nextWindow.isEmpty)
        #expect(c.useItAll.last!.x == 1)
        #expect(near(c.useItAll.last!.y, (10 + 90 * (132.4667 / 138.4667)) / 100, 0.001))
        #expect(c.unused.count == 3)
        #expect(c.unused[1].x == 1 && c.unused[2].x == 1)
    }

    // Final review #15: labels that would collide move out of each other's way.
    @Test func resetLabelJoinsTodayWhenTheyMeet() {
        let wednesday = local(2026, 10, 7, 10)
        let r = reading(org: "charizard", week: 95, weekResetsAt: local(2026, 10, 7, 21), at: wednesday)
        let onWednesday = WeekChartModel.make(axis: axis, now: wednesday, reading: r,
                                              forecast: Pace.forecast(r, history: [], now: wednesday, calendar: newYork), history: [])
        #expect(onWednesday.resetLabelMeetsToday)
        #expect(!chart(reading(org: "charizard", week: 95, weekResetsAt: local(2026, 10, 7, 21))).resetLabelMeetsToday)
    }

    @Test func nowLabelFlipsLeftNearTheEnd() {
        let sunday = local(2026, 10, 11, 20)
        let r = reading(week: 40, weekResetsAt: local(2026, 10, 13, 4), at: sunday)
        let late = WeekChartModel.make(axis: axis, now: sunday, reading: r,
                                       forecast: Pace.forecast(r, history: [], now: sunday, calendar: newYork), history: [])
        #expect(late.nowLabelOnLeft)
        #expect(!chart(reading(week: 55, weekResetsAt: local(2026, 10, 9, 4))).nowLabelOnLeft)
    }

    // The "now" label goes on whichever side of the dot has room: below it high in the
    // chart, above it low in the chart (below would run into the axis).
    @Test func nowLabelSitsOnTheRoomierSide() {
        #expect(chart(reading(week: 55, weekResetsAt: local(2026, 10, 9, 4))).nowLabelBelow)
        #expect(chart(reading(week: 95, weekResetsAt: local(2026, 10, 7, 21))).nowLabelBelow)
        #expect(!chart(reading(week: 30, weekResetsAt: local(2026, 10, 10, 15))).nowLabelBelow)
        #expect(!chart(reading(week: 0, weekResetsAt: nil)).nowLabelBelow)
    }

    // Review Focus 1
    @Test func weekNotStartedHasOnlyNow() {
        let c = chart(reading(week: 0, weekResetsAt: nil))
        #expect(c.past == [ChartPoint(x: c.nowX, y: 0)])
        #expect(c.useItAll.isEmpty && c.yourPace.isEmpty && c.unused.isEmpty && c.resetX == nil)
    }
}
