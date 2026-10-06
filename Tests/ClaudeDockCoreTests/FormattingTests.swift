import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct FormattingTests {
    @Test func sameDayShowsTimeOnly() {
        #expect(fmt.dayTime(local(2026, 10, 6, 16, 20), now: designNow) == "4:20 PM")
        #expect(fmt.dayTime(local(2026, 10, 6, 16, 0), now: designNow) == "4 PM")
    }

    @Test func otherDayShowsWeekday() {
        #expect(fmt.dayTime(local(2026, 10, 9, 4, 0), now: designNow) == "Fri 4 AM")
        #expect(fmt.dayTime(local(2026, 10, 7, 21, 0), now: designNow) == "Wed 9 PM")
        #expect(fmt.dayTime(local(2026, 10, 7, 21, 30), now: designNow) == "Wed 9:30 PM")
    }

    @Test func compactDurations() {
        #expect(Formatting.compact(34 * 3600 + 20 * 60) == "1d 10h")
        #expect(Formatting.compact(3 * 3600 + 5 * 60) == "3h 5m")
        #expect(Formatting.compact(12 * 60) == "12m")
        #expect(Formatting.compact(2 * 3600) == "2h")
        #expect(Formatting.compact(-5) == "0m")
    }

    @Test func percents() {
        #expect(Formatting.percent(54.6) == "55%")
        #expect(Formatting.percent(0) == "0%")
    }

    @Test func weekStart() {
        #expect(fmt.weekStartLabel(local(2026, 10, 5)) == "Mon Oct 5")
    }
}
