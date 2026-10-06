import Foundation
import Testing
@testable import ClaudeDockCore

/// Shaped like a real claude.ai usage response (placeholder values only).
let usageJSON = """
{
  "five_hour": {"utilization": 52, "resets_at": "2026-10-06T15:20:00.408772+00:00"},
  "seven_day": {"utilization": 55, "resets_at": "2026-10-09T08:00:00.408798+00:00"},
  "seven_day_opus": null,
  "extra_usage": {"is_enabled": true, "monthly_limit": 0},
  "limits": [
    {"kind": "session", "group": "session", "percent": 52, "severity": "normal",
     "resets_at": "2026-10-06T15:20:00.408772+00:00", "scope": null, "is_active": false},
    {"kind": "weekly_all", "group": "weekly", "percent": 55, "severity": "normal",
     "resets_at": "2026-10-09T08:00:00.408798+00:00", "scope": null, "is_active": true},
    {"kind": "weekly_scoped", "group": "weekly", "percent": 31, "severity": "normal",
     "resets_at": "2026-10-09T08:00:00.409004+00:00",
     "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}
  ]
}
"""

let orgsJSON = """
[
  {"uuid": "00000000-0000-4000-8000-000000000001", "name": "Pikachu", "billing_type": "stripe_subscription", "capabilities": ["chat"]},
  {"uuid": "00000000-0000-4000-8000-000000000002", "name": "Charizard", "billing_type": "stripe_subscription", "capabilities": ["chat"]},
  {"uuid": "00000000-0000-4000-8000-000000000003", "name": "Personal", "billing_type": null, "capabilities": ["chat"]}
]
"""

@Suite struct UsageParserTests {
    @Test func parsesLimits() throws {
        let r = try UsageParser.reading(from: Data(usageJSON.utf8), org: "pikachu", at: designNow)
        #expect(r.session == 52)
        #expect(r.sessionResetsAt == utc("2026-10-06T15:20:00Z"))
        #expect(r.week == 55)
        #expect(r.weekResetsAt == utc("2026-10-09T08:00:00Z"))
        #expect(r.scoped == ["Fable": 31])
        #expect(r.org == "pikachu")
        #expect(r.time == designNow)
    }

    @Test func roundsResetTimesToTheMinute() {
        #expect(UsageParser.parseDate("2026-10-08T00:59:59.702797+00:00") == utc("2026-10-08T01:00:00Z"))
        #expect(UsageParser.parseDate("2026-10-08T01:00:00Z") == utc("2026-10-08T01:00:00Z"))
        #expect(UsageParser.parseDate("not a date") == nil)
    }

    @Test func sessionWithoutWindowHasNoReset() throws {
        let json = """
        {"limits": [
          {"kind": "session", "percent": 0, "resets_at": null},
          {"kind": "weekly_all", "percent": 95, "resets_at": "2026-10-08T00:59:59.702797+00:00"}
        ]}
        """
        let r = try UsageParser.reading(from: Data(json.utf8), org: "charizard", at: designNow)
        #expect(r.session == 0)
        #expect(r.sessionResetsAt == nil)
        #expect(r.week == 95)
    }

    // Review Focus 1
    @Test func weekNotStartedHasNoReset() throws {
        let json = #"{"limits": [{"kind": "weekly_all", "percent": 0, "resets_at": null}]}"#
        let r = try UsageParser.reading(from: Data(json.utf8), org: "charizard", at: designNow)
        #expect(r.week == 0)
        #expect(r.weekResetsAt == nil)
    }

    @Test func fallsBackToOlderShape() throws {
        let json = """
        {"five_hour": {"utilization": 12, "resets_at": "2026-10-06T15:20:00+00:00"},
         "seven_day": {"utilization": 40, "resets_at": "2026-10-09T08:00:00+00:00"}}
        """
        let r = try UsageParser.reading(from: Data(json.utf8), org: "pikachu", at: designNow)
        #expect(r.session == 12)
        #expect(r.week == 40)
        #expect(r.weekResetsAt == utc("2026-10-09T08:00:00Z"))
    }

    // Review Focus 4
    @Test func htmlIsNotJSON() {
        #expect(throws: UsageParserError.notJSON) {
            try UsageParser.reading(from: Data("<html>Just a moment...</html>".utf8), org: "pikachu", at: designNow)
        }
        #expect(throws: UsageParserError.notJSON) {
            try UsageParser.orgs(from: Data("<html></html>".utf8))
        }
    }

    @Test func missingWeeklyLimitThrows() {
        #expect(throws: UsageParserError.noWeeklyLimit) {
            try UsageParser.reading(from: Data(#"{"limits": []}"#.utf8), org: "pikachu", at: designNow)
        }
    }

    // Review Focus 5
    @Test func clampsPercentages() throws {
        let json = """
        {"limits": [
          {"kind": "session", "percent": -3, "resets_at": null},
          {"kind": "weekly_all", "percent": 140, "resets_at": "2026-10-09T08:00:00+00:00"},
          {"kind": "weekly_scoped", "percent": 120, "resets_at": null, "scope": {"model": {"display_name": "Fable"}}}
        ]}
        """
        let r = try UsageParser.reading(from: Data(json.utf8), org: "pikachu", at: designNow)
        #expect(r.session == 0)
        #expect(r.week == 100)
        #expect(r.scoped["Fable"] == 100)
    }

    @Test func parsesOrgs() throws {
        let orgs = try UsageParser.orgs(from: Data(orgsJSON.utf8))
        #expect(orgs.map(\.name) == ["Pikachu", "Charizard", "Personal"])
        #expect(orgs[0].id == "00000000-0000-4000-8000-000000000001")
        #expect(orgs[0].billingType == "stripe_subscription")
        #expect(orgs[2].billingType == nil)
    }
}
