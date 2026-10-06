# Claude Dock Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Claude Dock, an always-on macOS widget that shows weekly and 5-hour Claude usage for two orgs, a stoplight per org, and advice on which org Claude Code should use.

**Architecture:** A Swift package with two targets. `ClaudeDockCore` holds all logic (parsing, pace math, stoplight, switch advice, chart geometry, copy, history) as pure, unit-tested code. `ClaudeDock` is the AppKit + SwiftUI app: two floating panels (widget and expanded panel), a hidden `WKWebView` that reads claude.ai, a poller, notifications and settings. Demo mode and a `--render` flag show every state with Pokémon sample data.

**Tech Stack:** Swift 6.4 toolchain (Command Line Tools only, no Xcode), Swift language mode 5, SwiftPM, Swift Testing, AppKit, SwiftUI, WebKit, UserNotifications, ServiceManagement. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-06-claude-dock-design.md`

## Global Constraints

- macOS 14 or later (`platforms: [.macOS(.v14)]`). Every target uses `.swiftLanguageMode(.v5)`.
- Run tests with `./test.sh` (it loads the Swift Testing macro plugin, which SwiftPM can't find without Xcode). Never plain `swift test`.
- No third-party dependencies.
- **The repository is public.** Never commit employer, org or plan names, email addresses, real org or account IDs, or home-folder paths. Examples use Pokémon: **Pikachu** is the primary org, **Charizard** the overflow org. Fake IDs look like `00000000-0000-4000-8000-00000000000N`. The `.githooks` scanner enforces this; never bypass it with `--no-verify`.
- Never commit images. Renders go to a scratch folder outside the repo.
- Every percentage is "used", 0–100.
- Default thresholds, verbatim from the spec: red when under 10% of the week left, or running out 12+ hours early, or 5-hour window ≥ 95%; yellow when 5-hour window ≥ 80%, or under 5% would go unused, or running out under 12 hours early; green pulse 2.8 s (unused < 10), 1.6 s (10–25), 0.9 s (> 25); eligible for Claude Code with ≥ 10% week left and 5-hour window < 80%; the primary org also needs ≥ 15% week left.
- claude.ai is read-only: GET requests only. Poll every 3 minutes; back off 3 → 6 → 12 → 15 minutes on errors.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. **A week that hasn't started** (weekly `resets_at: null`): show "hasn't started", no forecast, a steady green dot, no crash. Tests: Task 1 (parser), Task 4 (no forecast), Task 5 (steady green), Task 8 (copy and chart).
2. **A reset time passes between two polls:** that window must read as empty right away, not stay at its old high value. Test: Task 1 (`Reading.adjusted(to:)`).
3. **No usage in the last 72 hours** (zero pace): everything left would go unused, with no division by zero. Test: Task 4.
4. **claude.ai answers with an HTML page** (bot check or login page) instead of JSON: treat it as an error, keep the last numbers (greyed out once stale), never crash. Test: Task 1 (`notJSON`).
5. **A percentage outside 0–100** (for example extra usage pushing past 100): clamp it. Test: Task 1.

---

### Task 1: Package, test runner, models and the claude.ai parser

**Files:**
- Create: `Package.swift`, `test.sh`
- Create: `Sources/ClaudeDockCore/Models.swift`, `Sources/ClaudeDockCore/UsageParser.swift`
- Test: `Tests/ClaudeDockCoreTests/Helpers.swift`, `Tests/ClaudeDockCoreTests/ModelsTests.swift`, `Tests/ClaudeDockCoreTests/UsageParserTests.swift`

**Interfaces:**
- Produces: `Org(id: String, name: String, billingType: String?)`; `Role { primary, overflow }`; `Reading(time:org:session:sessionResetsAt:week:weekResetsAt:scoped:)` with `weekLeft: Double`, `adjusted(to: Date) -> Reading`, `sessionElapsedFraction(now: Date) -> Double?`; `UsageParser.orgs(from: Data) throws -> [Org]`, `UsageParser.reading(from: Data, org: String, at: Date) throws -> Reading`, `UsageParser.parseDate(String) -> Date?`; `UsageParserError { notJSON, noWeeklyLimit }`. Test helpers `newYork`, `local(...)`, `utc(...)`, `designNow`, `reading(...)`, `near(...)`.

- [ ] **Step 1: Create the package and the test runner**

`Package.swift`:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeDock",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClaudeDockCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ClaudeDockCoreTests",
            dependencies: ["ClaudeDockCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

`test.sh`:

```bash
#!/bin/bash
# Runs the unit tests. With only the Command Line Tools installed (no Xcode), SwiftPM
# can't find the Swift Testing macro plugin by itself, so load it explicitly.
set -euo pipefail
cd "$(dirname "$0")"
plugin="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -f "$plugin" ]; then
  exec swift test -Xswiftc -load-plugin-library -Xswiftc "$plugin" "$@"
fi
exec swift test "$@"
```

Run: `chmod +x test.sh`

- [ ] **Step 2: Write the test helpers**

`Tests/ClaudeDockCoreTests/Helpers.swift`:

```swift
import Foundation
@testable import ClaudeDockCore

/// Tests run in New York time so day names and midnights are deterministic.
let newYork: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

/// A New York local time, e.g. `local(2026, 10, 6, 11, 32)`.
func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

