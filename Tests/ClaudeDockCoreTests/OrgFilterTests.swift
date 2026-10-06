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
        #expect(OrgFilter.shown([team, personalFree], choices: ["personal": true, "pikachu": false]) == [personalFree])
        #expect(OrgFilter.shown([team, personalFree], choices: [:]) == [team])
    }

    // Choices are kept per org, so an org joined after the owner picked is shown by default
    // instead of staying hidden forever.
    @Test func anOrgJoinedLaterIsShownByDefault() {
        let mew = Org(id: "mew", name: "Mew", billingType: "team")
        #expect(OrgFilter.shown([team, personalFree, mew], choices: ["pikachu": true, "personal": false]) == [team, mew])
    }

    @Test func aFreeOrgCanBeTurnedOn() {
        #expect(OrgFilter.shown([team, personalFree], choices: ["personal": true]) == [team, personalFree])
    }

    // Choosing to hide every org falls back to the default rather than an empty widget.
    @Test func hidingEverythingFallsBackToTheDefault() {
        #expect(OrgFilter.shown([team, personalFree], choices: ["pikachu": false]) == [team])
    }

    // Earlier versions saved the list of shown orgs.
    @Test func earlierPicksBecomeChoices() {
        #expect(OrgFilter.choices(fromShown: ["personal"], known: [team, personalFree]) == ["pikachu": false, "personal": true])
    }
}
