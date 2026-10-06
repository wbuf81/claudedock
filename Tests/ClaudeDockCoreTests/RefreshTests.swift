import Foundation
import Testing
@testable import ClaudeDockCore

private let weekly = Data(#"{"limits":[{"kind":"weekly_all","percent":40,"resets_at":"2026-10-09T08:00:00Z"}]}"#.utf8)
/// A plan with a 5-hour window but no weekly limit (a free plan may look like this).
private let sessionOnly = Data(#"{"limits":[{"kind":"session","percent":10,"resets_at":null}]}"#.utf8)

private final class Asked: @unchecked Sendable { var ids: [String] = [] }

@Suite struct UsageRoundTests {
    @Test func oneUnreadableOrgDoesNotBlankTheOthers() async throws {
        let outcome = try await UsageRound.run([pikachu, charizard], at: designNow) { org in
            org == pikachu ? weekly : sessionOnly
        }
        #expect(outcome.readings.map(\.org) == ["pikachu"])
        #expect(outcome.readings.first?.week == 40)
        #expect(outcome.failures == [UsageRound.Failure(org: charizard, problem: .noWeeklyLimit)])
    }

    @Test func aRefusedOrgOnlyLosesItsOwnReading() async throws {
        let outcome = try await UsageRound.run([pikachu, charizard], at: designNow) { org in
            if org == pikachu { throw WebSessionError.forbidden }
            return weekly
        }
        #expect(outcome.readings.map(\.org) == ["charizard"])
        #expect(outcome.failures == [UsageRound.Failure(org: pikachu, problem: .refused)])
    }

    @Test func signingOutEndsTheRound() async {
        let asked = Asked()
        await #expect(throws: WebSessionError.signedOut) {
            try await UsageRound.run([pikachu, charizard], at: designNow) { org in
                asked.ids.append(org.id)
                throw WebSessionError.signedOut
            }
        }
        #expect(asked.ids == ["pikachu"])
    }
}

@Suite struct RefreshProblemTests {
    @Test func errorsBecomeProblems() {
        #expect(RefreshProblem(WebSessionError.blocked) == .blocked)
        #expect(RefreshProblem(WebSessionError.notReady) == .offline)
        #expect(RefreshProblem(WebSessionError.forbidden) == .refused)
        #expect(RefreshProblem(WebSessionError.http(503)) == .http(503))
        #expect(RefreshProblem(WebSessionError.badResult) == .unreadable)
        #expect(RefreshProblem(UsageParserError.notJSON) == .unreadable)
        #expect(RefreshProblem(UsageParserError.unreadableResetTime) == .unreadable)
        #expect(RefreshProblem(UsageParserError.noWeeklyLimit) == .noWeeklyLimit)
        // A fetch() that couldn't connect fails inside the page's script.
        #expect(RefreshProblem(URLError(.notConnectedToInternet)) == .offline)
    }

    @Test func whenEverythingFailsTheLineSaysWhatHappened() {
        #expect(Copy.problem(.offline) == "Can't reach claude.ai. Trying again in a few minutes.")
        #expect(Copy.problem(.blocked) == "claude.ai's bot check stopped Claude Dock. Trying again in a few minutes.")
        #expect(Copy.problem(.http(503)) == "claude.ai answered with error 503. Trying again in a few minutes.")
        #expect(Copy.problem(.unreadable) == "claude.ai answered in a way Claude Dock can't read; its usage page may have changed.")
        #expect(Copy.problem(.refused) == "claude.ai refused to share usage.")
    }

    @Test func whenSomeOrgsFailTheLineNamesThem() {
        let failures = [UsageRound.Failure(org: charizard, problem: .noWeeklyLimit)]
        #expect(Copy.problem(failures, shown: 2) == "Couldn't read Charizard: no weekly limit.")
        #expect(Copy.problem([], shown: 2) == nil)
        let both = [UsageRound.Failure(org: pikachu, problem: .refused), UsageRound.Failure(org: charizard, problem: .refused)]
        #expect(Copy.problem(both, shown: 2) == "claude.ai refused to share usage for Pikachu and Charizard.")
        let personal = Org(id: "personal", name: "Personal")
        #expect(Copy.problem([UsageRound.Failure(org: personal, problem: .noWeeklyLimit)], shown: 1)
                == "claude.ai shows no weekly limit for Personal.")
    }

    @Test func theWidgetGetsAShortForm() {
        #expect(RefreshProblem.offline.short == "no connection")
        #expect(RefreshProblem.blocked.short == "blocked by a bot check")
        #expect(RefreshProblem.http(500).short == "claude.ai error 500")
        #expect(RefreshProblem.noWeeklyLimit.short == "no weekly limit")
    }
}