func utc(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

/// The moment the design was drawn: Tuesday Oct 6 2026, 11:32 AM in New York.
let designNow = local(2026, 10, 6, 11, 32)

func reading(
    org: String = "pikachu", week: Double, weekResetsAt: Date?,
    session: Double = 0, sessionResetsAt: Date? = nil,
    at time: Date = designNow, scoped: [String: Double] = [:]
) -> Reading {
    Reading(time: time, org: org, session: session, sessionResetsAt: sessionResetsAt,
            week: week, weekResetsAt: weekResetsAt, scoped: scoped)
}

func near(_ a: Double, _ b: Double, _ tolerance: Double = 0.05) -> Bool { abs(a - b) <= tolerance }
```

- [ ] **Step 3: Write the failing tests**

`Tests/ClaudeDockCoreTests/ModelsTests.swift`:

```swift
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
```

`Tests/ClaudeDockCoreTests/UsageParserTests.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `./test.sh`
Expected: build fails with errors like `cannot find 'Reading' in scope`.

- [ ] **Step 5: Write the models**

`Sources/ClaudeDockCore/Models.swift`:

```swift
import Foundation

/// A Claude organization the signed-in account belongs to.
public struct Org: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var billingType: String?

    public init(id: String, name: String, billingType: String? = nil) {
        self.id = id
        self.name = name
        self.billingType = billingType
    }
}

/// How the owner uses an org. The primary org is shared with the Claude desktop app.
public enum Role: String, Codable, Sendable {
    case primary, overflow
}

/// One usage snapshot for one org. Percentages are "used", 0–100.
public struct Reading: Codable, Equatable, Sendable {
    public var time: Date
    public var org: String
    public var session: Double
    /// nil when no 5-hour window is open.
    public var sessionResetsAt: Date?
    public var week: Double
    /// nil when the week hasn't started (nothing used yet).
    public var weekResetsAt: Date?
    /// Model-specific weekly limits, e.g. ["Fable": 31].
    public var scoped: [String: Double]

    public init(time: Date, org: String, session: Double, sessionResetsAt: Date?,
                week: Double, weekResetsAt: Date?, scoped: [String: Double] = [:]) {
        self.time = time
        self.org = org
        self.session = session
        self.sessionResetsAt = sessionResetsAt
        self.week = week
        self.weekResetsAt = weekResetsAt
        self.scoped = scoped
    }

    enum CodingKeys: String, CodingKey {
        case time = "t", org, session, sessionResetsAt, week, weekResetsAt, scoped
    }

    public var weekLeft: Double { 100 - week }

    /// The reading as it stands at `now`: a window whose reset time has passed is empty again.
    public func adjusted(to now: Date) -> Reading {
        var r = self
        if let reset = r.sessionResetsAt, reset <= now {
            r.session = 0
            r.sessionResetsAt = nil
        }
        if let reset = r.weekResetsAt, reset <= now {
            r.week = 0
            r.weekResetsAt = nil
            r.scoped = r.scoped.mapValues { _ in 0 }
        }
        return r
    }

    /// How far into the current 5-hour window `now` is, 0...1; nil when no window is open.
    public func sessionElapsedFraction(now: Date) -> Double? {
        guard let reset = sessionResetsAt else { return nil }
        return min(max(1 - reset.timeIntervalSince(now) / (5 * 3600), 0), 1)
    }
}
```

- [ ] **Step 6: Write the parser**

`Sources/ClaudeDockCore/UsageParser.swift`:

```swift
import Foundation

public enum UsageParserError: Error, Equatable {
    case notJSON
    case noWeeklyLimit
}

/// Turns claude.ai's JSON into models. Tolerant: unknown fields are ignored, and the
/// older `five_hour` / `seven_day` fields fill in whatever `limits` doesn't provide.
public enum UsageParser {
    public static func orgs(from data: Data) throws -> [Org] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw UsageParserError.notJSON
        }
        return list.compactMap { item in
            guard let id = item["uuid"] as? String, let name = item["name"] as? String else { return nil }
            return Org(id: id, name: name, billingType: item["billing_type"] as? String)
        }
    }

    public static func reading(from data: Data, org: String, at time: Date) throws -> Reading {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageParserError.notJSON
        }
        var session = 0.0
        var sessionResetsAt: Date?
        var week: Double?
        var weekResetsAt: Date?
        var scoped: [String: Double] = [:]

        if let fiveHour = root["five_hour"] as? [String: Any] {
            session = number(fiveHour["utilization"]) ?? 0
            sessionResetsAt = date(fiveHour["resets_at"])
        }
        if let sevenDay = root["seven_day"] as? [String: Any] {
            week = number(sevenDay["utilization"])
            weekResetsAt = date(sevenDay["resets_at"])
        }
        for limit in root["limits"] as? [[String: Any]] ?? [] {
            let percent = number(limit["percent"])
            let reset = date(limit["resets_at"])
            switch limit["kind"] as? String {
            case "session":
                session = percent ?? 0
                sessionResetsAt = reset
            case "weekly_all":
                week = percent
                weekResetsAt = reset
            case "weekly_scoped":
                let model = (limit["scope"] as? [String: Any])?["model"] as? [String: Any]
                if let name = model?["display_name"] as? String, let percent {
                    scoped[name] = clamp(percent)
                }
            default:
                break
            }
        }
        guard let week else { throw UsageParserError.noWeeklyLimit }
        return Reading(time: time, org: org, session: clamp(session), sessionResetsAt: sessionResetsAt,
                       week: clamp(week), weekResetsAt: weekResetsAt, scoped: scoped)
    }

    /// claude.ai sends microseconds ("2026-10-06T15:20:00.408772+00:00"), which
    /// ISO8601DateFormatter can't read, and the fraction drifts between requests. Drop it
    /// and round to the nearest minute so one window always has one reset time.
    public static func parseDate(_ text: String) -> Date? {
        var trimmed = text
        if let dot = trimmed.firstIndex(of: "."),
           let end = trimmed[dot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" }) {
            trimmed.removeSubrange(dot..<end)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: trimmed) else { return nil }
        return Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
    }

    private static func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
    private static func date(_ value: Any?) -> Date? { (value as? String).flatMap(parseDate) }
    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 100) }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `./test.sh`
Expected: `Test run with 13 tests ... passed`.

- [ ] **Step 8: Commit**

```bash
git add Package.swift test.sh Sources Tests
git commit -m "Add core models and claude.ai usage parser" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Formatting

**Files:**
- Create: `Sources/ClaudeDockCore/Formatting.swift`
- Modify: `Tests/ClaudeDockCoreTests/Helpers.swift` (append `fmt`)
- Test: `Tests/ClaudeDockCoreTests/FormattingTests.swift`

**Interfaces:**
- Produces: `Formatting(calendar: Calendar = .current, locale: Locale = en_US_POSIX)` with `dayTime(_ date: Date, now: Date) -> String`, `weekStartLabel(_ date: Date) -> String`, and statics `compact(_ interval: TimeInterval) -> String`, `percent(_ value: Double) -> String`. Test helper `fmt`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/ClaudeDockCoreTests/Helpers.swift`:

```swift
let fmt = Formatting(calendar: newYork)
```

`Tests/ClaudeDockCoreTests/FormattingTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct FormattingTests {
    @Test func sameDayShowsTimeOnly() {
        #expect(fmt.dayTime(local(2026, 10, 6, 16, 20), now: designNow) == "4:20 PM")
        #expect(fmt.dayTime(local(2026, 10, 6, 16, 0), now: designNow) == "4 PM")
    }

    @Test func otherDayShowsWeekday() {
        #expect(fmt.dayTime(local(2026, 10, 9, 4, 0), now: designNow) == "Fri 4 AM")
        #expect(fmt.dayTime(local(2026, 10, 7, 21, 0), now: designNow) == "Wed 9 PM")
        #expect(fmt.dayTime(local(2026, 10, 7, 21, 30), now: designNow) == "Wed 9:30 PM")
    }

    @Test func compactDurations() {
        #expect(Formatting.compact(34 * 3600 + 20 * 60) == "1d 10h")
        #expect(Formatting.compact(3 * 3600 + 5 * 60) == "3h 5m")
        #expect(Formatting.compact(12 * 60) == "12m")
        #expect(Formatting.compact(-5) == "0m")
    }

    @Test func percents() {
        #expect(Formatting.percent(54.6) == "55%")
        #expect(Formatting.percent(0) == "0%")
    }

    @Test func weekStart() {
        #expect(fmt.weekStartLabel(local(2026, 10, 5)) == "Mon Oct 5")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./test.sh`
Expected: build error `cannot find 'Formatting' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/ClaudeDockCore/Formatting.swift`:

```swift
import Foundation

/// Short time and number text used across the widget and panel.
public struct Formatting: Sendable {
    public var calendar: Calendar
    public var locale: Locale

    public init(calendar: Calendar = .current, locale: Locale = Locale(identifier: "en_US_POSIX")) {
        self.calendar = calendar
        self.locale = locale
    }

    /// "4:20 PM" or "4 PM" on the same day as `now`; "Fri 4 AM" or "Wed 9:30 PM" otherwise.
    public func dayTime(_ date: Date, now: Date) -> String {
        let time = format(date, calendar.component(.minute, from: date) == 0 ? "h a" : "h:mm a")
        return calendar.isDate(date, inSameDayAs: now) ? time : "\(format(date, "EEE")) \(time)"
    }

    /// "Mon Oct 5"
    public func weekStartLabel(_ date: Date) -> String { format(date, "EEE MMM d") }

    /// "1d 10h", "3h 5m" or "12m". Negative intervals read as "0m".
    public static func compact(_ interval: TimeInterval) -> String {
        let minutes = max(Int(interval / 60), 0)
        let days = minutes / 1440, hours = (minutes % 1440) / 60, rest = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(rest)m" }
        return "\(rest)m"
    }

    /// "55%": whole numbers, rounded.
    public static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    private func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./test.sh`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "Add time and percent formatting" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The shared Monday-to-Sunday week axis

**Files:**
- Create: `Sources/ClaudeDockCore/WeekAxis.swift`
- Test: `Tests/ClaudeDockCoreTests/WeekAxisTests.swift`

**Interfaces:**
- Produces: `WeekAxis(containing: Date, calendar: Calendar = .current)` with `start`, `end`, `calendar`, `duration`, `x(_ date: Date) -> Double`, `contains(_ date: Date) -> Bool`, `midnights: [Date]`, `days: [DayMark]`, `today(_ now: Date) -> ClosedRange<Double>`; `DayMark(name: String, start: Double, center: Double)`.

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeDockCoreTests/WeekAxisTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct WeekAxisTests {
    let axis = WeekAxis(containing: designNow, calendar: newYork)

    @Test func runsMondayToMonday() {
        #expect(axis.start == local(2026, 10, 5))
        #expect(axis.end == local(2026, 10, 12))
        #expect(axis.duration == 168 * 3600)
    }

    @Test func positionsAreShareOfTheWeek() {
        #expect(axis.x(local(2026, 10, 5)) == 0)
        #expect(near(axis.x(designNow), 35.5333 / 168, 0.0001))
        #expect(axis.x(local(2026, 10, 12)) == 1)
        #expect(axis.contains(designNow))
        #expect(!axis.contains(local(2026, 10, 12, 1)))
    }

    @Test func sundayBelongsToTheWeekBefore() {
        #expect(WeekAxis(containing: local(2026, 10, 11, 23), calendar: newYork).start == local(2026, 10, 5))
    }

    @Test func daysAndToday() {
        #expect(axis.days.map(\.name) == ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
        #expect(near(axis.days[1].center, 1.5 / 7, 0.0001))
        let today = axis.today(designNow)
        #expect(near(today.lowerBound, 1.0 / 7, 0.0001))
        #expect(near(today.upperBound, 2.0 / 7, 0.0001))
        #expect(axis.midnights.count == 8)
    }

    @Test func daylightSavingWeekHas169Hours() {
        let dst = WeekAxis(containing: local(2026, 10, 28), calendar: newYork)
        #expect(dst.start == local(2026, 10, 26))
        #expect(dst.duration == 169 * 3600)
        #expect(dst.days.last?.name == "Sun")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./test.sh`
Expected: build error `cannot find 'WeekAxis' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/ClaudeDockCore/WeekAxis.swift`:

```swift
import Foundation

/// One day on the week axis: its name, where it starts, and its middle (for the label).
public struct DayMark: Equatable, Sendable {
    public var name: String
    public var start: Double
    public var center: Double
}

/// The Monday-to-Sunday calendar week every chart is drawn on, so both orgs' days line
/// up even though their limits reset at different times. Positions are shares of the
/// week: 0 at Monday 00:00, 1 at the next Monday 00:00.
public struct WeekAxis: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let calendar: Calendar

    public init(containing date: Date, calendar: Calendar = .current) {
        var monday = calendar
        monday.firstWeekday = 2
        let week = monday.dateInterval(of: .weekOfYear, for: date)!
        start = week.start
        end = week.end
        self.calendar = monday
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    /// Not clamped: dates outside the week map below 0 or above 1.
    public func x(_ date: Date) -> Double { date.timeIntervalSince(start) / duration }

    public func contains(_ date: Date) -> Bool { date >= start && date <= end }

    /// The eight midnights from this Monday to the next.
    public var midnights: [Date] {
        (0...7).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    public var days: [DayMark] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        let nights = midnights
        return (0..<7).map { i in
            let a = x(nights[i]), b = x(nights[i + 1])
            return DayMark(name: formatter.string(from: nights[i]), start: a, center: (a + b) / 2)
        }
    }

    /// Where today's column sits.
    public func today(_ now: Date) -> ClosedRange<Double> {
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!
        return x(dayStart)...x(dayEnd)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./test.sh`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "Add the shared Monday-to-Sunday week axis" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Pace and forecast

**Files:**
- Create: `Sources/ClaudeDockCore/Pace.swift`
- Test: `Tests/ClaudeDockCoreTests/PaceTests.swift`

**Interfaces:**
- Consumes: `Reading` (Task 1).
- Produces: `WeekForecast` with stored fields in this order: `used`, `hoursLeft`, `elapsedFraction`, `pacePerHour`, `forecastAtReset`, `unused`, `runsOutEarlyByHours: Double?`, `runsOutAt: Date?`, `useItAllPerHour`, `byMidnight`, plus computed `pacePerDay`, `useItAllPerDay`. `Pace.window: TimeInterval` (7 days), `Pace.forecast(_ reading: Reading, history: [Reading], now: Date, calendar: Calendar = .current) -> WeekForecast?`.

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeDockCoreTests/PaceTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct PaceTests {
    // The spec's worked example: 55% used, 103.4 h elapsed, 64.6 h left, 11:32 AM.
    let reset = designNow.addingTimeInterval(64.6 * 3600)

    @Test func workedExample() throws {
        let f = try #require(Pace.forecast(reading(week: 55, weekResetsAt: reset), history: [], now: designNow, calendar: newYork))
        #expect(near(f.useItAllPerDay, 16.72))
        #expect(near(f.pacePerDay, 12.77))
        #expect(near(f.unused, 10.64))
        #expect(near(f.byMidnight, 8.68))
        #expect(near(f.elapsedFraction, 103.4 / 168, 0.001))
        #expect(f.runsOutEarlyByHours == nil)
    }

    @Test func usesTheReadingFrom72HoursAgo() throws {
        let old = reading(week: 20, weekResetsAt: reset, at: designNow.addingTimeInterval(-80 * 3600))
        let f = try #require(Pace.forecast(reading(week: 55, weekResetsAt: reset), history: [old], now: designNow, calendar: newYork))
        #expect(near(f.pacePerHour, 35.0 / 80, 0.0001))
        #expect(near(f.unused, 100 - (55 + 35.0 / 80 * 64.6)))
    }

    @Test func ignoresReadingsFromAnotherWindow() throws {
        let old = reading(week: 20, weekResetsAt: reset.addingTimeInterval(-Pace.window), at: designNow.addingTimeInterval(-80 * 3600))
        let f = try #require(Pace.forecast(reading(week: 55, weekResetsAt: reset), history: [old], now: designNow, calendar: newYork))
        #expect(near(f.pacePerDay, 12.77))
    }

    @Test func ignoresOtherOrgs() throws {
        let old = reading(org: "charizard", week: 20, weekResetsAt: reset, at: designNow.addingTimeInterval(-80 * 3600))
        let f = try #require(Pace.forecast(reading(week: 55, weekResetsAt: reset), history: [old], now: designNow, calendar: newYork))
        #expect(near(f.pacePerDay, 12.77))
    }

    @Test func runsOutEarly() throws {
        let f = try #require(Pace.forecast(reading(week: 90, weekResetsAt: reset), history: [], now: designNow, calendar: newYork))
        let pace = 90 / 103.4
        #expect(near(f.runsOutEarlyByHours!, 64.6 - 10 / pace))
        #expect(f.unused == 0)
        #expect(f.forecastAtReset == 100)
        #expect(near(f.runsOutAt!.timeIntervalSince(designNow) / 3600, 10 / pace))
    }

    // Review Focus 3
    @Test func zeroPaceMeansEverythingLeftGoesUnused() throws {
        let old = reading(week: 55, weekResetsAt: reset, at: designNow.addingTimeInterval(-80 * 3600))
        let f = try #require(Pace.forecast(reading(week: 55, weekResetsAt: reset), history: [old], now: designNow, calendar: newYork))
        #expect(f.pacePerHour == 0)
        #expect(f.unused == 45)
        #expect(f.runsOutEarlyByHours == nil)
    }

    // Review Focus 1
    @Test func noForecastBeforeTheWeekStartsOrAfterItEnds() {
        #expect(Pace.forecast(reading(week: 0, weekResetsAt: nil), history: [], now: designNow, calendar: newYork) == nil)
        #expect(Pace.forecast(reading(week: 50, weekResetsAt: designNow.addingTimeInterval(-60)), history: [], now: designNow, calendar: newYork) == nil)
    }

    @Test func byMidnightIsCappedAtReset() throws {
        let soon = local(2026, 10, 6, 16, 0)
        let f = try #require(Pace.forecast(reading(week: 70, weekResetsAt: soon), history: [], now: designNow, calendar: newYork))
        #expect(near(f.byMidnight, 30))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./test.sh`
Expected: build error `cannot find 'Pace' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/ClaudeDockCore/Pace.swift`:

```swift
import Foundation

/// Where a week's usage is heading. Percentages are of the weekly limit.
public struct WeekForecast: Equatable, Sendable {
    public var used: Double
    public var hoursLeft: Double
    /// Share of the 7-day window gone, 0...1.
    public var elapsedFraction: Double
    public var pacePerHour: Double
    public var forecastAtReset: Double
    /// What would be left unused at reset at the current pace.
    public var unused: Double
    /// Set when the current pace uses everything before reset.
    public var runsOutEarlyByHours: Double?
    public var runsOutAt: Date?
    /// The pace that uses exactly everything by reset.
    public var useItAllPerHour: Double
    /// How much more to use before local midnight to stay on the use-it-all pace.
    public var byMidnight: Double

    public var pacePerDay: Double { pacePerHour * 24 }
    public var useItAllPerDay: Double { useItAllPerHour * 24 }
}

public enum Pace {
    public static let window: TimeInterval = 7 * 24 * 3600
    static let lookback: TimeInterval = 72 * 3600

    /// nil when the week hasn't started or has already reset.
    public static func forecast(_ reading: Reading, history: [Reading], now: Date,
                                calendar: Calendar = .current) -> WeekForecast? {
        guard let reset = reading.weekResetsAt, reset > now else { return nil }
        let used = reading.week
        let left = 100 - used
        let hoursLeft = reset.timeIntervalSince(now) / 3600
        let hoursElapsed = max(now.timeIntervalSince(reset.addingTimeInterval(-window)) / 3600, 1.0 / 60)

        // Pace over the last 72 hours, measured from the newest reading in this window that
        // is at least that old. Without one, the average since the window started.
        var pace = used / hoursElapsed
        let cutoff = now.addingTimeInterval(-lookback)
        if let past = history
            .filter({ $0.org == reading.org && $0.weekResetsAt == reset && $0.time <= cutoff })
            .max(by: { $0.time < $1.time }) {
            pace = max((used - past.week) / (now.timeIntervalSince(past.time) / 3600), 0)
        }

        var runsOutEarly: Double?
        var runsOutAt: Date?
        if pace > 0, pace * hoursLeft > left {
            let hoursToEmpty = left / pace
            runsOutEarly = hoursLeft - hoursToEmpty
            runsOutAt = now.addingTimeInterval(hoursToEmpty * 3600)
        }
        let forecast = min(100, used + pace * hoursLeft)
        let useItAll = left / hoursLeft
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let hoursToMidnight = min(midnight.timeIntervalSince(now) / 3600, hoursLeft)

        return WeekForecast(
            used: used,
            hoursLeft: hoursLeft,
            elapsedFraction: min(hoursElapsed * 3600 / window, 1),
            pacePerHour: pace,
            forecastAtReset: forecast,
            unused: 100 - forecast,
            runsOutEarlyByHours: runsOutEarly,
            runsOutAt: runsOutAt,
            useItAllPerHour: useItAll,
            byMidnight: useItAll * hoursToMidnight
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./test.sh`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "Add weekly pace and forecast" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Stoplight

**Files:**
- Create: `Sources/ClaudeDockCore/Stoplight.swift`
- Test: `Tests/ClaudeDockCoreTests/StoplightTests.swift`

**Interfaces:**
- Consumes: `Reading`, `WeekForecast`.
- Produces: `Pulse { slow = 2.8, normal = 1.6, fast = 0.9 }` (raw value = seconds); `Light { green(Pulse?), yellow, red }` (`green(nil)` = steady); `Thresholds` (Codable, all `Double`, defaults below) with fields `redWeekLeft`, `redRunsOutEarlyHours`, `redSession`, `yellowSession`, `onPaceUnused`, `normalPulseUnused`, `fastPulseUnused`, `eligibleWeekLeft`, `eligibleSessionBelow`, `primaryReserveWeekLeft`; `Stoplight.light(_ reading: Reading, _ forecast: WeekForecast?, _ t: Thresholds = Thresholds()) -> Light`.

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeDockCoreTests/StoplightTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeDockCore

func forecastWith(unused: Double, early: Double? = nil) -> WeekForecast {
    WeekForecast(used: 50, hoursLeft: 50, elapsedFraction: 0.7, pacePerHour: 1,
                 forecastAtReset: 100 - unused, unused: unused, runsOutEarlyByHours: early,
                 runsOutAt: early.map { designNow.addingTimeInterval($0 * 3600) },
                 useItAllPerHour: 1, byMidnight: 5)
}

@Suite struct StoplightTests {
    let resetSoon = designNow.addingTimeInterval(50 * 3600)

    func light(week: Double = 50, session: Double = 0, unused: Double = 15, early: Double? = nil,
               _ t: Thresholds = Thresholds()) -> Light {
        Stoplight.light(reading(week: week, weekResetsAt: resetSoon, session: session),
                        forecastWith(unused: unused, early: early), t)
    }

    @Test func red() {
        #expect(light(week: 91) == .red)                      // under 10% left
        #expect(light(unused: 0, early: 12) == .red)          // runs out 12h early
        #expect(light(session: 95) == .red)                   // 5-hour window maxed
    }

    @Test func yellow() {
        #expect(light(unused: 0, early: 11.9) == .yellow)     // runs out slightly early
        #expect(light(session: 80) == .yellow)
        #expect(light(unused: 4.9) == .yellow)                // on pace
        #expect(light(week: 90) != .red)                      // exactly 10% left is not red
    }

    @Test func greenPulseBuckets() {
        #expect(light(unused: 5) == .green(.slow))
        #expect(light(unused: 9.9) == .green(.slow))
        #expect(light(unused: 10) == .green(.normal))
        #expect(light(unused: 25) == .green(.normal))
        #expect(light(unused: 25.1) == .green(.fast))
    }

    // Review Focus 1
    @Test func weekNotStartedIsSteadyGreen() {
        #expect(Stoplight.light(reading(week: 0, weekResetsAt: nil), nil) == .green(nil))
        #expect(Stoplight.light(reading(week: 0, weekResetsAt: nil, session: 85), nil) == .yellow)
    }

    @Test func thresholdsAreAdjustable() {
        var t = Thresholds()
        t.redWeekLeft = 20
        #expect(light(week: 85, t) == .red)
    }

    @Test func defaultsMatchTheSpec() {
        let t = Thresholds()
        #expect([t.redWeekLeft, t.redRunsOutEarlyHours, t.redSession, t.yellowSession, t.onPaceUnused,
                 t.normalPulseUnused, t.fastPulseUnused, t.eligibleWeekLeft, t.eligibleSessionBelow,
                 t.primaryReserveWeekLeft] == [10, 12, 95, 80, 5, 10, 25, 10, 80, 15])
        #expect(Pulse.slow.rawValue == 2.8 && Pulse.normal.rawValue == 1.6 && Pulse.fast.rawValue == 0.9)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./test.sh`
Expected: build error `cannot find 'Stoplight' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/ClaudeDockCore/Stoplight.swift`:

```swift
import Foundation

/// How fast a green dot pulses, in seconds per pulse.
public enum Pulse: Double, Equatable, Sendable {
    case slow = 2.8, normal = 1.6, fast = 0.9
}

/// "Should I be using this org right now?" Green (with a pulse, or steady when the week
/// hasn't started), yellow, or red.
public enum Light: Equatable, Sendable {
    case green(Pulse?)
    case yellow
    case red
}

/// Every adjustable threshold, in percent or hours. Defaults are the spec's values.
public struct Thresholds: Codable, Equatable, Sendable {
    public var redWeekLeft = 10.0
    public var redRunsOutEarlyHours = 12.0
    public var redSession = 95.0
    public var yellowSession = 80.0
    public var onPaceUnused = 5.0
    public var normalPulseUnused = 10.0
    public var fastPulseUnused = 25.0
    public var eligibleWeekLeft = 10.0
    public var eligibleSessionBelow = 80.0
    public var primaryReserveWeekLeft = 15.0

    public init() {}
}

public enum Stoplight {
    /// First match wins: red, then yellow, then green.
    public static func light(_ reading: Reading, _ forecast: WeekForecast?, _ t: Thresholds = Thresholds()) -> Light {
        let early = forecast?.runsOutEarlyByHours ?? 0
        if reading.weekLeft < t.redWeekLeft || early >= t.redRunsOutEarlyHours || reading.session >= t.redSession {
            return .red
        }
        guard let forecast else {
            return reading.session >= t.yellowSession ? .yellow : .green(nil)
        }
        if reading.session >= t.yellowSession || forecast.unused < t.onPaceUnused || forecast.runsOutEarlyByHours != nil {
            return .yellow
        }
        if forecast.unused > t.fastPulseUnused { return .green(.fast) }
        if forecast.unused >= t.normalPulseUnused { return .green(.normal) }
        return .green(.slow)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./test.sh`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "Add the stoplight rules" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Switch advice

**Files:**
- Create: `Sources/ClaudeDockCore/SwitchAdvisor.swift`
- Test: `Tests/ClaudeDockCoreTests/SwitchAdvisorTests.swift`

**Interfaces:**
- Consumes: `Org`, `Role`, `Reading`, `Light`, `Thresholds`, `Pace.window`, `Formatting`.
- Produces: `OrgStatus(org: Org, role: Role, reading: Reading, light: Light)`; `Advice(target: Org, reason: String)`; `SwitchAdvisor.isEligible(_:_:) -> Bool`, `SwitchAdvisor.best(_ orgs: [OrgStatus], now: Date, _ t: Thresholds) -> OrgStatus?`, `SwitchAdvisor.advice(_ orgs: [OrgStatus], claudeCodeOrg: String?, now: Date, formatting: Formatting, _ t: Thresholds) -> Advice?`, `SwitchAdvisor.statusLine(_ orgs: [OrgStatus], claudeCodeOrg: String?, advice: Advice?, now: Date, formatting: Formatting, _ t: Thresholds) -> String`; `AdviceGate()` with `shown: Advice?`, `hold: TimeInterval` (3600), `mutating update(_ candidate: Advice?, claudeCodeOrg: String?, currentIsRed: Bool, now: Date) -> Advice?`.

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeDockCoreTests/SwitchAdvisorTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeDockCore

let pikachu = Org(id: "pikachu", name: "Pikachu", billingType: "team")
let charizard = Org(id: "charizard", name: "Charizard", billingType: "team")
let friday4am = local(2026, 10, 9, 4, 0)
let wednesday9pm = local(2026, 10, 7, 21, 0)
let monday9am = local(2026, 10, 12, 9, 0)

func status(_ org: Org, _ role: Role, week: Double, reset: Date?, session: Double = 0,
            sessionReset: Date? = nil) -> OrgStatus {
    let r = reading(org: org.id, week: week, weekResetsAt: reset, session: session, sessionResetsAt: sessionReset)
    let f = Pace.forecast(r, history: [], now: designNow, calendar: newYork)
    return OrgStatus(org: org, role: role, reading: r, light: Stoplight.light(r, f))
}

func advise(_ orgs: [OrgStatus], cc: String? = "pikachu") -> Advice? {
    SwitchAdvisor.advice(orgs, claudeCodeOrg: cc, now: designNow, formatting: fmt, Thresholds())
}

@Suite struct SwitchAdvisorTests {
    // The design-day numbers: the overflow org has only 5% left, so stay put.
    let today = [
        status(pikachu, .primary, week: 55, reset: friday4am, session: 1, sessionReset: designNow.addingTimeInterval(4.8 * 3600)),
        status(charizard, .overflow, week: 95, reset: wednesday9pm),
    ]

    @Test func overflowAtFivePercentMeansNoAdvice() {
        #expect(advise(today) == nil)
        #expect(SwitchAdvisor.statusLine(today, claudeCodeOrg: "pikachu", advice: nil, now: designNow, formatting: fmt, Thresholds())
                == "Claude Code is on Pikachu, the right place right now.")
    }

    @Test func busyPrimarySessionMovesToOverflow() {
        let orgs = [
            status(pikachu, .primary, week: 60, reset: friday4am, session: 85, sessionReset: designNow.addingTimeInterval(1.5 * 3600)),
            status(charizard, .overflow, week: 60, reset: monday9am),
        ]
        let advice = advise(orgs)
        #expect(advice?.target == charizard)
        #expect(advice?.reason == "Pikachu 5h at 85%, desktop app needs room")
        #expect(SwitchAdvisor.statusLine(orgs, claudeCodeOrg: "pikachu", advice: advice, now: designNow, formatting: fmt, Thresholds())
                == "Move Claude Code to Charizard: Pikachu 5h at 85%, desktop app needs room.")
    }

    @Test func useWhatExpiresFirst() {
        let orgs = [
            status(pikachu, .primary, week: 30, reset: friday4am, session: 10, sessionReset: designNow.addingTimeInterval(3 * 3600)),
            status(charizard, .overflow, week: 70, reset: wednesday9pm),
        ]
        #expect(advise(orgs) == Advice(target: charizard, reason: "Charizard has 30% expiring Wed 9 PM"))
    }

    @Test func primaryKeepsABufferForTheDesktopApp() {
        let orgs = [
            status(pikachu, .primary, week: 86, reset: friday4am),
            status(charizard, .overflow, week: 50, reset: monday9am),
        ]
        #expect(advise(orgs) == Advice(target: charizard, reason: "Pikachu is down to 14%, keep it for the desktop app"))
    }

    @Test func bothLowSaysWhichComesBackFirst() {
        let orgs = [
            status(pikachu, .primary, week: 92, reset: friday4am),
            status(charizard, .overflow, week: 96, reset: wednesday9pm),
        ]
        #expect(advise(orgs) == nil)
        #expect(SwitchAdvisor.statusLine(orgs, claudeCodeOrg: "pikachu", advice: nil, now: designNow, formatting: fmt, Thresholds())
                == "Both orgs are low. Charizard is back first, Wed 9 PM.")
    }

    @Test func unknownClaudeCodeOrgMeansNoAdvice() {
        let orgs = [
            status(pikachu, .primary, week: 60, reset: friday4am, session: 85, sessionReset: designNow.addingTimeInterval(3600)),
            status(charizard, .overflow, week: 10, reset: monday9am),
        ]
        #expect(advise(orgs, cc: nil) == nil)
        #expect(advise(orgs, cc: "someone-else") == nil)
    }

    @Test func tiesGoToOverflow() {
        let orgs = [
            status(pikachu, .primary, week: 10, reset: friday4am),
            status(charizard, .overflow, week: 10, reset: friday4am),
        ]
        #expect(SwitchAdvisor.best(orgs, now: designNow, Thresholds())?.org == charizard)
    }
}

@Suite struct AdviceGateTests {
    let toCharizard = Advice(target: charizard, reason: "x")
    let toPikachu = Advice(target: pikachu, reason: "y")

    @Test func needsTwoReadingsInARow() {
        var gate = AdviceGate()
        #expect(gate.update(toCharizard, claudeCodeOrg: "pikachu", currentIsRed: false, now: designNow) == nil)
        #expect(gate.update(toCharizard, claudeCodeOrg: "pikachu", currentIsRed: false, now: designNow) == toCharizard)
        #expect(gate.update(toCharizard, claudeCodeOrg: "pikachu", currentIsRed: false, now: designNow) == toCharizard)
    }

    @Test func flipFloppingNeverShows() {
        var gate = AdviceGate()
        for advice in [toCharizard, toPikachu, toCharizard, toPikachu] {
            #expect(gate.update(advice, claudeCodeOrg: "pikachu", currentIsRed: false, now: designNow) == nil)
        }
    }

    @Test func noAdviceClearsIt() {
        var gate = AdviceGate()
        _ = gate.update(toCharizard, claudeCodeOrg: "pikachu", currentIsRed: false, now: designNow)
        _ = gate.update(toCharizard, claudeCodeOrg: "pikachu", currentIsRed: false, now: designNow)
        #expect(gate.update(nil, claudeCodeOrg: "pikachu", currentIsRed: false, now: designNow) == nil)
        #expect(gate.update(toCharizard, claudeCodeOrg: "pikachu", currentIsRed: false, now: designNow) == nil)
    }

    @Test func holdsSwitchingBackForAnHour() {
        var gate = AdviceGate()
        _ = gate.update(toCharizard, claudeCodeOrg: "pikachu", currentIsRed: false, now: designNow)
        _ = gate.update(toCharizard, claudeCodeOrg: "pikachu", currentIsRed: false, now: designNow)
        // The owner moved to Charizard; ten minutes later the advice flips back.
        let later = designNow.addingTimeInterval(600)
        #expect(gate.update(toPikachu, claudeCodeOrg: "charizard", currentIsRed: false, now: later) == nil)
        #expect(gate.update(toPikachu, claudeCodeOrg: "charizard", currentIsRed: false, now: later) == nil)
        // After the hour it's allowed (still needing two readings).
        let afterHour = designNow.addingTimeInterval(3700)
        #expect(gate.update(toPikachu, claudeCodeOrg: "charizard", currentIsRed: false, now: afterHour) == nil)
        #expect(gate.update(toPikachu, claudeCodeOrg: "charizard", currentIsRed: false, now: afterHour) == toPikachu)
    }

    @Test func redOverridesTheHold() {
        var gate = AdviceGate()
        _ = gate.update(toCharizard, claudeCodeOrg: "pikachu", currentIsRed: false, now: designNow)
        _ = gate.update(toCharizard, claudeCodeOrg: "pikachu", currentIsRed: false, now: designNow)
        let later = designNow.addingTimeInterval(600)
        #expect(gate.update(toPikachu, claudeCodeOrg: "charizard", currentIsRed: true, now: later) == nil)
        #expect(gate.update(toPikachu, claudeCodeOrg: "charizard", currentIsRed: true, now: later) == toPikachu)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./test.sh`
Expected: build error `cannot find 'OrgStatus' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/ClaudeDockCore/SwitchAdvisor.swift`:

```swift
import Foundation

/// One org with everything the switch rules need.
public struct OrgStatus: Equatable, Sendable {
    public var org: Org
    public var role: Role
    public var reading: Reading
    public var light: Light

    public init(org: Org, role: Role, reading: Reading, light: Light) {
        self.org = org
        self.role = role
        self.reading = reading
        self.light = light
    }
}

/// "Move Claude Code to <target>", and why.
public struct Advice: Equatable, Sendable {
    public var target: Org
    public var reason: String

    public init(target: Org, reason: String) {
        self.target = target
        self.reason = reason
    }
}

public enum SwitchAdvisor {
    /// Enough room for Claude Code: week left above the minimum (higher for the primary org,
    /// which keeps a buffer for the desktop app) and a 5-hour window that isn't nearly full.
    public static func isEligible(_ s: OrgStatus, _ t: Thresholds) -> Bool {
        s.reading.weekLeft >= minimumWeekLeft(s.role, t) && s.reading.session < t.eligibleSessionBelow
    }

    /// The eligible org whose week resets soonest (use it or lose it); ties go to overflow.
    public static func best(_ orgs: [OrgStatus], now: Date, _ t: Thresholds) -> OrgStatus? {
        orgs.filter { isEligible($0, t) }.min { a, b in
            let resetA = a.reading.weekResetsAt ?? now.addingTimeInterval(Pace.window)
            let resetB = b.reading.weekResetsAt ?? now.addingTimeInterval(Pace.window)
            if resetA != resetB { return resetA < resetB }
            return a.role == .overflow && b.role != .overflow
        }
    }

    public static func advice(_ orgs: [OrgStatus], claudeCodeOrg: String?, now: Date,
                              formatting: Formatting, _ t: Thresholds) -> Advice? {
        guard let current = orgs.first(where: { $0.org.id == claudeCodeOrg }),
              let best = best(orgs, now: now, t), best.org.id != current.org.id else { return nil }
        return Advice(target: best.org, reason: reason(current: current, best: best, now: now, formatting: formatting, t))
    }

    /// The panel's top line.
    public static func statusLine(_ orgs: [OrgStatus], claudeCodeOrg: String?, advice: Advice?, now: Date,
                                  formatting: Formatting, _ t: Thresholds) -> String {
        if let advice { return "Move Claude Code to \(advice.target.name): \(advice.reason)." }
        if !orgs.isEmpty, !orgs.contains(where: { isEligible($0, t) }) {
            let low = orgs.count == 2 ? "Both orgs are low." : "Every org is low."
            let back = orgs.compactMap { s -> (OrgStatus, Date)? in
                let date = s.reading.weekLeft < minimumWeekLeft(s.role, t) ? s.reading.weekResetsAt : s.reading.sessionResetsAt
                return date.map { (s, $0) }
            }.min { $0.1 < $1.1 }
            guard let (first, date) = back else { return low }
            return "\(low) \(first.org.name) is back first, \(formatting.dayTime(date, now: now))."
        }
        if let current = orgs.first(where: { $0.org.id == claudeCodeOrg }) {
            return "Claude Code is on \(current.org.name), the right place right now."
        }
        return ""
    }

    static func minimumWeekLeft(_ role: Role, _ t: Thresholds) -> Double {
        role == .primary ? max(t.eligibleWeekLeft, t.primaryReserveWeekLeft) : t.eligibleWeekLeft
    }

    static func reason(current: OrgStatus, best: OrgStatus, now: Date, formatting: Formatting, _ t: Thresholds) -> String {
        let name = current.org.name
        if current.light == .red, current.reading.weekLeft < t.eligibleWeekLeft {
            return "\(name) is nearly out"
        }
        if current.reading.session >= t.eligibleSessionBelow {
            let busy = "\(name) 5h at \(Formatting.percent(current.reading.session))"
            return current.role == .primary ? "\(busy), desktop app needs room" : busy
        }
        if current.role == .primary, current.reading.weekLeft < t.primaryReserveWeekLeft {
            return "\(name) is down to \(Formatting.percent(current.reading.weekLeft)), keep it for the desktop app"
        }
        if let reset = best.reading.weekResetsAt {
            return "\(best.org.name) has \(Formatting.percent(best.reading.weekLeft)) expiring \(formatting.dayTime(reset, now: now))"
        }
        return "\(best.org.name) has more room"
    }
}

/// Keeps switch advice from flip-flopping. A target must win two readings in a row, and
/// advice to go back to the org the owner was just moved off is held for an hour, unless
/// the org they're on now turns red.
public struct AdviceGate: Sendable {
    public private(set) var shown: Advice?
    public var hold: TimeInterval = 3600
    private var pending: Advice?
    private var movedOff: String?
    private var shownAt: Date?

    public init() {}

    public mutating func update(_ candidate: Advice?, claudeCodeOrg: String?, currentIsRed: Bool, now: Date) -> Advice? {
        guard let candidate else {
            pending = nil
            shown = nil
            return nil
        }
        if candidate.target.id == shown?.target.id {
            shown = candidate
            return shown
        }
        if let movedOff, let shownAt, candidate.target.id == movedOff,
           now.timeIntervalSince(shownAt) < hold, !currentIsRed {
            pending = nil
            shown = nil
            return nil
        }
        if pending?.target.id == candidate.target.id {
            shown = candidate
            pending = nil
            movedOff = claudeCodeOrg
            shownAt = now
        } else {
            pending = candidate
            shown = nil
        }
        return shown
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./test.sh`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "Add switch advice with debounce and hold" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Local files: history and Claude Code's org

**Files:**
- Create: `Sources/ClaudeDockCore/HistoryStore.swift`, `Sources/ClaudeDockCore/ClaudeCodeAccount.swift`
- Test: `Tests/ClaudeDockCoreTests/LocalFilesTests.swift`

**Interfaces:**
- Consumes: `Reading`.
- Produces: `HistoryStore(url: URL)` with `static defaultURL`, `append(_ readings: [Reading]) throws`, `load() -> [Reading]`, `prune(olderThan: Date) throws`; `ClaudeCodeAccount(url: URL = ~/.claude.json)` with `currentOrg() -> String?`, `modified() -> Date?`.

- [ ] **Step 1: Write the failing test**

`Tests/ClaudeDockCoreTests/LocalFilesTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeDockCore

func tempFile(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("claudedock-tests-\(UUID().uuidString)")
        .appendingPathComponent(name)
}

@Suite struct HistoryStoreTests {
    let a = reading(org: "pikachu", week: 55, weekResetsAt: local(2026, 10, 9, 4), session: 1,
                    sessionResetsAt: local(2026, 10, 6, 16, 20), scoped: ["Fable": 31])
    let b = reading(org: "charizard", week: 0, weekResetsAt: nil)

    @Test func roundTrips() throws {
        let store = HistoryStore(url: tempFile("history.jsonl"))
        try store.append([a, b])
        #expect(store.load() == [a, b])
        try store.append([a])
        #expect(store.load().count == 3)
    }

    @Test func usesTheSpecKeys() throws {
        let store = HistoryStore(url: tempFile("history.jsonl"))
        try store.append([a])
        let line = try String(contentsOf: store.url, encoding: .utf8)
        for key in ["\"t\":", "\"org\":", "\"session\":", "\"sessionResetsAt\":", "\"week\":", "\"weekResetsAt\":", "\"scoped\":"] {
            #expect(line.contains(key))
        }
    }

    @Test func skipsCorruptLines() throws {
        let store = HistoryStore(url: tempFile("history.jsonl"))
        try store.append([a])
        let handle = try FileHandle(forWritingTo: store.url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("garbage{\n".utf8))
        try handle.close()
        try store.append([b])
        #expect(store.load() == [a, b])
    }

    @Test func prunesOldReadings() throws {
        let store = HistoryStore(url: tempFile("history.jsonl"))
        let old = reading(week: 10, weekResetsAt: nil, at: designNow.addingTimeInterval(-40 * 86_400))
        try store.append([old, a])
        try store.prune(olderThan: designNow.addingTimeInterval(-35 * 86_400))
        #expect(store.load() == [a])
    }

    @Test func missingFileLoadsEmpty() {
        #expect(HistoryStore(url: tempFile("none.jsonl")).load().isEmpty)
    }
}

@Suite struct ClaudeCodeAccountTests {
    func write(_ text: String) throws -> URL {
        let url = tempFile("claude.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func readsTheOrg() throws {
        let url = try write(#"{"numStartups": 3, "oauthAccount": {"organizationUuid": "00000000-0000-4000-8000-000000000001", "organizationName": "Pikachu"}}"#)
        #expect(ClaudeCodeAccount(url: url).currentOrg() == "00000000-0000-4000-8000-000000000001")
        #expect(ClaudeCodeAccount(url: url).modified() != nil)
    }

    @Test func missingOrMalformedMeansUnknown() throws {
        #expect(ClaudeCodeAccount(url: tempFile("absent.json")).currentOrg() == nil)
        #expect(ClaudeCodeAccount(url: try write("{not json")).currentOrg() == nil)
        #expect(ClaudeCodeAccount(url: try write(#"{"oauthAccount": {}}"#)).currentOrg() == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./test.sh`
Expected: build error `cannot find 'HistoryStore' in scope`.

- [ ] **Step 3: Write the implementations**

`Sources/ClaudeDockCore/HistoryStore.swift`:

```swift
import Foundation

/// The reading history: one JSON object per line. Corrupt lines are skipped, so a crash
/// mid-write costs one reading, not the history.
public final class HistoryStore: @unchecked Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClaudeDock/history.jsonl")
    }

    public func append(_ readings: [Reading]) throws {
        guard !readings.isEmpty else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.lines(readings)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }

    public func load() -> [Reading] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            try? Self.decoder.decode(Reading.self, from: Data(line.utf8))
        }
    }

    /// Rewrites the file without readings older than `cutoff`.
    public func prune(olderThan cutoff: Date) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try Self.lines(load().filter { $0.time >= cutoff }).write(to: url, options: .atomic)
    }

    private static func lines(_ readings: [Reading]) throws -> Data {
        var data = Data()
        for reading in readings {
            data.append(try encoder.encode(reading))
            data.append(0x0A)
        }
        return data
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
```

`Sources/ClaudeDockCore/ClaudeCodeAccount.swift`:

```swift
import Foundation

/// Which org Claude Code is signed into. Reads one field from Claude Code's config file
/// and nothing else.
public struct ClaudeCodeAccount: Sendable {
    public var url: URL

    public init(url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude.json")) {
        self.url = url
    }

    public func currentOrg() -> String? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = root["oauthAccount"] as? [String: Any] else { return nil }
        return account["organizationUuid"] as? String
    }

    public func modified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./test.sh`
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources Tests
git commit -m "Add reading history and Claude Code org lookup" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Chart geometry and on-screen text

**Files:**
- Create: `Sources/ClaudeDockCore/WeekChartModel.swift`, `Sources/ClaudeDockCore/Copy.swift`
- Test: `Tests/ClaudeDockCoreTests/WeekChartModelTests.swift`, `Tests/ClaudeDockCoreTests/CopyTests.swift`

**Interfaces:**
- Consumes: `WeekAxis`, `Reading`, `WeekForecast`, `Pace`, `Light`, `Thresholds`, `Formatting`.
- Produces: `ChartPoint(x:y:)`; `WeekChartModel` with `today`, `nowX`, `nowY`, `past`, `useItAll`, `yourPace`, `unused`, `resetX: Double?`, `nextWindow`, `days`, and `static make(axis:now:reading:forecast:history:) -> WeekChartModel`; `Copy.widgetSubline(_:light:forecast:now:formatting:_:) -> String`, `Copy.backTime(_:_:) -> Date?`, `Copy.Today(main: String, warning: String?)`, `Copy.today(_:forecast:now:formatting:_:) -> Copy.Today`, `Copy.weekLine(_:forecast:now:formatting:) -> String`.

- [ ] **Step 1: Write the failing tests**

`Tests/ClaudeDockCoreTests/WeekChartModelTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct WeekChartModelTests {
    let axis = WeekAxis(containing: designNow, calendar: newYork)

    func chart(_ r: Reading, history: [Reading] = []) -> WeekChartModel {
        WeekChartModel.make(axis: axis, now: designNow, reading: r,
                            forecast: Pace.forecast(r, history: history, now: designNow, calendar: newYork), history: history)
    }

    @Test func primaryOnDesignDay() {
        let c = chart(reading(week: 55, weekResetsAt: local(2026, 10, 9, 4)))
        #expect(near(c.nowX, 35.5333 / 168, 0.0001))
        #expect(c.nowY == 0.55)
        // The window began Friday, before this Monday: the line enters at the average value.
        #expect(c.past.count == 2)
        #expect(c.past[0].x == 0)
        #expect(near(c.past[0].y, 0.55 * 68 / 103.5333, 0.001))
        #expect(near(c.resetX!, 76.0 / 168, 0.0001))
        #expect(c.useItAll.last == ChartPoint(x: c.resetX!, y: 1))
        #expect(c.unused.count == 3)
        #expect(near(c.nextWindow.last!.y, 68.0 / 168, 0.001))
        #expect(c.nextWindow.last!.x == 1)
        #expect(c.days.count == 7)
    }

    @Test func historyFromThisWindowIsDrawn() {
        let reset = local(2026, 10, 9, 4)
        let earlier = reading(week: 40, weekResetsAt: reset, at: local(2026, 10, 5, 12))
        let c = chart(reading(week: 55, weekResetsAt: reset), history: [earlier])
        #expect(c.past.count == 3)
        #expect(c.past[1] == ChartPoint(x: axis.x(local(2026, 10, 5, 12)), y: 0.4))
    }

    @Test func runningOutFlattensAtTheTop() {
        let c = chart(reading(org: "charizard", week: 95, weekResetsAt: local(2026, 10, 7, 21)))
        #expect(c.yourPace.count == 3)
        #expect(c.yourPace[1].y == 1)
        #expect(c.yourPace[2].y == 1)
        #expect(c.unused.isEmpty)
    }

    @Test func resetAfterThisWeekIsClippedAtSunday() {
        let c = chart(reading(week: 10, weekResetsAt: local(2026, 10, 12, 6)))
        #expect(c.resetX == nil)
        #expect(c.nextWindow.isEmpty)
        #expect(c.useItAll.last!.x == 1)
        #expect(near(c.useItAll.last!.y, (10 + 90 * (132.4667 / 138.4667)) / 100, 0.001))
        #expect(c.unused.count == 3)
        #expect(c.unused[1].x == 1 && c.unused[2].x == 1)
    }

    // Review Focus 1
    @Test func weekNotStartedHasOnlyNow() {
        let c = chart(reading(week: 0, weekResetsAt: nil))
        #expect(c.past == [ChartPoint(x: c.nowX, y: 0)])
        #expect(c.useItAll.isEmpty && c.yourPace.isEmpty && c.unused.isEmpty && c.resetX == nil)
    }
}
```

`Tests/ClaudeDockCoreTests/CopyTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct CopyTests {
    let primary = reading(week: 55, weekResetsAt: local(2026, 10, 9, 4), session: 1,
                          sessionResetsAt: local(2026, 10, 6, 16, 20))
    let overflow = reading(org: "charizard", week: 95, weekResetsAt: local(2026, 10, 7, 21))

    func forecast(_ r: Reading) -> WeekForecast? { Pace.forecast(r, history: [], now: designNow, calendar: newYork) }
    func light(_ r: Reading) -> Light { Stoplight.light(r, forecast(r)) }

    @Test func todayForTheDesignDayPrimary() {
        let today = Copy.today(primary, forecast: forecast(primary), now: designNow, formatting: fmt)
        #expect(today.main == "Use about 9% more by midnight (to ~64% used), then about 17% a day.")
        #expect(today.warning == "At your current ~13% a day, about 11% goes unused by Fri 4 AM.")
    }

    @Test func todayForANearlyOutOrg() {
        let today = Copy.today(overflow, forecast: forecast(overflow), now: designNow, formatting: fmt)
        #expect(today.main == "Only 5% left until Wed 9 PM, about 7 hours at your recent pace.")
        #expect(today.warning == nil)
    }

    @Test func todayWhenResetComesBeforeMidnight() {
        let r = reading(week: 70, weekResetsAt: local(2026, 10, 6, 16))
        let today = Copy.today(r, forecast: forecast(r), now: designNow, formatting: fmt)
        #expect(today.main == "Use the last 30% before 4 PM.")
        #expect(today.warning == "At your current ~10% a day, about 28% goes unused by 4 PM.")
    }

    @Test func todayWhenRunningOutEarly() {
        let r = reading(week: 80, weekResetsAt: local(2026, 10, 9, 4))
        let today = Copy.today(r, forecast: forecast(r), now: designNow, formatting: fmt)
        #expect(today.main == "Ease off to about 7% a day to last until Fri 4 AM.")
        #expect(today.warning?.hasPrefix("At your current ~19% a day it runs out ") == true)
    }

    // Review Focus 1
    @Test func todayBeforeTheWeekStarts() {
        let r = reading(week: 0, weekResetsAt: nil)
        #expect(Copy.today(r, forecast: nil, now: designNow, formatting: fmt).main
                == "This week hasn't started. Nothing is used yet.")
        #expect(Copy.weekLine(r, forecast: nil, now: designNow, formatting: fmt) == "this week hasn't started")
    }

    @Test func weekLine() {
        #expect(Copy.weekLine(primary, forecast: forecast(primary), now: designNow, formatting: fmt)
                == "62% of the week gone · resets Fri 4 AM")
    }

    @Test func widgetSublines() {
        #expect(Copy.widgetSubline(primary, light: light(primary), forecast: forecast(primary), now: designNow, formatting: fmt)
                == "5h: 1% used · 12m in")
        #expect(Copy.widgetSubline(overflow, light: light(overflow), forecast: forecast(overflow), now: designNow, formatting: fmt)
                == "back Wed 9 PM · 5h idle")
        let idle = reading(week: 20, weekResetsAt: local(2026, 10, 9, 4))
        #expect(Copy.widgetSubline(idle, light: light(idle), forecast: forecast(idle), now: designNow, formatting: fmt) == "5h idle")
    }

    @Test func backTimeIsTheBlockingWindow() {
        #expect(Copy.backTime(overflow, Thresholds()) == local(2026, 10, 7, 21))
        let maxed = reading(week: 40, weekResetsAt: local(2026, 10, 9, 4), session: 97, sessionResetsAt: local(2026, 10, 6, 13))
        #expect(Copy.backTime(maxed, Thresholds()) == local(2026, 10, 6, 13))
        #expect(Copy.backTime(primary, Thresholds()) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./test.sh`
Expected: build error `cannot find 'WeekChartModel' in scope`.

- [ ] **Step 3: Write the chart geometry**

`Sources/ClaudeDockCore/WeekChartModel.swift`:

```swift
import Foundation

/// A point on a week chart: x is the share of the Mon–Sun week (0...1), y is % used / 100.
public struct ChartPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Everything a week chart draws, in unit coordinates, so the view only scales and strokes.
public struct WeekChartModel: Equatable, Sendable {
    public var today: ClosedRange<Double>
    public var nowX: Double
    public var nowY: Double
    /// Window start (0%), this window's readings, and now.
    public var past: [ChartPoint]
    /// From now to 100% exactly at reset.
    public var useItAll: [ChartPoint]
    /// From now at the current pace (flat at 100% once it runs out).
    public var yourPace: [ChartPoint]
    /// Polygon between the two at reset: what would go unused. Empty when nothing would.
    public var unused: [ChartPoint]
    /// nil when the reset falls outside this week.
    public var resetX: Double?
    /// The next window at use-it-all pace, from the reset to Sunday night.
    public var nextWindow: [ChartPoint]
    public var days: [DayMark]

    public static func make(axis: WeekAxis, now: Date, reading: Reading, forecast: WeekForecast?,
                            history: [Reading]) -> WeekChartModel {
        var past: [(Date, Double)] = []
        if let reset = reading.weekResetsAt {
            let start = reset.addingTimeInterval(-Pace.window)
            past.append((start, 0))
            past += history
                .filter { $0.org == reading.org && $0.weekResetsAt == reset && $0.time > start && $0.time < now }
                .sorted { $0.time < $1.time }
                .map { ($0.time, $0.week) }
        }
        past.append((now, reading.week))

        var model = WeekChartModel(today: axis.today(now), nowX: axis.x(now), nowY: reading.week / 100,
                                   past: clip(past, axis), useItAll: [], yourPace: [], unused: [],
                                   resetX: nil, nextWindow: [], days: axis.days)
        guard let reset = reading.weekResetsAt, let forecast else { return model }

        let allLine = [(now, reading.week), (reset, 100.0)]
        var paceLine = [(now, reading.week)]
        if let out = forecast.runsOutAt {
            paceLine += [(out, 100), (reset, 100)]
        } else {
            paceLine.append((reset, forecast.forecastAtReset))
        }
        model.useItAll = clip(allLine, axis)
        model.yourPace = clip(paceLine, axis)

        if forecast.unused > 0.05 {
            let edge = min(reset, axis.end)
            model.unused = [(now, reading.week), (edge, value(paceLine, at: edge)), (edge, value(allLine, at: edge))]
                .map { point($0, axis) }
        }
        if axis.contains(reset) {
            model.resetX = axis.x(reset)
            let nextAtEnd = axis.end.timeIntervalSince(reset) / Pace.window * 100
            model.nextWindow = [point((reset, 0), axis), point((axis.end, nextAtEnd), axis)]
        }
        return model
    }

    /// Keeps the part of a line inside the week, interpolating where it crosses the edges.
    static func clip(_ line: [(Date, Double)], _ axis: WeekAxis) -> [ChartPoint] {
        var kept: [(Date, Double)] = []
        for (i, p) in line.enumerated() {
            if p.0 < axis.start {
                if i + 1 < line.count, line[i + 1].0 > axis.start {
                    kept.append((axis.start, interpolate(p, line[i + 1], at: axis.start)))
                }
                continue
            }
            if p.0 > axis.end {
                if i > 0, line[i - 1].0 < axis.end {
                    kept.append((axis.end, interpolate(line[i - 1], p, at: axis.end)))
                }
                break
            }
            kept.append(p)
        }
        return kept.map { point($0, axis) }
    }

    static func value(_ line: [(Date, Double)], at date: Date) -> Double {
        for i in 1..<line.count where date <= line[i].0 {
            return interpolate(line[i - 1], line[i], at: date)
        }
        return line.last!.1
    }

    static func interpolate(_ a: (Date, Double), _ b: (Date, Double), at date: Date) -> Double {
        let span = b.0.timeIntervalSince(a.0)
        guard span > 0 else { return b.1 }
        return a.1 + (b.1 - a.1) * date.timeIntervalSince(a.0) / span
    }

    static func point(_ p: (Date, Double), _ axis: WeekAxis) -> ChartPoint {
        ChartPoint(x: axis.x(p.0), y: p.1 / 100)
    }
}
```

- [ ] **Step 4: Write the on-screen text**

`Sources/ClaudeDockCore/Copy.swift`:

```swift
import Foundation

/// The sentences the widget and panel show, kept here so they can be tested.
public enum Copy {
    public struct Today: Equatable, Sendable {
        public var main: String
        public var warning: String?
    }

    /// Under the widget's 5-hour bar.
    public static func widgetSubline(_ r: Reading, light: Light, forecast: WeekForecast?, now: Date,
                                     formatting: Formatting, _ t: Thresholds = Thresholds()) -> String {
        if light == .red, let back = backTime(r, t) {
            return "back \(formatting.dayTime(back, now: now))" + (r.sessionResetsAt == nil ? " · 5h idle" : "")
        }
        guard let reset = r.sessionResetsAt else { return "5h idle" }
        let into = now.timeIntervalSince(reset.addingTimeInterval(-5 * 3600))
        return "5h: \(Formatting.percent(r.session)) used · \(Formatting.compact(into)) in"
    }

    /// When a red org can be used again: its week reset if the week is nearly out, its
    /// 5-hour reset if that window is maxed; nil when it's red only for running out early.
    public static func backTime(_ r: Reading, _ t: Thresholds) -> Date? {
        if r.weekLeft < t.redWeekLeft { return r.weekResetsAt }
        if r.session >= t.redSession { return r.sessionResetsAt }
        return nil
    }

    /// "62% of the week gone · resets Fri 4 AM"
    public static func weekLine(_ r: Reading, forecast: WeekForecast?, now: Date, formatting: Formatting) -> String {
        guard let forecast, let reset = r.weekResetsAt else { return "this week hasn't started" }
        return "\(Formatting.percent(forecast.elapsedFraction * 100)) of the week gone · resets \(formatting.dayTime(reset, now: now))"
    }

    /// The panel's TODAY box.
    public static func today(_ r: Reading, forecast: WeekForecast?, now: Date,
                             formatting: Formatting, _ t: Thresholds = Thresholds()) -> Today {
        guard let f = forecast, let reset = r.weekResetsAt else {
            return Today(main: "This week hasn't started. Nothing is used yet.", warning: nil)
        }
        let resetText = formatting.dayTime(reset, now: now)
        if r.weekLeft < t.redWeekLeft {
            var main = "Only \(Formatting.percent(r.weekLeft)) left until \(resetText)"
            if f.pacePerHour > 0 { main += ", about \(hours(r.weekLeft / f.pacePerHour)) at your recent pace" }
            return Today(main: main + ".", warning: nil)
        }
        if let out = f.runsOutAt, let early = f.runsOutEarlyByHours {
            return Today(
                main: "Ease off to about \(Formatting.percent(f.useItAllPerDay)) a day to last until \(resetText).",
                warning: "At your current ~\(Formatting.percent(f.pacePerDay)) a day it runs out \(formatting.dayTime(out, now: now)), \(Formatting.compact(early * 3600)) early.")
        }
        let main: String
        if f.byMidnight >= r.weekLeft - 0.001 {
            main = "Use the last \(Formatting.percent(r.weekLeft)) before \(resetText)."
        } else {
            main = "Use about \(Formatting.percent(f.byMidnight)) more by midnight (to ~\(Formatting.percent(r.week + f.byMidnight)) used), then about \(Formatting.percent(f.useItAllPerDay)) a day."
        }
        let warning = f.unused >= t.onPaceUnused
            ? "At your current ~\(Formatting.percent(f.pacePerDay)) a day, about \(Formatting.percent(f.unused)) goes unused by \(resetText)."
            : nil
        return Today(main: main, warning: warning)
    }

    static func hours(_ h: Double) -> String {
        h < 1 ? "\(max(Int(h * 60), 1)) minutes" : "\(Int(h.rounded())) hours"
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./test.sh`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "Add week chart geometry and on-screen text" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: The app with demo data (widget, panel, renders)

Deliverable: `build/Claude Dock.app` runs in demo mode showing the corner widget and the click-to-open panel, and `--render` writes PNGs of every demo scenario.

**Files:**
- Modify: `Package.swift` (add the `ClaudeDock` executable target)
- Create: `Sources/ClaudeDock/main.swift`, `AppDelegate.swift`, `AppModel.swift`, `Settings.swift`, `DemoData.swift`, `Palette.swift`, `Components.swift`, `WidgetView.swift`, `PanelView.swift`, `WeekChart.swift`, `FloatingPanel.swift`, `DockController.swift`, `Renderer.swift` (all under `Sources/ClaudeDock/`)
- Create: `build.sh`

**Interfaces:**
- Consumes: everything in `ClaudeDockCore`.
- Produces: `AppModel` (`orgs`, `latest`, `history`, `claudeCodeOrg`, `advice`, `signedIn`, `lastError`, `now`, `settings`, `formatting`, `onAdvice`, `onRed`, `lastUpdated`, `isStale`, `role(of:)`, `reading(for:)`, `forecast(for:)`, `light(for:)`, `statuses`, `statusLine`, `setAvailableOrgs(_:claudeCodeOrg:)`, `ingest(_:claudeCodeOrg:at:)`, `setClaudeCodeOrg(_:)`, `tick()`, `apply(_ scenario: DemoScenario)`, `leaveDemo()`); `Settings(defaults:)`; `WidgetActions`; `DockController(model:actions:)` with `show()`, `hide(for:)`, `togglePanel()`, `openPanel()`, `closePanel()`, `onPanelOpened`; `DemoData.scenarios(now:)`; `Renderer.renderDemo(to:)`.

- [ ] **Step 1: Add the app target**

Replace `Package.swift` with:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudeDock",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClaudeDockCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ClaudeDock",
            dependencies: ["ClaudeDockCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "ClaudeDockCoreTests",
            dependencies: ["ClaudeDockCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

- [ ] **Step 2: Settings and the app model**

`Sources/ClaudeDock/Settings.swift`:

```swift
import Foundation
import ClaudeDockCore

/// The owner's choices, saved in UserDefaults on this Mac only.
@MainActor
final class Settings: ObservableObject {
    private let defaults: UserDefaults

    @Published var thresholds: Thresholds { didSet { save(thresholds, "thresholds") } }
    @Published var primaryOrg: String? { didSet { defaults.set(primaryOrg, forKey: "primaryOrg") } }
    @Published var shownOrgs: [String]? { didSet { defaults.set(shownOrgs, forKey: "shownOrgs") } }
    @Published var knownOrgs: [Org] { didSet { save(knownOrgs, "knownOrgs") } }
    @Published var notifySwitch: Bool { didSet { defaults.set(notifySwitch, forKey: "notifySwitch") } }
    @Published var notifyRed: Bool { didSet { defaults.set(notifyRed, forKey: "notifyRed") } }
    @Published var demoMode: Bool { didSet { defaults.set(demoMode, forKey: "demoMode") } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        thresholds = Self.load(Thresholds.self, "thresholds", defaults) ?? Thresholds()
        primaryOrg = defaults.string(forKey: "primaryOrg")
        shownOrgs = defaults.stringArray(forKey: "shownOrgs")
        knownOrgs = Self.load([Org].self, "knownOrgs", defaults) ?? []
        notifySwitch = defaults.object(forKey: "notifySwitch") as? Bool ?? true
        notifyRed = defaults.object(forKey: "notifyRed") as? Bool ?? true
        demoMode = defaults.bool(forKey: "demoMode")
    }

    /// The owner's picks, or by default every paid org (a free personal org has no billing type).
    func isShown(_ org: Org) -> Bool {
        shownOrgs.map { $0.contains(org.id) } ?? (org.billingType != nil)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
```

`Sources/ClaudeDock/AppModel.swift`:

```swift
import Foundation
import ClaudeDockCore

/// Everything the widget and panel show: orgs, readings, and what's derived from them.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var orgs: [Org] = []
    @Published private(set) var latest: [String: Reading] = [:]
    @Published private(set) var history: [Reading] = []
    @Published private(set) var claudeCodeOrg: String?
    @Published private(set) var advice: Advice?
    @Published var signedIn = true
    @Published var lastError: String?
    @Published var now = Date()

    let settings: Settings
    let formatting = Formatting()
    var onAdvice: ((Advice) -> Void)?
    var onRed: ((Org) -> Void)?

    private let store: HistoryStore
    private var gate = AdviceGate()
    private var primaryOverride: String?
    private static let keep: TimeInterval = 35 * 24 * 3600

    init(settings: Settings, store: HistoryStore) {
        self.settings = settings
        self.store = store
        try? store.prune(olderThan: Date().addingTimeInterval(-Self.keep))
        history = store.load()
    }

    var lastUpdated: Date? { latest.values.map(\.time).max() }

    /// Signed out, or nothing newer than 10 minutes.
    var isStale: Bool { !signedIn || (lastUpdated.map { now.timeIntervalSince($0) > 600 } ?? true) }

    func role(of org: Org) -> Role { org.id == (primaryOverride ?? settings.primaryOrg) ? .primary : .overflow }
    func reading(for org: Org) -> Reading? { latest[org.id]?.adjusted(to: now) }
    func forecast(for org: Org) -> WeekForecast? {
        reading(for: org).flatMap { Pace.forecast($0, history: history, now: now) }
    }
    func light(for org: Org) -> Light? {
        reading(for: org).map { Stoplight.light($0, forecast(for: org), settings.thresholds) }
    }

    var statuses: [OrgStatus] {
        orgs.compactMap { org in
            guard let r = reading(for: org), let l = light(for: org) else { return nil }
            return OrgStatus(org: org, role: role(of: org), reading: r, light: l)
        }
    }

    var statusLine: String {
        SwitchAdvisor.statusLine(statuses, claudeCodeOrg: claudeCodeOrg, advice: advice, now: now,
                                 formatting: formatting, settings.thresholds)
    }

    /// The org list from claude.ai: show the selected orgs, primary first. The first time,
    /// the org Claude Code is signed into becomes the primary org.
    func setAvailableOrgs(_ all: [Org], claudeCodeOrg: String?) {
        settings.knownOrgs = all
        let shown = all.filter { settings.isShown($0) }
        if !shown.contains(where: { $0.id == settings.primaryOrg }) {
            settings.primaryOrg = shown.first(where: { $0.id == claudeCodeOrg })?.id ?? shown.first?.id
        }
        orgs = shown.sorted { role(of: $0) == .primary && role(of: $1) != .primary }
    }

    func ingest(_ readings: [Reading], claudeCodeOrg: String?, at time: Date) {
        let wasRed = currentOrgIsRed
        now = time
        self.claudeCodeOrg = claudeCodeOrg
        for r in readings { latest[r.org] = r }
        history.append(contentsOf: readings)
        try? store.append(readings)
        signedIn = true
        lastError = nil
        updateAdvice()
        if !wasRed, currentOrgIsRed, let org = orgs.first(where: { $0.id == claudeCodeOrg }) { onRed?(org) }
    }

    func setClaudeCodeOrg(_ id: String?) {
        guard id != claudeCodeOrg else { return }
        claudeCodeOrg = id
        updateAdvice()
    }

    func tick() { now = Date() }

    private var currentOrgIsRed: Bool { statuses.first { $0.org.id == claudeCodeOrg }?.light == .red }

    private func updateAdvice() {
        let candidate = SwitchAdvisor.advice(statuses, claudeCodeOrg: claudeCodeOrg, now: now,
                                             formatting: formatting, settings.thresholds)
        let previous = advice
        advice = gate.update(candidate, claudeCodeOrg: claudeCodeOrg, currentIsRed: currentOrgIsRed, now: now)
        if let advice, advice.target != previous?.target { onAdvice?(advice) }
    }

    // MARK: Demo mode

    func apply(_ scenario: DemoScenario) {
        primaryOverride = scenario.primary
        orgs = scenario.orgs
        latest = Dictionary(uniqueKeysWithValues: scenario.readings.map { ($0.org, $0) })
        history = []
        claudeCodeOrg = scenario.claudeCodeOrg
        now = scenario.now
        signedIn = true
        advice = SwitchAdvisor.advice(statuses, claudeCodeOrg: claudeCodeOrg, now: now,
                                      formatting: formatting, settings.thresholds)
    }

    func leaveDemo() {
        primaryOverride = nil
        orgs = []
        latest = [:]
        advice = nil
        history = store.load()
        now = Date()
    }
}
```

`Sources/ClaudeDock/DemoData.swift`:

```swift
import Foundation
import ClaudeDockCore

/// One canned state for demo mode and `--render`.
struct DemoScenario {
    var name: String
    var orgs: [Org]
    var primary: String
    var readings: [Reading]
    var claudeCodeOrg: String
    var now: Date
}

/// Pokémon sample data, so no real account ever shows up in a demo or a screenshot.
enum DemoData {
    static let pikachu = Org(id: "demo-pikachu", name: "Pikachu", billingType: "demo")
    static let charizard = Org(id: "demo-charizard", name: "Charizard", billingType: "demo")

    /// Every scenario, relative to `now` so demo mode looks right on any day.
    static func scenarios(now: Date = Date()) -> [DemoScenario] {
        func at(_ hours: Double) -> Date { now.addingTimeInterval(hours * 3600) }
        func r(_ org: Org, week: Double, weekReset: Double?, session: Double = 0,
               sessionReset: Double? = nil, fable: Double = 20) -> Reading {
            Reading(time: now, org: org.id, session: session, sessionResetsAt: sessionReset.map(at),
                    week: week, weekResetsAt: weekReset.map(at), scoped: ["Fable": fable])
        }
        func scenario(_ name: String, _ readings: [Reading]) -> DemoScenario {
            DemoScenario(name: name, orgs: [pikachu, charizard], primary: pikachu.id,
                         readings: readings, claudeCodeOrg: pikachu.id, now: now)
        }
        return [
            scenario("green-and-red", [
                r(pikachu, week: 55, weekReset: 64.5, session: 1, sessionReset: 4.8, fable: 31),
                r(charizard, week: 95, weekReset: 33.5, fable: 2),
            ]),
            scenario("switch-for-desktop-app", [
                r(pikachu, week: 60, weekReset: 64.5, session: 85, sessionReset: 1.5),
                r(charizard, week: 60, weekReset: 140),
            ]),
            scenario("use-it-before-it-expires", [
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
```

- [ ] **Step 3: Colors, shared pieces and the widget**

`Sources/ClaudeDock/Palette.swift`:

```swift
import AppKit
import SwiftUI
import ClaudeDockCore

/// Colors from the design: blue for usage, a stoplight set for state, amber for "would go unused".
enum Palette {
    static let accent = dynamic(light: 0x2A78D6, dark: 0x3987E5)
    static let good = dynamic(light: 0x0CA30C, dark: 0x0CA30C)
    static let warn = dynamic(light: 0xFAB219, dark: 0xFAB219)
    static let crit = dynamic(light: 0xD03B3B, dark: 0xD03B3B)

    static func color(for light: Light) -> Color {
        switch light {
        case .green: good
        case .yellow: warn
        case .red: crit
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// `--render` can't draw translucent materials, so it asks for a solid background instead.
private struct SolidBackgroundKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var solidBackground: Bool {
        get { self[SolidBackgroundKey.self] }
        set { self[SolidBackgroundKey.self] = newValue }
    }
}

/// The rounded, translucent card both windows use.
struct HUDBackground: ViewModifier {
    @Environment(\.solidBackground) private var solid
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        content
            .background {
                if solid {
                    shape.fill(scheme == .dark ? Color(white: 0.11) : Color(white: 0.97))
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay(shape.strokeBorder(Color.primary.opacity(0.12)))
            .clipShape(shape)
    }
}

extension View {
    func hud(radius: CGFloat) -> some View { modifier(HUDBackground(radius: radius)) }
}
```

`Sources/ClaudeDock/Components.swift`:

```swift
import SwiftUI
import ClaudeDockCore

/// The week ring: fill = % used, tick = how much of the week has gone by.
struct WeekRing: View {
    var used: Double
    var elapsed: Double
    var color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.26), lineWidth: 6)
            Circle().trim(from: 0, to: used / 100)
                .stroke(color, lineWidth: 6)
                .rotationEffect(.degrees(-90))
            Capsule().fill(Color.primary).frame(width: 2, height: 10)
                .offset(y: -18)
                .rotationEffect(.degrees(elapsed * 360))
            Text(Formatting.percent(used)).font(.system(size: 10.5, weight: .bold))
        }
        .frame(width: 36, height: 36)
        .frame(width: 48, height: 48)
    }
}

/// A thin bar: fill = % used, tick = how far through the window we are.
struct UsageBar: View {
    var used: Double
    var tick: Double?
    var color: Color
    var height: CGFloat = 6
    var off = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(off ? Color.primary.opacity(0.12) : color.opacity(0.26))
                if !off {
                    Capsule().fill(color).frame(width: used > 0 ? max(geo.size.width * used / 100, height) : 0)
                    if let tick {
                        Capsule().fill(Color.primary).frame(width: 2, height: height + 6)
                            .offset(x: geo.size.width * tick - 1)
                    }
                }
            }
        }
        .frame(height: height)
    }
}

/// The stoplight dot. Green pulses (faster when more would go unused) unless Reduce Motion is on.
struct StoplightDot: View {
    var light: Light
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        let color = Palette.color(for: light)
        Circle().fill(color).frame(width: 9, height: 9)
            .overlay {
                if case .green(let pulse?) = light, !reduceMotion {
                    Circle().stroke(color, lineWidth: 2)
                        .scaleEffect(pulsing ? 2.4 : 1)
                        .opacity(pulsing ? 0 : 0.8)
                        .animation(.easeOut(duration: pulse.rawValue).repeatForever(autoreverses: false), value: pulsing)
                        .onAppear { pulsing = true }
                }
            }
            .accessibilityLabel(label)
    }

    private var label: String {
        switch light {
        case .green: "Use it"
        case .yellow: "On pace"
        case .red: "Nearly out"
        }
    }
}

/// What the widget's and panel's buttons and menu items do.
struct WidgetActions {
    var tap: () -> Void = {}
    var refresh: () -> Void = {}
    var hide: () -> Void = {}
    var settings: () -> Void = {}
    var signInOut: () -> Void = {}
    var quit: () -> Void = {}

    static let none = WidgetActions()
}
```

`Sources/ClaudeDock/WidgetView.swift`:

```swift
import SwiftUI
import ClaudeDockCore

/// The always-on corner widget, Dock height: one block per org, plus a switch tab when
/// there's advice.
struct WidgetView: View {
    @ObservedObject var model: AppModel
    var actions: WidgetActions

    var body: some View {
        HStack(spacing: 0) {
            if let advice = model.advice {
                VStack(spacing: 1) {
                    Text("⇄").font(.system(size: 14)).foregroundStyle(Palette.warn)
                    Text("\(advice.target.name)\nfirst")
                        .font(.system(size: 9.5, weight: .semibold))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 9)
                .frame(maxHeight: .infinity)
                .background(Palette.warn.opacity(0.16))
                Divider()
            }
            if model.orgs.isEmpty {
                Text(model.signedIn ? "Loading usage…" : "Sign in to claude.ai")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 16)
            }
            ForEach(Array(model.orgs.enumerated()), id: \.element.id) { index, org in
                if index > 0 { Divider() }
                OrgBlock(model: model, org: org)
            }
        }
        .frame(height: 60)
        .hud(radius: 16)
        .opacity(model.isStale ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: actions.tap)
        .contextMenu {
            Button("Refresh now", action: actions.refresh)
            Button("Hide for 1 hour", action: actions.hide)
            Button("Settings…", action: actions.settings)
            Button(model.signedIn ? "Sign out" : "Sign in…", action: actions.signInOut)
            Divider()
            Button("Quit Claude Dock", action: actions.quit)
        }
    }
}

private struct OrgBlock: View {
    @ObservedObject var model: AppModel
    let org: Org

    var body: some View {
        let reading = model.reading(for: org)
        let forecast = model.forecast(for: org)
        let light = model.light(for: org) ?? .yellow
        let red = light == .red
        HStack(spacing: 8) {
            WeekRing(used: reading?.week ?? 0, elapsed: forecast?.elapsedFraction ?? 0,
                     color: red ? Palette.crit : Palette.accent)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(org.name).font(.system(size: 11, weight: .semibold))
                    StoplightDot(light: light)
                }
                UsageBar(used: reading?.session ?? 0, tick: reading?.sessionElapsedFraction(now: model.now),
                         color: Palette.accent, off: reading?.sessionResetsAt == nil)
                Text(reading.map {
                    Copy.widgetSubline($0, light: light, forecast: forecast, now: model.now,
                                       formatting: model.formatting, model.settings.thresholds)
                } ?? "no reading yet")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(width: 116, alignment: .leading)
        }
        .padding(.leading, 7)
        .padding(.trailing, 11)
        .frame(maxHeight: .infinity)
        .background(red ? Palette.crit.opacity(0.18) : Color.clear)
    }
}
```

- [ ] **Step 4: The panel and its chart**

`Sources/ClaudeDock/WeekChart.swift`:

```swift
import SwiftUI
import ClaudeDockCore

/// One org's week on the shared Mon–Sun axis: today's column, the "now" line, history,
/// the use-it-all and current-pace lines, the "would go unused" wedge, and the reset.
struct WeekChart: View {
    let chart: WeekChartModel
    let red: Bool
    let resetLabel: String?

    var body: some View {
        Canvas { ctx, size in
            let plot = CGRect(x: 0, y: 12, width: size.width, height: size.height - 34)
            let lineColor = red ? Palette.crit : Palette.accent
            func pt(_ p: ChartPoint) -> CGPoint { CGPoint(x: plot.minX + p.x * plot.width, y: plot.maxY - p.y * plot.height) }
            func path(_ points: [ChartPoint]) -> Path {
                var path = Path()
                guard let first = points.first else { return path }
                path.move(to: pt(first))
                points.dropFirst().forEach { path.addLine(to: pt($0)) }
                return path
            }
            func vertical(_ x: Double) -> Path {
                Path { $0.move(to: CGPoint(x: plot.minX + x * plot.width, y: plot.minY)); $0.addLine(to: CGPoint(x: plot.minX + x * plot.width, y: plot.maxY)) }
            }

            let todayX = plot.minX + chart.today.lowerBound * plot.width
            let todayWidth = (chart.today.upperBound - chart.today.lowerBound) * plot.width
            ctx.fill(Path(CGRect(x: todayX, y: plot.minY, width: todayWidth, height: plot.height)), with: .color(.primary.opacity(0.08)))
            ctx.draw(Text("TODAY").font(.system(size: 8.5, weight: .bold)).foregroundColor(.primary),
                     at: CGPoint(x: todayX + todayWidth / 2, y: 5))

            for day in chart.days.dropFirst() { ctx.stroke(vertical(day.start), with: .color(.primary.opacity(0.08)), lineWidth: 1) }
            ctx.stroke(path([ChartPoint(x: 0, y: 1), ChartPoint(x: 1, y: 1)]), with: .color(.primary.opacity(0.12)), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            ctx.stroke(path([ChartPoint(x: 0, y: 0), ChartPoint(x: 1, y: 0)]), with: .color(.primary.opacity(0.25)), lineWidth: 1)

            if chart.unused.count >= 3 {
                var wedge = path(chart.unused)
                wedge.closeSubpath()
                ctx.fill(wedge, with: .color(Palette.warn.opacity(0.5)))
            }
            ctx.stroke(path(chart.past), with: .color(lineColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            ctx.stroke(path(chart.useItAll), with: .color(.secondary), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            ctx.stroke(path(chart.yourPace), with: .color(lineColor), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 4]))

            if let resetX = chart.resetX {
                ctx.stroke(vertical(resetX), with: .color(Palette.accent), lineWidth: 1.5)
                ctx.stroke(path(chart.nextWindow), with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                if let resetLabel {
                    ctx.draw(Text("↺ \(resetLabel)").font(.system(size: 8.5)).foregroundColor(.secondary),
                             at: CGPoint(x: plot.minX + resetX * plot.width, y: 5))
                }
            }

            ctx.stroke(vertical(chart.nowX), with: .color(.primary), lineWidth: 1.5)
            let dot = pt(ChartPoint(x: chart.nowX, y: chart.nowY))
            ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)), with: .color(lineColor))
            let labelY = dot.y + 14 < plot.maxY ? dot.y + 12 : dot.y - 10
            ctx.draw(Text("now · \(Formatting.percent(chart.nowY * 100))").font(.system(size: 9.5, weight: .semibold)).foregroundColor(.primary),
                     at: CGPoint(x: dot.x + 6, y: labelY), anchor: .leading)

            for day in chart.days {
                let isToday = chart.today.contains(day.center)
                ctx.draw(Text(day.name).font(.system(size: 9, weight: isToday ? .bold : .regular))
                            .foregroundColor(isToday ? .primary : .secondary),
                         at: CGPoint(x: plot.minX + day.center * plot.width, y: size.height - 8))
            }
        }
        .frame(height: 88)
    }
}

struct ChartLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            key("so far") { Rectangle().fill(Palette.accent).frame(width: 14, height: 2) }
            key("use-it-all pace") { Line().stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).frame(width: 14, height: 2) }
            key("your pace") { Line().stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [1, 4])).frame(width: 14, height: 2) }
            key("would go unused") { Rectangle().fill(Palette.warn.opacity(0.6)).frame(width: 12, height: 6) }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private func key<S: View>(_ text: String, @ViewBuilder _ swatch: () -> S) -> some View {
        HStack(spacing: 4) { swatch(); Text(text) }
    }
}

struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { $0.move(to: CGPoint(x: rect.minX, y: rect.midY)); $0.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
    }
}
```

`Sources/ClaudeDock/PanelView.swift`:

```swift
import SwiftUI
import ClaudeDockCore

/// The panel that opens above the widget: switch advice, then each org's week in detail.
struct PanelView: View {
    @ObservedObject var model: AppModel
    var actions: WidgetActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("AI usage · week of \(model.formatting.weekStartLabel(WeekAxis(containing: model.now).start))")
                Spacer()
                Text(updatedText)
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)

            if !model.statusLine.isEmpty { statusLine }

            ForEach(Array(model.orgs.enumerated()), id: \.element.id) { index, org in
                Divider().padding(.top, 10)
                OrgSection(model: model, org: org, showLegend: index == 0).padding(.top, 10)
            }

            if !model.signedIn {
                Button("Sign in to claude.ai", action: actions.signInOut).padding(.top, 10)
            }
        }
        .padding(14)
        .frame(width: 372)
        .hud(radius: 14)
    }

    private var updatedText: String {
        guard let last = model.lastUpdated else { return model.signedIn ? "loading…" : "signed out" }
        let time = model.formatting.dayTime(last, now: model.now)
        return model.isStale ? "as of \(time)" : "\(time) · live"
    }

    private var statusLine: some View {
        let switching = model.advice != nil
        return HStack(alignment: .top, spacing: 7) {
            Text(switching ? "⇄" : "✓").foregroundStyle(switching ? Palette.warn : Palette.accent)
            Text(model.statusLine).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(switching ? Palette.warn.opacity(0.16) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct OrgSection: View {
    @ObservedObject var model: AppModel
    let org: Org
    let showLegend: Bool

    var body: some View {
        let reading = model.reading(for: org)
        let forecast = model.forecast(for: org)
        let light = model.light(for: org) ?? .yellow
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(org.name).font(.system(size: 13, weight: .bold))
                StoplightDot(light: light)
                Text(model.role(of: org) == .primary ? "Desktop app + Claude Code" : "Extra Claude Code")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                Spacer()
                if model.claudeCodeOrg == org.id {
                    HStack(spacing: 4) {
                        Circle().fill(Palette.accent).frame(width: 6, height: 6)
                        Text("Claude Code is here")
                    }
                    .font(.system(size: 10))
                }
            }
            if let reading {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(Formatting.percent(reading.week)) used").font(.system(size: 20, weight: .bold))
                    Text(Copy.weekLine(reading, forecast: forecast, now: model.now, formatting: model.formatting))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                WeekChart(
                    chart: WeekChartModel.make(axis: WeekAxis(containing: model.now), now: model.now, reading: reading,
                                               forecast: forecast, history: model.history),
                    red: light == .red,
                    resetLabel: reading.weekResetsAt.map { model.formatting.dayTime($0, now: model.now) })
                if showLegend { ChartLegend() }
                TodayBox(today: Copy.today(reading, forecast: forecast, now: model.now,
                                           formatting: model.formatting, model.settings.thresholds))
                ForEach(reading.scoped.keys.sorted(), id: \.self) { name in
                    let used = reading.scoped[name] ?? 0
                    BarRow(label: name, used: used, tick: forecast?.elapsedFraction,
                           detail: "\(Formatting.percent(used)) used · this week")
                }
                BarRow(label: "5 hours", used: reading.session, tick: reading.sessionElapsedFraction(now: model.now),
                       detail: reading.sessionResetsAt.map {
                           "\(Formatting.percent(reading.session)) used · till \(model.formatting.dayTime($0, now: model.now))"
                       } ?? "not started",
                       off: reading.sessionResetsAt == nil)
            } else {
                Text("No reading yet.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}

private struct TodayBox: View {
    var today: Copy.Today

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            (Text("TODAY  ").font(.system(size: 9.5, weight: .heavy)) + Text(today.main)).font(.system(size: 11.5))
            if let warning = today.warning {
                (Text("▲ ").foregroundColor(Palette.warn) + Text(warning)).font(.system(size: 11))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct BarRow: View {
    var label: String
    var used: Double
    var tick: Double?
    var detail: String
    var off = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            UsageBar(used: used, tick: tick, color: Palette.accent, off: off)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).frame(width: 128, alignment: .trailing)
        }
        .padding(.top, 2)
    }
}
```

- [ ] **Step 5: Windows, the controller, and rendering**

`Sources/ClaudeDock/FloatingPanel.swift`:

```swift
import AppKit

/// A borderless panel that floats on every Space, including over full-screen apps, and
/// never activates the app, so clicking it doesn't take focus from what you're doing.
final class FloatingPanel: NSPanel {
    private let allowsKey: Bool

    init(allowsKey: Bool) {
        self.allowsKey = allowsKey
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovable = false
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }
}
```

`Sources/ClaudeDock/DockController.swift`:

```swift
import AppKit
import Combine
import SwiftUI

/// Owns the two floating windows: the always-on widget and the panel it opens.
@MainActor
final class DockController {
    var onPanelOpened: (() -> Void)?

    private let model: AppModel
    private let widget = FloatingPanel(allowsKey: false)
    private let panel = FloatingPanel(allowsKey: true)
    private var monitors: [Any] = []
    private var changes: AnyCancellable?
    private var hiddenUntil: Date?

    init(model: AppModel, actions: WidgetActions) {
        self.model = model
        widget.contentView = NSHostingView(rootView: WidgetView(model: model, actions: actions))
        panel.contentView = NSHostingView(rootView: PanelView(model: model, actions: actions))
        changes = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.layout() } }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
    }

    func show() {
        hiddenUntil = nil
        layout()
        widget.orderFrontRegardless()
    }

    func hide(for seconds: TimeInterval) {
        closePanel()
        widget.orderOut(nil)
        let until = Date().addingTimeInterval(seconds)
        hiddenUntil = until
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            MainActor.assumeIsolated { if self?.hiddenUntil == until { self?.show() } }
        }
    }

    func togglePanel() { panel.isVisible ? closePanel() : openPanel() }

    func openPanel() {
        guard !panel.isVisible else { return }
        placePanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        onPanelOpened?()
        if let outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closePanel() }
        }) { monitors.append(outside) }
        if let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.closePanel() }
            return nil
        }) { monitors.append(escape) }
    }

    func closePanel() {
        panel.orderOut(nil)
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// Bottom-right corner. With the Dock at the bottom, sit beside it at the same height;
    /// otherwise stay inside the visible frame so a side Dock isn't covered.
    private func layout() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first, let content = widget.contentView else { return }
        let size = content.fittingSize
        let full = screen.frame, visible = screen.visibleFrame
        let dockAtBottom = visible.minY > full.minY + 1
        let origin = NSPoint(x: visible.maxX - size.width - 12, y: dockAtBottom ? full.minY + 6 : visible.minY + 12)
        widget.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.isVisible { placePanel() }
    }

    private func placePanel() {
        guard let content = panel.contentView, let screen = widget.screen ?? NSScreen.main else { return }
        let size = content.fittingSize
        let bottom = widget.frame.maxY + 8
        let height = min(size.height, screen.visibleFrame.maxY - bottom - 8)
        panel.setFrame(NSRect(x: widget.frame.maxX - size.width, y: bottom, width: size.width, height: height), display: true)
    }
}
```

`Sources/ClaudeDock/Renderer.swift`:

```swift
import AppKit
import SwiftUI
import ClaudeDockCore

/// `ClaudeDock --render DIR` draws the widget and panel for every demo scenario, in dark
/// and light, as PNGs. A way to check the UI without screen-recording permission.
@MainActor
enum Renderer {
    static func renderDemo(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fixedNow = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: 11, minute: 32))!
        let settings = Settings(defaults: UserDefaults(suiteName: "ClaudeDockRender")!)
        for scenario in DemoData.scenarios(now: fixedNow) {
            let model = AppModel(settings: settings, store: HistoryStore(url: dir.appendingPathComponent("render-history.jsonl")))
            model.apply(scenario)
            for scheme in [ColorScheme.dark, .light] {
                let suffix = scheme == .dark ? "dark" : "light"
                write(WidgetView(model: model, actions: .none), scheme, dir.appendingPathComponent("\(scenario.name)-widget-\(suffix).png"))
                write(PanelView(model: model, actions: .none), scheme, dir.appendingPathComponent("\(scenario.name)-panel-\(suffix).png"))
            }
        }
        print("Rendered to \(dir.path)")
    }

    private static func write<V: View>(_ view: V, _ scheme: ColorScheme, _ url: URL) {
        let framed = view
            .environment(\.colorScheme, scheme)
            .environment(\.solidBackground, true)
            .padding(12)
            .background(scheme == .dark ? Color(white: 0.25) : Color(white: 0.85))
        let renderer = ImageRenderer(content: framed)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }
}
```

- [ ] **Step 6: Startup (demo mode for now)**

`Sources/ClaudeDock/main.swift`:

```swift
import AppKit
import Foundation

MainActor.assumeIsolated {
    let arguments = CommandLine.arguments
    if let flag = arguments.firstIndex(of: "--render"), flag + 1 < arguments.count {
        Renderer.renderDemo(to: URL(fileURLWithPath: arguments[flag + 1]))
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
```

`Sources/ClaudeDock/AppDelegate.swift` (Task 10 replaces this with the live version):

```swift
import AppKit
import ClaudeDockCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var dock: DockController!
    private var demo: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel(settings: Settings(defaults: .standard), store: HistoryStore(url: HistoryStore.defaultURL))
        dock = DockController(model: model, actions: WidgetActions(
            tap: { [weak self] in self?.dock.togglePanel() },
            hide: { [weak self] in self?.dock.hide(for: 3600) },
            quit: { NSApp.terminate(nil) }))
        dock.show()
        demo = Task { [weak self] in
            var index = 0
            while !Task.isCancelled {
                guard let self else { return }
                let scenarios = DemoData.scenarios()
                self.model.apply(scenarios[index % scenarios.count])
                index += 1
                try? await Task.sleep(for: .seconds(6))
            }
        }
    }
}
```

- [ ] **Step 7: The build script**

`build.sh`:

```bash
#!/bin/bash
# Builds build/Claude Dock.app: a release binary in a minimal bundle, ad-hoc signed.
# Universal (Apple Silicon + Intel) when the toolchain can cross-compile, else native only.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Claude Dock.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

binaries=()
for arch in arm64 x86_64; do
  triple="$arch-apple-macosx14.0"
  if swift build -c release --triple "$triple" --product ClaudeDock; then
    binaries+=("$(swift build -c release --triple "$triple" --show-bin-path)/ClaudeDock")
  elif [ "$arch" = "$(uname -m)" ]; then
    echo "Build failed for $arch" >&2; exit 1
  else
    echo "Skipping $arch (cross-compiling isn't available here)"
  fi
done
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/ClaudeDock"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>ClaudeDock</string>
  <key>CFBundleDisplayName</key><string>Claude Dock</string>
  <key>CFBundleIdentifier</key><string>com.wbuf81.claudedock</string>
  <key>CFBundleExecutable</key><string>ClaudeDock</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>0.1.0</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
```

Run: `chmod +x build.sh`

- [ ] **Step 8: Build, render and look**

Run: `./build.sh`
Expected: ends with `Built build/Claude Dock.app`. Fix any compile errors before going on.

Run (`SCRATCH` = the session scratchpad directory, outside the repo):
`"build/Claude Dock.app/Contents/MacOS/ClaudeDock" --render "$SCRATCH/renders"`
Expected: `Rendered to …` and 20 PNGs. Open `green-and-red-widget-dark.png` and `green-and-red-panel-dark.png` and check against the approved mockups: Pikachu ring at 55% with a tick near 62%, a green dot, `5h: 1% used · 12m in`; Charizard red ring at 95%, a red dot, `back Wed 9 PM · 5h idle`; the panel's status line, Mon–Sun charts with TODAY on Tue, the use-it-all and pace lines, the amber wedge, the TODAY box text from Task 8, and the Fable and 5-hour bars. Check `switch-for-desktop-app-widget-dark.png` shows the `⇄ Charizard first` tab. Nothing overlaps or is cut off.

Run: `./test.sh`
Expected: all core tests still pass.

Run: `open "build/Claude Dock.app"`
Expected: the widget appears in the bottom-right corner beside the Dock and cycles through demo scenarios every 6 seconds; clicking it opens the panel above it; clicking elsewhere or pressing Esc closes it. Then quit with `pkill -x ClaudeDock`.

- [ ] **Step 9: Commit**

```bash
git add Package.swift build.sh Sources
git commit -m "Add the widget and panel app with demo data and renders" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Live data, sign-in, notifications and settings

Deliverable: launching the app asks for a claude.ai sign-in once, then shows live usage for the owner's orgs, refreshing every 3 minutes, with notifications, a Settings window and launch at login.

**Files:**
- Create: `Sources/ClaudeDock/ClaudeWebSession.swift`, `Sources/ClaudeDock/Poller.swift`, `Sources/ClaudeDock/Notifier.swift`, `Sources/ClaudeDock/SettingsView.swift`
- Modify: `Sources/ClaudeDock/AppDelegate.swift` (replace)

**Interfaces:**
- Consumes: `AppModel`, `Settings`, `DockController`, `WidgetActions`, `DemoData`, `UsageParser`, `ClaudeCodeAccount`.
- Produces: `ClaudeWebSession` (`getJSON(_:) async throws -> Data`, `showSignIn()`, `signOut() async`, `onSignedIn`); `WebSessionError { signedOut, badResult, http(Int) }`; `Poller(model:session:account:)` (`start(immediately:)`, `stop()`, `refresh() async`); `Notifier` (`requestPermission()`, `post(_:_:)`, `onClick`); `SettingsView`.

- [ ] **Step 1: The claude.ai session**

`Sources/ClaudeDock/ClaudeWebSession.swift`:

```swift
import AppKit
import WebKit

enum WebSessionError: Error {
    case signedOut
    case badResult
    case http(Int)
}

/// The app's own claude.ai session, kept in the app's website data store (separate from
/// Safari, Chrome and the Claude desktop app). Requests run as fetch() inside a hidden
/// claude.ai page, so they carry the session cookie and look like the site's own requests.
/// Only GET requests are ever made.
@MainActor
final class ClaudeWebSession: NSObject, WKNavigationDelegate {
    var onSignedIn: (() -> Void)?

    private static let home = URL(string: "https://claude.ai/settings/usage")!
    private static let login = URL(string: "https://claude.ai/login")!

    private let dataStore = WKWebsiteDataStore.default()
    private lazy var fetcher = makeWebView()
    private var fetcherReady = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var signInWindow: NSWindow?
    private var signInView: WKWebView?

    /// GETs a claude.ai API path and returns the response body.
    func getJSON(_ path: String) async throws -> Data {
        await loadFetcher()
        let script = """
        const r = await fetch(path, { credentials: 'include', headers: { accept: 'application/json' } });
        return { status: r.status, body: await r.text() };
        """
        let value = try await fetcher.callAsyncJavaScript(script, arguments: ["path": path], in: nil, contentWorld: .page)
        guard let result = value as? [String: Any],
              let status = (result["status"] as? NSNumber)?.intValue,
              let body = result["body"] as? String else { throw WebSessionError.badResult }
        if status == 401 || status == 403 { throw WebSessionError.signedOut }
        guard status == 200 else { throw WebSessionError.http(status) }
        return Data(body.utf8)
    }

    func showSignIn() {
        if let window = signInWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let size = NSSize(width: 520, height: 720)
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        let hint = NSTextField(wrappingLabelWithString: "Sign in to claude.ai once. Claude Dock only reads your usage. If Google sign-in is blocked here, use “Continue with email”.")
        hint.font = .systemFont(ofSize: 12)
        hint.frame = NSRect(x: 12, y: size.height - 46, width: size.width - 24, height: 38)
        hint.autoresizingMask = [.width, .minYMargin]
        let view = makeWebView()
        view.frame = NSRect(x: 0, y: 0, width: size.width, height: size.height - 52)
        view.autoresizingMask = [.width, .height]
        container.addSubview(hint)
        container.addSubview(view)
        view.load(URLRequest(url: Self.login))

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Sign in to claude.ai"
        window.contentView = container
        window.isReleasedWhenClosed = false
        window.center()
        signInWindow = window
        signInView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        watchForSignIn()
    }

    /// Deletes this app's claude.ai cookies and storage.
    func signOut() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await dataStore.dataRecords(ofTypes: types)
        await dataStore.removeData(ofTypes: types, for: records.filter { $0.displayName.contains("claude.ai") })
        fetcherReady = false
    }

    // MARK: Private

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        config.applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 640), configuration: config)
        view.navigationDelegate = self
        return view
    }

    private func loadFetcher() async {
        guard !fetcherReady else { return }
        fetcher.load(URLRequest(url: Self.home))
        await withCheckedContinuation { waiters.append($0) }
    }

    /// The sign-in page is a web app that may not fire navigation events when it finishes,
    /// so poll for a working session every 2 seconds while the window is open.
    private func watchForSignIn() {
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(2))
                guard let self, let window = self.signInWindow, window.isVisible else {
                    self?.signInWindow = nil
                    self?.signInView = nil
                    return
                }
                if (try? await self.getJSON("/api/organizations")) != nil {
                    window.close()
                    self.signInWindow = nil
                    self.signInView = nil
                    self.onSignedIn?()
                    return
                }
            }
        }
    }

    private func finished(_ webView: WKWebView, ok: Bool) {
        guard webView === fetcher else { return }
        fetcherReady = ok
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished(webView, ok: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finished(webView, ok: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finished(webView, ok: false)
    }
}
```

- [ ] **Step 2: The poller**

`Sources/ClaudeDock/Poller.swift`:

```swift
import Foundation
import ClaudeDockCore

/// Reads claude.ai every 3 minutes (backing off on errors) and watches which org Claude
/// Code is signed into.
@MainActor
final class Poller {
    private let model: AppModel
    private let session: ClaudeWebSession
    private let account: ClaudeCodeAccount
    private var loop: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private var failures = 0
    private var orgsFetchedAt: Date?
    private var accountModified: Date?
    private let delays: [TimeInterval] = [180, 360, 720, 900]

    init(model: AppModel, session: ClaudeWebSession, account: ClaudeCodeAccount) {
        self.model = model
        self.session = session
        self.account = account
    }

    /// Starts or restarts polling. With `immediately: false` the first refresh waits one interval.
    func start(immediately: Bool = true) {
        loop?.cancel()
        loop = Task { [weak self] in
            var refreshNow = immediately
            while !Task.isCancelled {
                guard let self else { return }
                if refreshNow { await self.refresh() }
                refreshNow = true
                try? await Task.sleep(for: .seconds(self.delays[min(self.failures, self.delays.count - 1)]))
            }
        }
        if watcher == nil {
            watcher = Task { [weak self] in
                while !Task.isCancelled {
                    self?.checkAccount()
                    try? await Task.sleep(for: .seconds(10))
                }
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    func refresh() async {
        guard !model.settings.demoMode else { return }
        do {
            if model.orgs.isEmpty || (orgsFetchedAt.map { Date().timeIntervalSince($0) > 86_400 } ?? true) {
                let all = try UsageParser.orgs(from: try await session.getJSON("/api/organizations"))
                model.setAvailableOrgs(all, claudeCodeOrg: account.currentOrg())
                orgsFetchedAt = Date()
            }
            let now = Date()
            var readings: [Reading] = []
            for org in model.orgs {
                let data = try await session.getJSON("/api/organizations/\(org.id)/usage")
                readings.append(try UsageParser.reading(from: data, org: org.id, at: now))
            }
            model.ingest(readings, claudeCodeOrg: account.currentOrg(), at: now)
            failures = 0
        } catch WebSessionError.signedOut {
            model.signedIn = false
        } catch {
            failures += 1
            model.lastError = String(describing: error)
        }
    }

    private func checkAccount() {
        let modified = account.modified()
        guard modified != accountModified else { return }
        accountModified = modified
        model.setClaudeCodeOrg(account.currentOrg())
    }
}
```

- [ ] **Step 3: Notifications**

`Sources/ClaudeDock/Notifier.swift`:

```swift
import Foundation
import UserNotifications

/// Mac notifications for switch advice and for Claude Code's org turning red. Only works
/// from the bundled app (an unbundled binary has no notification identity).
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    var onClick: (() -> Void)?

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func requestPermission() {
        center?.delegate = self
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center?.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run { onClick?() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}
```

- [ ] **Step 4: Settings window**

`Sources/ClaudeDock/SettingsView.swift`:

```swift
import ServiceManagement
import SwiftUI
import ClaudeDockCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    var setDemoMode: (Bool) -> Void
    var signInOut: () -> Void
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Organizations") {
                ForEach(settings.knownOrgs) { org in
                    Toggle(org.name, isOn: Binding(get: { settings.isShown(org) }, set: { show(org, $0) }))
                }
                Picker("Shared with the desktop app", selection: Binding(
                    get: { settings.primaryOrg ?? "" },
                    set: { settings.primaryOrg = $0; refreshOrgs() })) {
                    ForEach(settings.knownOrgs.filter { settings.isShown($0) }) { Text($0.name).tag($0.id) }
                }
            }
            Section("Notifications") {
                Toggle("When Claude Code should switch orgs", isOn: $settings.notifySwitch)
                Toggle("When Claude Code's org turns red", isOn: $settings.notifyRed)
            }
            Section("Thresholds") {
                threshold("Red when week left is under", \.redWeekLeft, "%")
                threshold("Red when running out this early", \.redRunsOutEarlyHours, "h")
                threshold("Red when the 5-hour window reaches", \.redSession, "%")
                threshold("Yellow when the 5-hour window reaches", \.yellowSession, "%")
                threshold("On pace when unused is under", \.onPaceUnused, "%")
                threshold("Normal pulse from unused", \.normalPulseUnused, "%")
                threshold("Fast pulse above unused", \.fastPulseUnused, "%")
                threshold("Suggest an org with week left of", \.eligibleWeekLeft, "%")
                threshold("…and its 5-hour window under", \.eligibleSessionBelow, "%")
                threshold("Desktop app buffer (week left)", \.primaryReserveWeekLeft, "%")
                Button("Reset to defaults") { settings.thresholds = Thresholds() }
            }
            Section("App") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                    }
                Toggle("Demo mode (Pokémon sample data)", isOn: Binding(get: { settings.demoMode }, set: setDemoMode))
                Button(model.signedIn ? "Sign out of claude.ai" : "Sign in to claude.ai", action: signInOut)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 640)
    }

    private func show(_ org: Org, _ on: Bool) {
        var ids = Set(settings.knownOrgs.filter { settings.isShown($0) }.map(\.id))
        if on { ids.insert(org.id) } else { ids.remove(org.id) }
        settings.shownOrgs = Array(ids)
        refreshOrgs()
    }

    private func refreshOrgs() {
        model.setAvailableOrgs(settings.knownOrgs, claudeCodeOrg: model.claudeCodeOrg)
    }

    private func threshold(_ label: String, _ key: WritableKeyPath<Thresholds, Double>, _ unit: String) -> some View {
        Stepper(value: Binding(get: { settings.thresholds[keyPath: key] },
                               set: { settings.thresholds[keyPath: key] = $0 }), in: 0...100, step: 1) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Int(settings.thresholds[keyPath: key]))\(unit)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }
}
```

- [ ] **Step 5: Wire it all up**

Replace `Sources/ClaudeDock/AppDelegate.swift` with:

```swift
import AppKit
import ServiceManagement
import SwiftUI
import ClaudeDockCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var dock: DockController!
    private var poller: Poller!
    private let session = ClaudeWebSession()
    private let notifier = Notifier()
    private var settingsWindow: NSWindow?
    private var demo: Task<Void, Never>?
    private var clock: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = Settings(defaults: .standard)
        model = AppModel(settings: settings, store: HistoryStore(url: HistoryStore.defaultURL))
        poller = Poller(model: model, session: session, account: ClaudeCodeAccount())
        dock = DockController(model: model, actions: WidgetActions(
            tap: { [weak self] in self?.dock.togglePanel() },
            refresh: { [weak self] in Task { await self?.poller.refresh() } },
            hide: { [weak self] in self?.dock.hide(for: 3600) },
            settings: { [weak self] in self?.showSettings() },
            signInOut: { [weak self] in self?.signInOrOut() },
            quit: { NSApp.terminate(nil) }))

        dock.onPanelOpened = { [weak self] in
            guard let self, !self.model.settings.demoMode else { return }
            if self.model.lastUpdated.map({ Date().timeIntervalSince($0) > 30 }) ?? true {
                Task { await self.poller.refresh() }
            }
        }
        session.onSignedIn = { [weak self] in self?.poller.start() }
        notifier.onClick = { [weak self] in self?.dock.openPanel() }
        notifier.requestPermission()
        model.onAdvice = { [weak self] advice in
            guard let self, self.model.settings.notifySwitch else { return }
            self.notifier.post("Move Claude Code to \(advice.target.name)", advice.reason)
        }
        model.onRed = { [weak self] org in
            guard let self, self.model.settings.notifyRed else { return }
            self.notifier.post("\(org.name) is nearly out", "Claude Code is signed into \(org.name), which just turned red.")
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.settings.demoMode else { return }
                self.poller.start()
            }
        }
        clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.settings.demoMode else { return }
                self.model.tick()
            }
        }

        registerLoginItemOnce()
        dock.show()
        if settings.demoMode {
            startDemo()
        } else {
            Task {
                await poller.refresh()
                if !model.signedIn { session.showSignIn() }
                poller.start(immediately: false)
            }
        }
    }

    private func signInOrOut() {
        if model.signedIn {
            Task {
                await session.signOut()
                model.signedIn = false
            }
        } else {
            session.showSignIn()
        }
    }

    private func setDemoMode(_ on: Bool) {
        model.settings.demoMode = on
        if on {
            poller.stop()
            startDemo()
        } else {
            demo?.cancel()
            model.leaveDemo()
            poller.start()
        }
    }

    private func startDemo() {
        demo?.cancel()
        demo = Task { [weak self] in
            var index = 0
            while !Task.isCancelled {
                guard let self else { return }
                let scenarios = DemoData.scenarios()
                self.model.apply(scenarios[index % scenarios.count])
                index += 1
                try? await Task.sleep(for: .seconds(6))
            }
        }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(model: model, settings: model.settings,
                                    setDemoMode: { [weak self] in self?.setDemoMode($0) },
                                    signInOut: { [weak self] in self?.signInOrOut() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Claude Dock Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The spec has Claude Dock launch at login; register once, then leave it to Settings.
    private func registerLoginItemOnce() {
        guard Bundle.main.bundleIdentifier != nil, !UserDefaults.standard.bool(forKey: "loginItemOffered") else { return }
        UserDefaults.standard.set(true, forKey: "loginItemOffered")
        try? SMAppService.mainApp.register()
    }
}
```

- [ ] **Step 6: Build and run against claude.ai**

Run: `./build.sh && ./test.sh`
Expected: `Built build/Claude Dock.app` and all tests pass.

Run: `pkill -x ClaudeDock; open "build/Claude Dock.app"`
Expected: a "Sign in to claude.ai" window opens. The owner signs in (this step needs them). Within a few seconds the window closes and the widget shows the owner's real orgs, primary first, with numbers matching claude.ai's usage page and the same stoplight colors as the design. The panel's top line says which org Claude Code is on. Right-click shows the menu; Settings opens; toggling demo mode switches to Pokémon data and back.

Check the session is the app's own: `ls ~/Library/WebKit/com.wbuf81.claudedock` exists, and nothing new appears in the repo (`git status` is clean apart from tracked changes).

- [ ] **Step 7: Commit**

```bash
git add Sources
git commit -m "Read live usage from claude.ai with sign-in, notifications and settings" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: End-to-end check and publish

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Behaviour checks with the app running live**

With the app running and signed in:
1. Leave it for 4 minutes: the panel's header time advances (a new reading every 3 minutes).
2. Turn Wi-Fi off for 12 minutes: the widget greys out and the panel shows `as of <time>`; turn Wi-Fi on: it recovers within one backoff interval.
3. Run `/login` in Claude Code to switch orgs: within 10 seconds "Claude Code is here" moves to the other org.
4. Sign out from the right-click menu: the widget says "Sign in to claude.ai"; sign in again from the panel button.
5. Hide for 1 hour from the menu, then quit and relaunch to bring it back.

- [ ] **Step 2: Update the README**

In `README.md`, replace the line `Status: in design. The spec lives in \`docs/superpowers/specs/\`.` with:

```markdown
## Build and run

Needs macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh                      # builds build/Claude Dock.app
open "build/Claude Dock.app"    # first launch asks you to sign in to claude.ai once
./test.sh                       # unit tests
```

Claude Dock signs in to claude.ai in its own private web view and only reads your usage
(GET requests to claude.ai's usage endpoints, every 3 minutes). It reads one field from
`~/.claude.json` to see which org Claude Code is signed into. History stays in
`~/Library/Application Support/ClaudeDock/`. These endpoints are not a public API and may
change.

Settings has a demo mode with Pokémon sample data (Pikachu and Charizard), and
`"build/Claude Dock.app/Contents/MacOS/ClaudeDock" --render DIR` draws every demo state to
PNGs.

The design spec and implementation plan live in `docs/superpowers/`.
```

- [ ] **Step 3: Audit, commit and push**

Run: `.githooks/scan-sensitive.sh --all`
Expected: no findings.

```bash
git add README.md
git commit -m "Document building and running Claude Dock" -m "Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
git push
```

Expected: the pre-push scan passes and the push succeeds.
