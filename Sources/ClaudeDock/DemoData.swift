import Foundation
import ClaudeDockCore

/// One canned state for demo mode and `--render`.
struct DemoScenario {
    var name: String
    var orgs: [Org]
    var primary: String
    var readings: [Reading]
    var claudeCodeOrg: String
    /// Claude Code is working on `claudeCodeOrg`, so it shows the in-use effect.
    var claudeCodeWorking = false
    var now: Date
    /// The crab's mood on `claudeCodeOrg`; nil shows no crab.
    var crab: CrabMood? = nil
}

/// Pokémon sample data, so no real account ever shows up in a demo or a screenshot.
enum DemoData {
    static let pikachu = Org(id: "demo-pikachu", name: "Pikachu", billingType: "demo")
    static let charizard = Org(id: "demo-charizard", name: "Charizard", billingType: "demo")

    /// Every scenario, relative to `now` so demo mode looks right on any day.
    static func scenarios(now: Date = Date()) -> [DemoScenario] {
        func at(_ hours: Double) -> Date { now.addingTimeInterval(hours * 3600) }
        // Real weekly resets land on the hour; keep the demo's looking the same.
        func onTheHour(_ hours: Double) -> Date {
            Date(timeIntervalSince1970: (at(hours).timeIntervalSince1970 / 3600).rounded() * 3600)
        }
        func r(_ org: Org, week: Double, weekReset: Double?, session: Double = 0,
               sessionReset: Double? = nil, fable: Double = 20) -> Reading {
            Reading(time: now, org: org.id, session: session, sessionResetsAt: sessionReset.map(at),
                    week: week, weekResetsAt: weekReset.map(onTheHour), scoped: ["Fable": fable])
        }
        func scenario(_ name: String, working: Bool = false, crab: CrabMood? = nil, _ readings: [Reading]) -> DemoScenario {
            DemoScenario(name: name, orgs: [pikachu, charizard], primary: pikachu.id,
                         readings: readings, claudeCodeOrg: pikachu.id, claudeCodeWorking: working, now: now, crab: crab)
        }
        return [
            scenario("green-and-red", crab: .tool, [
                r(pikachu, week: 55, weekReset: 64.5, session: 1, sessionReset: 4.8, fable: 31),
                r(charizard, week: 95, weekReset: 33.5, fable: 2),
            ]),
            scenario("switch-for-desktop-app", working: true, crab: .tool, [
                r(pikachu, week: 60, weekReset: 64.5, session: 85, sessionReset: 1.5),
                r(charizard, week: 40, weekReset: 40),
            ]),
            scenario("use-it-before-it-expires", crab: .permission, [
                r(pikachu, week: 30, weekReset: 64.5, session: 10, sessionReset: 3),
                r(charizard, week: 70, weekReset: 33.5),
            ]),
            scenario("both-low", [
                r(pikachu, week: 92, weekReset: 64.5, session: 40, sessionReset: 2),
                r(charizard, week: 96, weekReset: 33.5),
            ]),
            scenario("on-pace-and-fresh", [
                r(pikachu, week: 88, weekReset: 20, session: 30, sessionReset: 3),
                r(charizard, week: 0, weekReset: nil, fable: 0),
            ]),
        ]
    }
}
