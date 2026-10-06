import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct OrgFilterTests {
    let team = Org(id: "pikachu", name: "Pikachu", billingType: "stripe_subscription")
    let personalFree = Org(id: "personal", name: "Personal", billingType: nil)

    @Test func paidOrgsAreShownByDefault() {
        #expect(OrgFilter.defaultShown([team, personalFree]) == [team])
    }

    // A free-only account has no paid org; showing nothing left the widget on
    // "Loading usage…" forever.
    @Test func anAccountWithNoPaidOrgShowsWhatItHas() {
        #expect(OrgFilter.defaultShown([personalFree]) == [personalFree])
    }

    @Test func theOwnersChoiceWins() {
        #expect(OrgFilter.shown([team, personalFree], chosen: ["personal"]) == [personalFree])
        #expect(OrgFilter.shown([team, personalFree], chosen: nil) == [team])
    }

    // Choosing to hide every org falls back to the default rather than an empty widget.
    @Test func hidingEverythingFallsBackToTheDefault() {
        #expect(OrgFilter.shown([team, personalFree], chosen: []) == [team])
    }
}
