import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct ModelsTests {
    @Test func weekLeftIsTheRest() {
        #expect(reading(week: 55, weekResetsAt: nil).weekLeft == 45)
    }

    @Test func passedSessionResetEmptiesTheSession() {
        let r = reading(week: 30, weekResetsAt: designNow.addingTimeInterval(36_000),
                        session: 40, sessionResetsAt: designNow.addingTimeInterval(-60))
        let now = r.adjusted(to: designNow)
        #expect(now.session == 0)
        #expect(now.sessionResetsAt == nil)
        #expect(now.week == 30)
    }

    @Test func passedWeekResetEmptiesTheWeek() {
        let r = reading(week: 80, weekResetsAt: designNow.addingTimeInterval(-60), scoped: ["Fable": 50])
        let now = r.adjusted(to: designNow)
        #expect(now.week == 0)
        #expect(now.weekResetsAt == nil)
        #expect(now.scoped == ["Fable": 0])
    }

    @Test func sessionElapsedFraction() {
        let r = reading(week: 0, weekResetsAt: nil, session: 1, sessionResetsAt: designNow.addingTimeInterval(4.8 * 3600))
        #expect(near(r.sessionElapsedFraction(now: designNow)!, 0.04, 0.001))
        #expect(reading(week: 0, weekResetsAt: nil).sessionElapsedFraction(now: designNow) == nil)
    }
}
