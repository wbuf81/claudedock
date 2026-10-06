import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct SessionResponseTests {
    @Test func okAndSignedOut() {
        #expect(SessionResponse.classify(status: 200, body: "[]") == .ok)
        #expect(SessionResponse.classify(status: 401, body: "<html></html>") == .signedOut)
        #expect(SessionResponse.classify(status: 401, body: #"{"type":"error"}"#) == .signedOut)
    }

    // Final review #1: a 403 bot-check page is not a sign-out.
    @Test func htmlForbiddenIsABotCheckNotASignOut() {
        #expect(SessionResponse.classify(status: 403, body: "<!DOCTYPE html><title>Just a moment...</title>") == .blocked)
        #expect(SessionResponse.classify(status: 403, body: "") == .blocked)
    }

    @Test func jsonForbiddenNeedsACloserLook() {
        #expect(SessionResponse.classify(status: 403, body: #"{"type":"error","error":{"type":"permission_error"}}"#) == .forbidden)
        #expect(SessionResponse.classify(status: 403, body: "  \n[]") == .forbidden)
    }

    @Test func otherStatusesFail() {
        #expect(SessionResponse.classify(status: 503, body: "") == .failed(503))
        #expect(SessionResponse.classify(status: 429, body: "{}") == .failed(429))
    }
}

@Suite struct PageLoadStateTests {
    // Final review #5: only one load at a time.
    @Test func oneLoadAtATime() {
        var page = PageLoadState()
        let first = page.claimLoad()
        let second = page.claimLoad()
        #expect(first && !second)
        page.finished(ok: true)
        let afterReady = page.claimLoad()
        #expect(page.isReady && !afterReady)
    }

    // Final review #2: a crashed page or failed script sends it back to needing a load.
    @Test func invalidatedPageReloads() {
        var page = PageLoadState()
        _ = page.claimLoad()
        page.finished(ok: true)
        page.invalidate()
        let reload = page.claimLoad()
        #expect(reload)
    }

    // A script killed by a load that's already running mustn't start a second load, which
    // would cancel the first and report it as "no connection".
    @Test func aFailedScriptDuringALoadLeavesTheLoadRunning() {
        var page = PageLoadState()
        _ = page.claimLoad()
        page.invalidate()
        let second = page.claimLoad()
        #expect(!second)
        page.finished(ok: true)
        #expect(page.isReady)
    }

    @Test func failedLoadCanBeRetried() {
        var page = PageLoadState()
        _ = page.claimLoad()
        page.finished(ok: false)
        #expect(!page.isReady)
        let retry = page.claimLoad()
        #expect(retry)
    }
}

@Suite struct SessionWatchTests {
    // Launching while signed out isn't news; losing a session that worked is.
    @Test func onlyASessionThatWorkedCanEnd() {
        var watch = SessionWatch()
        #expect(watch.ended() == false)
        watch.worked()
        #expect(watch.ended() == true)
        #expect(watch.ended() == false)
    }
}
