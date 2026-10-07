import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct InUseTests {
    /// This 5-hour window's and this week's reset times.
    let windowReset = designNow.addingTimeInterval(3 * 3600)
    let weekReset = designNow.addingTimeInterval(50 * 3600)

    func r(session: Double, sessionResetsAt: Date?, week: Double = 40, ago: TimeInterval = 0) -> Reading {
        reading(week: week, weekResetsAt: weekReset, session: session, sessionResetsAt: sessionResetsAt,
                at: designNow.addingTimeInterval(-ago))
    }

    func inUse(latest: Reading? = nil, previous: Reading? = nil, claudeCodeOrg: String? = nil,
               activeAgo: TimeInterval? = nil, stale: Bool = false, now: Date = designNow) -> Bool {
        InUse.isInUse(org: "pikachu", latest: latest, previous: previous, claudeCodeOrg: claudeCodeOrg,
                      claudeCodeActiveAt: activeAgo.map { now.addingTimeInterval(-$0) }, stale: stale, now: now)
    }

    @Test func claudeCodeWorkingOnThisOrg() {
        #expect(inUse(claudeCodeOrg: "pikachu", activeAgo: 59))
        #expect(!inUse(claudeCodeOrg: "pikachu", activeAgo: 61))
        #expect(!inUse(claudeCodeOrg: "charizard", activeAgo: 5))
        #expect(!inUse(claudeCodeOrg: "pikachu", activeAgo: nil))
    }

    @Test func usageRoseAtTheNewestReading() {
        let before = r(session: 10, sessionResetsAt: windowReset, ago: 180)
        let after = r(session: 12, sessionResetsAt: windowReset)
        #expect(inUse(latest: after, previous: before))
        #expect(inUse(latest: after, previous: before, now: designNow.addingTimeInterval(239)))
        #expect(!inUse(latest: after, previous: before, now: designNow.addingTimeInterval(241)))
        #expect(!inUse(latest: before, previous: before))
    }

    @Test func weeklyRiseCountsToo() {
        #expect(inUse(latest: r(session: 0, sessionResetsAt: nil, week: 41),
                      previous: r(session: 0, sessionResetsAt: nil, week: 40, ago: 180)))
    }

    @Test func aResetIsNotARiseButNewUseIs() {
        let before = r(session: 85, sessionResetsAt: designNow.addingTimeInterval(-60), ago: 180)
        #expect(!inUse(latest: r(session: 0, sessionResetsAt: nil), previous: before))
        // A window opens on first use, so a new one that already shows use is a rise.
        #expect(inUse(latest: r(session: 2, sessionResetsAt: designNow.addingTimeInterval(5 * 3600)), previous: before))
        #expect(inUse(latest: r(session: 1, sessionResetsAt: windowReset),
                      previous: r(session: 0, sessionResetsAt: nil, ago: 180)))
    }

    @Test func resetTimesASecondApartAreTheSameWindow() {
        #expect(!inUse(latest: r(session: 12, sessionResetsAt: windowReset.addingTimeInterval(1)),
                       previous: r(session: 12, sessionResetsAt: windowReset, ago: 180)))
    }

    @Test func needsTwoReadingsCloseTogether() {
        let after = r(session: 12, sessionResetsAt: windowReset)
        #expect(!inUse(latest: after, previous: nil))
        // The reading before is from hours ago (the app was closed): not "just now".
        #expect(!inUse(latest: after, previous: r(session: 10, sessionResetsAt: windowReset, ago: 2 * 3600)))
    }

    @Test func nothingWhileStale() {
        #expect(!inUse(latest: r(session: 12, sessionResetsAt: windowReset),
                       previous: r(session: 10, sessionResetsAt: windowReset, ago: 180), stale: true))
        #expect(!inUse(claudeCodeOrg: "pikachu", activeAgo: 5, stale: true))
    }
}
