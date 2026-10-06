import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct WeekAxisTests {
    let axis = WeekAxis(containing: designNow, calendar: newYork)

    @Test func runsMondayToMonday() {
        #expect(axis.start == local(2026, 10, 5))
        #expect(axis.end == local(2026, 10, 12))
        #expect(axis.duration == 168 * 3600)
    }

    @Test func positionsAreShareOfTheWeek() {
        #expect(axis.x(local(2026, 10, 5)) == 0)
        #expect(near(axis.x(designNow), 35.5333 / 168, 0.0001))
        #expect(axis.x(local(2026, 10, 12)) == 1)
        #expect(axis.contains(designNow))
        #expect(!axis.contains(local(2026, 10, 12, 1)))
    }

    @Test func sundayBelongsToTheWeekBefore() {
        #expect(WeekAxis(containing: local(2026, 10, 11, 23), calendar: newYork).start == local(2026, 10, 5))
    }

    @Test func daysAndToday() {
        #expect(axis.days.map(\.name) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(near(axis.days[1].center, 1.5 / 7, 0.0001))
        let today = axis.today(designNow)
        #expect(near(today.lowerBound, 1.0 / 7, 0.0001))
        #expect(near(today.upperBound, 2.0 / 7, 0.0001))
        #expect(axis.midnights.count == 8)
    }

    @Test func daylightSavingWeekHas169Hours() {
        let dst = WeekAxis(containing: local(2026, 10, 28), calendar: newYork)
        #expect(dst.start == local(2026, 10, 26))
        #expect(dst.duration == 169 * 3600)
        #expect(dst.days.last?.name == "Sun")
    }
}
