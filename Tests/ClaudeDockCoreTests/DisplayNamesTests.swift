import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct DisplayNamesTests {
    func shortNames(_ names: [String]) -> [String] {
        DisplayNames.short(names.map { Org(id: $0, name: $0) }).map(\.name)
    }

    @Test func dropsLeadingWordsEveryOrgShares() {
        #expect(shortNames(["Team Rocket Pikachu", "Team Rocket Charizard"]) == ["Pikachu", "Charizard"])
    }

    @Test func keepsNamesWithNothingInCommon() {
        #expect(shortNames(["Pikachu", "Charizard"]) == ["Pikachu", "Charizard"])
        #expect(shortNames(["Team Pikachu", "Gym Charizard"]) == ["Team Pikachu", "Gym Charizard"])
    }

    @Test func neverEmptiesAName() {
        #expect(shortNames(["Team Rocket", "Team Rocket Charizard"]) == ["Rocket", "Rocket Charizard"])
        #expect(shortNames(["Pikachu", "Pikachu"]) == ["Pikachu", "Pikachu"])
    }

    @Test func singleOrgKeepsItsName() {
        #expect(shortNames(["Team Rocket Pikachu"]) == ["Team Rocket Pikachu"])
    }

    @Test func keepsIdsAndBilling() {
        let orgs = DisplayNames.short([Org(id: "a", name: "Team Pikachu", billingType: "x"), Org(id: "b", name: "Team Charizard")])
        #expect(orgs[0] == Org(id: "a", name: "Pikachu", billingType: "x"))
    }
}
