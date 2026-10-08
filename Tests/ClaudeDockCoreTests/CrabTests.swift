import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct CrabTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func s(_ pid: Int32, _ mood: CrabMood, ago: TimeInterval) -> CrabSession {
        CrabSession(pid: pid, mood: mood, time: now.addingTimeInterval(-ago))
    }
    let alive: (Int32) -> Bool = { _ in true }

    @Test func parsesTheHookFile() {
        #expect(Crab.parse("tool 1800000000\n", pid: 42) == CrabSession(pid: 42, mood: .tool, time: Date(timeIntervalSince1970: 1_800_000_000)))
        #expect(Crab.parse("permission 1800000000", pid: 7)?.mood == .permission)
        #expect(Crab.parse("", pid: 1) == nil)
        #expect(Crab.parse("dancing 1800000000", pid: 1) == nil)
        #expect(Crab.parse("tool soon", pid: 1) == nil)
    }

    @Test func noSessionsNoCrab() {
        #expect(Crab.mood([], isAlive: alive, now: now) == nil)
    }

    @Test func eachMoodShowsAsWritten() {
        for mood in CrabMood.allCases {
            #expect(Crab.mood([s(1, mood, ago: 2)], isAlive: alive, now: now) == mood)
        }
    }

    @Test func mostUrgentWins() {
        let sessions = [s(1, .thinking, ago: 1), s(2, .permission, ago: 5), s(3, .tool, ago: 1), s(4, .done, ago: 1)]
        #expect(Crab.mood(sessions, isAlive: alive, now: now) == .permission)
        #expect(Crab.mood([s(1, .idle, ago: 1), s(2, .done, ago: 1)], isAlive: alive, now: now) == .done)
    }

    @Test func doneTurnsIdleAfterTenSeconds() {
        #expect(Crab.mood([s(1, .done, ago: 9.9)], isAlive: alive, now: now) == .done)
        #expect(Crab.mood([s(1, .done, ago: 10)], isAlive: alive, now: now) == .idle)
    }

    @Test func aStuckMoodTurnsIdleAfterTenMinutes() {
        #expect(Crab.mood([s(1, .permission, ago: 599)], isAlive: alive, now: now) == .permission)
        #expect(Crab.mood([s(1, .tool, ago: 600)], isAlive: alive, now: now) == .idle)
    }

    // Review focus: a session killed with kill -9 never sends SessionEnd.
    @Test func deadProcessesDontCount() {
        let sessions = [s(1, .permission, ago: 1), s(2, .thinking, ago: 1)]
        #expect(Crab.mood(sessions, isAlive: { $0 == 2 }, now: now) == .thinking)
        #expect(Crab.mood(sessions, isAlive: { _ in false }, now: now) == nil)
    }

    // Review focus: after a reboot an old pid can belong to another process.
    @Test func oldFilesExpire() {
        #expect(Crab.mood([s(1, .idle, ago: 12 * 3600 - 1)], isAlive: alive, now: now) == .idle)
        #expect(Crab.mood([s(1, .idle, ago: 12 * 3600)], isAlive: alive, now: now) == nil)
    }

    @Test func nextChangeIsTheEarliestTimedEdge() {
        #expect(Crab.nextChange([s(1, .done, ago: 4), s(2, .tool, ago: 100)], now: now) == now.addingTimeInterval(6))
        #expect(Crab.nextChange([s(1, .tool, ago: 100)], now: now) == now.addingTimeInterval(500))
        #expect(Crab.nextChange([s(1, .idle, ago: 100), s(2, .done, ago: 30)], now: now) == nil)
    }

    @Test func withoutHooksTheFolderWatchDrivesIt() {
        #expect(Crab.fallbackMood(claudeCodeActiveAt: nil, now: now) == nil)
        #expect(Crab.fallbackMood(claudeCodeActiveAt: now.addingTimeInterval(-59), now: now) == .tool)
        #expect(Crab.fallbackMood(claudeCodeActiveAt: now.addingTimeInterval(-65), now: now) == .done)
        #expect(Crab.fallbackMood(claudeCodeActiveAt: now.addingTimeInterval(-70), now: now) == nil)
    }
}
