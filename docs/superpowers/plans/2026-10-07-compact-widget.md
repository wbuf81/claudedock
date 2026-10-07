# Compact Widget and In-Use Particles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the widget shrink to rings, names and 5-hour lines until hovered, and show particles on an org that's in use right now instead of a pulsing dot.

**Architecture:** The pure rules (where the full widget grows to, whether an org is in use, the effect enums, a Claude Code activity watcher) live in `ClaudeDockCore` with Swift Testing tests. The app's widget window holds two SwiftUI hosting views (compact and full) pinned to the corner it grows from; AppKit animates the window frame while the views crossfade. Particles are Core Animation layers in an `NSViewRepresentable`, like the old pulse ring, with a SwiftUI glow for Reduce Motion and image renders.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, SwiftUI + AppKit, Core Animation (`CAEmitterLayer`, `CAReplicatorLayer`, keyframe animations), FSEvents (CoreServices), Swift Testing. No dependencies.

**Spec:** `docs/superpowers/specs/2026-10-07-compact-widget-design.md`

## Global Constraints

- macOS 14 or later; builds with the Command Line Tools alone. `./test.sh` runs the tests, `./build.sh` builds `build/Claude Dock.app`.
- No `@State` in new SwiftUI code: the macOS 27 SDK makes it a macro the Command Line Tools can't expand (see `SettingsView.swift`).
- No SwiftUI animations that re-lay out the widget every frame (that cost ~5% CPU all day before). Motion is Core Animation or `NSAnimationContext`.
- The repo is public: never commit org names, employer, emails or real org IDs. Examples use Pokémon (Pikachu = primary, Charizard = overflow). A pre-commit hook checks `.git/info/sensitive-patterns`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Timings from the spec: grow after the pointer rests **0.25 s**, shrink **0.4 s** after it leaves, frame animation **0.22 s** ease-out, Reduce Motion crossfade **0.2 s**. Claude Code counts as working for **60 s** after a transcript write; a usage rise counts for **4 minutes**; the previous reading must be at most **10 minutes** older; reset times within **60 s** are the same window.
- Compact geometry at content scale `k`: ring **44k**, dot **9k**, name **10k pt** semibold (at least 9 pt), name width **54k**, line **46k × 4k**, column **56k**, column spacing **6k**, padding **10k**, badge **26k** wide (horizontal) or **24k** tall (vertical), vertical strip **68k** wide.
- Defaults: Shrink until hovered **on**; In-use effect **Flow**, amount **Normal** (multipliers 0.5 / 1 / 1.8).

## Review Focus

These are what a person using the app will hit that no unit test exercises. Each one has a check in the task that owns the code.

1. **Hovering in and out fast, or leaving mid-growth**: the widget must end compact whenever the pointer is off it (and the panel is closed), never stuck open or flickering. Check: Task 5, Step 8.
2. **Starting a drag while the widget is growing or full**: the drag moves the compact widget with no jump, and it ends compact where dropped. Check: Task 5, Step 8.
3. **Turning Shrink until hovered off or on while expanded or with the panel open**: the right widget, in the right place, at the floating level. Check: Task 5, Step 8.
4. **Long names, three orgs, an org with no reading, the switch badge, in compact**: names are cut off with "…", nothing overflows, every column lines up. Check: Task 4, Step 6.
5. **No `~/.claude/projects` (Claude Code never used), or Claude Code writing constantly**: no crash; the widget redraws only when an org starts or stops being in use, not on every write. Check: Task 7, Steps 1 and 7.

---

### Task 1: Where the full widget grows to

**Files:**
- Modify: `Sources/ClaudeDockCore/Placement.swift` (add `GrowthAnchor`; add `anchor` and `expandedFrame` to `WidgetPlacement`)
- Test: `Tests/ClaudeDockCoreTests/PlacementTests.swift` (new `GrowthTests` suite), `Tests/ClaudeDockCoreTests/MatrixTests.swift`

**Interfaces:**
- Produces:
  - `public struct GrowthAnchor: Equatable, Sendable { enum Horizontal { left, right }; enum Vertical { bottom, top, center }; var horizontal; var vertical; init(_ horizontal:, _ vertical:) }`
  - `WidgetPlacement.anchor(compact: CGRect, visible: CGRect, spot: WidgetSpot?) -> GrowthAnchor`
  - `WidgetPlacement.expandedFrame(compact: CGRect, size: CGSize, anchor: GrowthAnchor, screen: CGRect, visible: CGRect) -> CGRect`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/ClaudeDockCoreTests/PlacementTests.swift`:

```swift
/// The compact widget grows to the full one toward the middle of the screen.
@Suite struct GrowthTests {
    let full = CGSize(width: 497, height: 82)

    func anchor(_ frame: CGRect, _ spot: WidgetSpot? = nil) -> GrowthAnchor {
        WidgetPlacement.anchor(compact: frame, visible: visibleWithDock, spot: spot)
    }

    func grown(_ compact: CGRect, _ size: CGSize, _ spot: WidgetSpot? = nil, visible: CGRect = visibleWithDock) -> CGRect {
        WidgetPlacement.expandedFrame(compact: compact, size: size,
                                      anchor: WidgetPlacement.anchor(compact: compact, visible: visible, spot: spot),
                                      screen: screen, visible: visible)
    }

    @Test func growsTowardTheMiddleOfTheScreen() {
        #expect(anchor(CGRect(x: 2398, y: 6, width: 150, height: 82)) == GrowthAnchor(.right, .bottom))
        #expect(anchor(CGRect(x: 12, y: 6, width: 150, height: 82)) == GrowthAnchor(.left, .bottom))
        #expect(anchor(CGRect(x: 2398, y: 1346, width: 150, height: 82)) == GrowthAnchor(.right, .top))
        #expect(anchor(CGRect(x: 12, y: 1346, width: 150, height: 82)) == GrowthAnchor(.left, .top))
        #expect(anchor(CGRect(x: 900, y: 300, width: 150, height: 82), .free(WidgetOffset(right: 1510, bottom: 300)))
                == GrowthAnchor(.left, .bottom))
    }

    @Test func sideStripsGrowFromTheirMiddle() {
        let strip = CGRect(x: 2486, y: 685, width: 68, height: 160)
        #expect(anchor(strip, .snapped(.rightMiddle)) == GrowthAnchor(.right, .center))
        #expect(anchor(CGRect(x: 6, y: 685, width: 68, height: 160), .snapped(.leftMiddle)) == GrowthAnchor(.left, .center))
        #expect(grown(strip, CGSize(width: 104, height: 300), .snapped(.rightMiddle))
                == CGRect(x: 2450, y: 615, width: 104, height: 300))
    }

    @Test func keepsTheAnchoredEdgesInPlace() {
        #expect(grown(CGRect(x: 2398, y: 6, width: 150, height: 82), full) == CGRect(x: 2051, y: 6, width: 497, height: 82))
        #expect(grown(CGRect(x: 12, y: 1346, width: 150, height: 82), full) == CGRect(x: 12, y: 1346, width: 497, height: 82))
        // A vertical strip in a bottom corner grows up from its bottom edge.
        #expect(grown(CGRect(x: 12, y: 6, width: 68, height: 160), CGSize(width: 104, height: 300))
                == CGRect(x: 12, y: 6, width: 104, height: 300))
    }

    @Test func staysOnScreenAndBelowTheMenuBar() {
        let withMenuBar = CGRect(x: 0, y: 90, width: 2560, height: 1325)
        // A strip centred near the top would reach under the menu bar: it moves down.
        let high = CGRect(x: 2486, y: 1200, width: 68, height: 160)
        let frame = grown(high, CGSize(width: 104, height: 300), .snapped(.rightMiddle), visible: withMenuBar)
        #expect(frame == CGRect(x: 2450, y: 1115, width: 104, height: 300))
        #expect(frame.contains(high))
        // One centred near the bottom would go below the screen: it moves up.
        let low = CGRect(x: 2486, y: 10, width: 68, height: 160)
        #expect(grown(low, CGSize(width: 104, height: 300), .snapped(.rightMiddle)).minY == 0)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `./test.sh --filter GrowthTests`
Expected: build failure, `cannot find 'GrowthAnchor' in scope`.

- [ ] **Step 3: Implement**

In `Sources/ClaudeDockCore/Placement.swift`, add after `enum LayoutChoice`:

```swift
/// The edges that stay put when the compact widget grows to its full size.
public struct GrowthAnchor: Equatable, Sendable {
    public enum Horizontal: Sendable { case left, right }
    public enum Vertical: Sendable { case bottom, top, center }

    public var horizontal: Horizontal
    public var vertical: Vertical

    public init(_ horizontal: Horizontal, _ vertical: Vertical) {
        self.horizontal = horizontal
        self.vertical = vertical
    }
}
```

and inside `public enum WidgetPlacement`, after `offset(origin:size:screen:)`:

```swift
    /// The compact widget grows toward the middle of the screen, so the part under the
    /// pointer stays under it: from its right edge in the right half and its left edge in
    /// the left half, from its bottom edge in the lower half and its top edge in the upper
    /// half. A strip snapped to the middle of a side grows from its vertical centre.
    public static func anchor(compact: CGRect, visible: CGRect, spot: WidgetSpot?) -> GrowthAnchor {
        let horizontal: GrowthAnchor.Horizontal = compact.midX >= visible.midX ? .right : .left
        if case .snapped(let point)? = spot, point == .rightMiddle || point == .leftMiddle {
            return GrowthAnchor(horizontal, .center)
        }
        return GrowthAnchor(horizontal, compact.midY < visible.midY ? .bottom : .top)
    }

    /// The full widget's frame: `size` grown out of the compact frame from its anchored
    /// edges, then kept inside the visible frame across, and between the bottom of the
    /// screen and the menu bar. It may cover a bottom Dock: while expanded it floats above it.
    public static func expandedFrame(compact: CGRect, size: CGSize, anchor: GrowthAnchor,
                                     screen: CGRect, visible: CGRect) -> CGRect {
        let x = anchor.horizontal == .right ? compact.maxX - size.width : compact.minX
        let y: Double
        switch anchor.vertical {
        case .bottom: y = compact.minY
        case .top: y = compact.maxY - size.height
        case .center: y = compact.midY - size.height / 2
        }
        return CGRect(x: min(max(x, visible.minX), visible.maxX - size.width),
                      y: min(max(y, screen.minY), visible.maxY - size.height),
                      width: size.width, height: size.height)
    }
```

- [ ] **Step 4: Run them to verify they pass**

Run: `./test.sh --filter GrowthTests`
Expected: `Suite GrowthTests passed`, 4 tests.

- [ ] **Step 5: Sweep compact and expanded through the placement matrix**

In `Tests/ClaudeDockCoreTests/MatrixTests.swift`, add after `widgetSize(...)`:

```swift
    /// The compact widget's size, mirroring WidgetView's compact layout: 56 pt columns 6 pt
    /// apart inside 10 pt of padding plus a 26 pt switch badge, as tall as the Dock bar; or a
    /// 68 pt strip of 66 pt columns 6 pt apart inside 10 pt of padding plus a 24 pt badge.
    static func compactSize(orgs: Int, vertical: Bool, screen: CGRect, visible: CGRect, tile: Double, scale: Double) -> CGSize {
        let k = DockFit.contentScale(screen: screen, visible: visible, tileSize: tile) * scale
        let n = Double(orgs)
        if vertical { return CGSize(width: 68 * k, height: (n * 66 + (n - 1) * 6 + 20 + 24) * k) }
        let height = DockFit.height(screen: screen, visible: visible, tileSize: tile) * scale
        return CGSize(width: (n * 56 + (n - 1) * 6 + 20 + 26) * k, height: height)
    }
```

Then replace the body of the innermost `for wanted in Self.sizeScales { ... }` loop with:

```swift
                            for wanted in Self.sizeScales {
                                for compact in [false, true] {
                                let natural = Self.widgetSize(orgs: orgs, vertical: vertical, screen: screen,
                                                              visible: visible, tile: tile, scale: 1)
                                let scale = WidgetLayout.fittedScale(wanted, natural: natural, visible: visible)
                                let full = Self.widgetSize(orgs: orgs, vertical: vertical, screen: screen,
                                                           visible: visible, tile: tile, scale: scale)
                                let size = compact
                                    ? Self.compactSize(orgs: orgs, vertical: vertical, screen: screen, visible: visible, tile: tile, scale: scale)
                                    : full
                                let origin = WidgetPlacement.origin(size: size, screen: screen, visible: visible, spot: spot,
                                                                    dockWidth: dockWidth)
                                let widget = CGRect(origin: origin, size: size)
                                let label = "\(display.name), Dock \(side) \(Int(tile)) pt with \(items) items, \(orgs) org(s), \(spot.map { "\($0)" } ?? "default"), size \(wanted), \(compact ? "compact" : "full")"

                                if widget.minX < visible.minX - 0.5 || widget.maxX > visible.maxX + 0.5 {
                                    problems.append("\(label): widget under a side Dock or off screen \(widget)")
                                }
                                if widget.maxY > visible.maxY + 0.5 { problems.append("\(label): widget under the menu bar \(widget)") }
                                if widget.minY < screen.minY - 0.5 { problems.append("\(label): widget below the screen \(widget)") }
                                if let dock, widget.insetBy(dx: 1, dy: 1).intersects(dock) {
                                    problems.append("\(label): widget under the Dock \(widget) vs \(dock)")
                                }

                                // Compact mode: the full widget grown out of it may cover the Dock (it floats
                                // above it), but must stay on screen, below the menu bar, and over the compact one.
                                let shown = compact
                                    ? WidgetPlacement.expandedFrame(compact: widget, size: full,
                                                                    anchor: WidgetPlacement.anchor(compact: widget, visible: visible, spot: spot),
                                                                    screen: screen, visible: visible)
                                    : widget
                                if compact {
                                    if shown.minX < visible.minX - 0.5 || shown.maxX > visible.maxX + 0.5
                                        || shown.minY < screen.minY - 0.5 || shown.maxY > visible.maxY + 0.5 {
                                        problems.append("\(label): expanded widget off screen or under the menu bar \(shown)")
                                    }
                                    if !shown.insetBy(dx: -0.5, dy: -0.5).contains(widget) {
                                        problems.append("\(label): expanded widget doesn't cover the compact one \(shown) vs \(widget)")
                                    }
                                }

                                let panel = WidgetPlacement.panelFrame(panel: Self.panelSize(orgs: orgs), widget: shown, visible: visible)
                                if panel.minX < visible.minX + 7.5 || panel.maxX > visible.maxX - 7.5
                                    || panel.minY < visible.minY + 7.5 || panel.maxY > visible.maxY - 7.5 {
                                    problems.append("\(label): panel off screen \(panel)")
                                }
                                if panel.insetBy(dx: 1, dy: 1).intersects(shown) {
                                    problems.append("\(label): panel covers the widget \(panel) vs \(shown)")
                                }
                                if panel.height < 240 { problems.append("\(label): panel squeezed to \(Int(panel.height)) pt") }
                                }
                            }
```

Also update the suite's doc comment to mention compact: `/// ...a panel off screen or on top of the widget, in full and compact mode (with the full widget grown out of the compact one).`

- [ ] **Step 6: Run the whole suite**

Run: `./test.sh`
Expected: all tests pass (137 before this task, 141 now). If `everyCombinationStaysOnScreenAndClear` reports problems, read the printed example: a problem with the compact widget itself means `compactSize` doesn't match the layout in the spec's Global Constraints; a problem with the expanded frame means `expandedFrame`'s clamping is wrong. Fix the code, not the assertion.

- [ ] **Step 7: Commit**

```bash
git add Sources/ClaudeDockCore/Placement.swift Tests/ClaudeDockCoreTests/PlacementTests.swift Tests/ClaudeDockCoreTests/MatrixTests.swift
git commit -m "Grow the full widget out of the compact one, toward the middle of the screen

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: A steady stoplight dot

**Files:**
- Modify: `Sources/ClaudeDockCore/Stoplight.swift`
- Modify: `Sources/ClaudeDock/Components.swift` (`StoplightDot`; delete `PulseRing`)
- Modify: `Sources/ClaudeDock/SettingsView.swift:38-39` (delete the two pulse rows)
- Modify: `Sources/ClaudeDock/Showcase.swift` (`captions[0]` and `captions[4]`)
- Test: `Tests/ClaudeDockCoreTests/StoplightTests.swift`

**Interfaces:**
- Produces: `public enum Light: Equatable, Sendable { case green, yellow, red }` (no associated value). `Pulse` and `Thresholds.normalPulseUnused` / `fastPulseUnused` no longer exist.

- [ ] **Step 1: Update the tests first**

In `Tests/ClaudeDockCoreTests/StoplightTests.swift`, replace `greenPulseBuckets`, `weekNotStartedIsSteadyGreen` and `defaultsMatchTheSpec` with:

```swift
    @Test func greenWhenTokensWouldGoUnused() {
        #expect(light(unused: 5) == .green)
        #expect(light(unused: 25.1) == .green)
    }

    // Review Focus 1
    @Test func weekNotStartedIsGreen() {
        #expect(Stoplight.light(reading(week: 0, weekResetsAt: nil), nil) == .green)
        #expect(Stoplight.light(reading(week: 0, weekResetsAt: nil, session: 85), nil) == .yellow)
    }

    @Test func defaultsMatchTheSpec() {
        let t = Thresholds()
        #expect([t.redWeekLeft, t.redRunsOutEarlyHours, t.redSession, t.yellowSession, t.onPaceUnused,
                 t.eligibleWeekLeft, t.eligibleSessionBelow, t.primaryReserveWeekLeft] == [10, 12, 95, 80, 5, 10, 80, 15])
    }

    // Settings saved before the dot stopped pulsing still hold the two pulse thresholds.
    @Test func thresholdsSavedWithPulseFieldsStillLoad() throws {
        let saved = #"{"redWeekLeft":20,"redRunsOutEarlyHours":12,"redSession":95,"yellowSession":80,"onPaceUnused":5,"normalPulseUnused":10,"fastPulseUnused":25,"eligibleWeekLeft":10,"eligibleSessionBelow":80,"primaryReserveWeekLeft":15}"#
        let t = try JSONDecoder().decode(Thresholds.self, from: Data(saved.utf8))
        #expect(t.redWeekLeft == 20 && t.primaryReserveWeekLeft == 15)
    }
```

- [ ] **Step 2: Run to verify they fail**

Run: `./test.sh --filter StoplightTests`
Expected: build failure: `.green` used without its associated value (`member 'green' expects argument of type 'Pulse?'`).

- [ ] **Step 3: Implement in Core**

Replace the top of `Sources/ClaudeDockCore/Stoplight.swift` (everything above `public enum Stoplight`) with:

```swift
import Foundation

/// "Should I be using this org right now?" Green (tokens would go unused), yellow (on
/// pace) or red (nearly out).
public enum Light: Equatable, Sendable {
    case green
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
    public var eligibleWeekLeft = 10.0
    public var eligibleSessionBelow = 80.0
    public var primaryReserveWeekLeft = 15.0

    public init() {}
}
```

and in `Stoplight.light`, replace `.green(nil)` with `.green`, and replace the last three lines (`fastPulseUnused`, `normalPulseUnused`, `.green(.slow)`) with `return .green`.

- [ ] **Step 4: Update the app**

In `Sources/ClaudeDock/Components.swift`, replace `StoplightDot` and delete the whole `PulseRing` struct (and its doc comment) below it:

```swift
/// The stoplight dot. Steady: an org that's in use gets particles instead (`InUseEffect`).
struct StoplightDot: View {
    var light: Light
    var size: CGFloat = 9

    var body: some View {
        Circle().fill(Palette.color(for: light)).frame(width: size, height: size)
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
```

In `Sources/ClaudeDock/SettingsView.swift`, delete these two lines:

```swift
                threshold("Normal pulse from unused", \.normalPulseUnused, "%")
                threshold("Fast pulse above unused", \.fastPulseUnused, "%")
```

In `Sources/ClaudeDock/Showcase.swift`, change `captions[0]` to `"Pikachu is green: tokens would go unused. Charizard is nearly out."` and `captions[4]` to `"Pikachu is on pace (yellow) but down to its last 12%, so Charizard, whose week hasn't started, goes first."`

- [ ] **Step 5: Run tests and build**

Run: `./test.sh && swift build`
Expected: all tests pass; the app builds with no errors (search the output for `error:`).

- [ ] **Step 6: Commit**

```bash
git add Sources/ClaudeDockCore/Stoplight.swift Sources/ClaudeDock/Components.swift Sources/ClaudeDock/SettingsView.swift Sources/ClaudeDock/Showcase.swift Tests/ClaudeDockCoreTests/StoplightTests.swift
git commit -m "Keep the stoplight dot steady; particles will show an org in use

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Whether an org is in use

**Files:**
- Create: `Sources/ClaudeDockCore/InUse.swift`
- Test: `Tests/ClaudeDockCoreTests/InUseTests.swift`

**Interfaces:**
- Produces:
  - `InUse.claudeCodeQuiet: TimeInterval` (60), `InUse.riseLasts: TimeInterval` (240)
  - `InUse.isInUse(org: String, latest: Reading?, previous: Reading?, claudeCodeOrg: String?, claudeCodeActiveAt: Date?, stale: Bool, now: Date) -> Bool`
  - `InUse.rose(from previous: Reading, to latest: Reading) -> Bool`

- [ ] **Step 1: Write the failing tests**

Create `Tests/ClaudeDockCoreTests/InUseTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify they fail**

Run: `./test.sh --filter InUseTests`
Expected: build failure, `cannot find 'InUse' in scope`.

- [ ] **Step 3: Implement**

Create `Sources/ClaudeDockCore/InUse.swift`:

```swift
import Foundation

/// Whether an org is being used right now. Two signals: Claude Code writing its transcripts
/// while signed into the org (seconds behind), and the org's usage going up between two
/// readings (one poll behind, but it also sees the desktop app and the browser).
public enum InUse {
    /// Claude Code counts as working for this long after it last wrote a transcript.
    public static let claudeCodeQuiet: TimeInterval = 60
    /// A rise counts for this long after the reading that showed it: a little over one poll.
    public static let riseLasts: TimeInterval = 240
    /// Reset times this close together belong to the same window.
    static let sameWindow: TimeInterval = 60

    public static func isInUse(org: String, latest: Reading?, previous: Reading?, claudeCodeOrg: String?,
                               claudeCodeActiveAt: Date?, stale: Bool, now: Date) -> Bool {
        guard !stale else { return false }
        if org == claudeCodeOrg, let active = claudeCodeActiveAt, now.timeIntervalSince(active) < claudeCodeQuiet {
            return true
        }
        guard let latest, let previous, now.timeIntervalSince(latest.time) < riseLasts,
              latest.time.timeIntervalSince(previous.time) <= Reading.freshFor else { return false }
        return rose(from: previous, to: latest)
    }

    /// Whether usage went up between two readings of one org: more used in the same 5-hour
    /// or weekly window, or a new window that already shows use (a window opens on first
    /// use). A reset to nothing is not a rise.
    public static func rose(from previous: Reading, to latest: Reading) -> Bool {
        func rose(_ before: Double, _ beforeReset: Date?, _ after: Double, _ afterReset: Date?) -> Bool {
            guard afterReset != nil, after > 0 else { return false }
            guard let beforeReset, let afterReset, abs(afterReset.timeIntervalSince(beforeReset)) < sameWindow else { return true }
            return after > before
        }
        return rose(previous.session, previous.sessionResetsAt, latest.session, latest.sessionResetsAt)
            || rose(previous.week, previous.weekResetsAt, latest.week, latest.weekResetsAt)
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `./test.sh --filter InUseTests`
Expected: `Suite InUseTests passed`, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/ClaudeDockCore/InUse.swift Tests/ClaudeDockCoreTests/InUseTests.swift
git commit -m "Tell when an org is in use: Claude Code working on it, or its usage rising

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: The compact layout

**Files:**
- Modify: `Sources/ClaudeDock/WidgetView.swift`
- Modify: `Sources/ClaudeDock/Renderer.swift` (render compact too)
- Modify: `Sources/ClaudeDock/Showcase.swift` (`renderMatrix`, `MatrixSheet`, `StripSheet`)

**Interfaces:**
- Consumes: `StoplightDot(light:size:)` (Task 2), `WeekRing`, `UsageBar`, `Copy.widgetSummary`.
- Produces: `WidgetView(model:actions:compact:)`, where `compact: Bool = false`. With no orgs, compact draws the same placeholder as the full widget.

- [ ] **Step 1: Give `WidgetView` a compact mode**

In `Sources/ClaudeDock/WidgetView.swift`:

Add the property after `var actions: WidgetActions`:

```swift
    /// The compact widget: each org's ring, name and 5-hour line. Without orgs it shows the
    /// same placeholder as the full widget.
    var compact = false
```

Replace the `Group { if model.vertical { strip } else { bar } }` in `body` with:

```swift
        Group {
            if compact && !model.orgs.isEmpty {
                if model.vertical { compactStrip } else { compactBar }
            } else {
                if model.vertical { strip } else { bar }
            }
        }
```

Update the doc comment above `struct WidgetView` to:

```swift
/// The always-on widget: one block per org, plus a switch tab when there's advice. A
/// horizontal bar as tall as the Dock, or a narrow vertical strip on the left and right
/// edges; in compact mode each org shrinks to its ring, name and 5-hour line. Contents
/// scale with the Dock's icon size and the owner's size setting.
```

Add after `private var strip: some View { ... }`:

```swift
    private var compactBar: some View {
        HStack(spacing: 0) {
            if let advice = model.advice {
                switchBadge(advice)
                    .frame(width: 26 * k)
                    .frame(maxHeight: .infinity)
                    .background(Palette.warn.opacity(0.16))
            }
            HStack(spacing: 6 * k) {
                ForEach(model.orgs) { org in CompactOrg(model: model, org: org, k: k, open: actions.tap) }
            }
            .padding(.horizontal, 10 * k)
        }
        .frame(height: model.widgetHeight)
        .hud(radius: model.widgetHeight * 0.27, glass: true)
    }

    private var compactStrip: some View {
        VStack(spacing: 0) {
            if let advice = model.advice {
                switchBadge(advice)
                    .frame(height: 24 * k)
                    .frame(maxWidth: .infinity)
                    .background(Palette.warn.opacity(0.16))
            }
            VStack(spacing: 6 * k) {
                ForEach(model.orgs) { org in CompactOrg(model: model, org: org, k: k, open: actions.tap) }
            }
            .padding(.vertical, 10 * k)
        }
        .frame(width: 68 * k)
        .hud(radius: 22 * k, glass: true)
    }
```

Replace `switchTab(_:)` with these three, so the tab and the badge say the same thing:

```swift
    private func switchSummary(_ advice: Advice) -> String {
        "Move Claude Code to \(advice.target.name): \(advice.reason)."
    }

    private func switchTab(_ advice: Advice) -> some View {
        VStack(spacing: 1 * k) {
            Text("⇄").font(.system(size: 14 * k)).foregroundStyle(Palette.warn)
            Text("\(advice.target.name)\nfirst")
                .font(.system(size: max(9.5 * k, 9), weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: 64 * k)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(switchSummary(advice))
        .help(switchSummary(advice))
    }

    /// The compact widget's switch tab: just the amber ⇄, saying the same as the full tab.
    private func switchBadge(_ advice: Advice) -> some View {
        Text("⇄").font(.system(size: 15 * k)).foregroundStyle(Palette.warn)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(switchSummary(advice))
            .help(switchSummary(advice))
    }
```

- [ ] **Step 2: Add `CompactOrg` and share the accessibility with `OrgBlock`**

In `OrgBlock.body`, replace the six lines from `.accessibilityElement(children: .ignore)` to `.help(summary)` with `.orgButton(summary, open: open)`.

Then add at the end of the file:

```swift
/// One org in the compact widget: the week ring with its stoplight dot on the edge, the
/// name, and the 5-hour line, stacked and centred.
private struct CompactOrg: View {
    @ObservedObject var model: AppModel
    let org: Org
    let k: CGFloat
    let open: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let reading = model.reading(for: org)
        let forecast = model.forecast(for: org)
        let light = model.light(for: org) ?? .yellow
        let summary = Copy.widgetSummary(org.name, reading, light: model.light(for: org),
                                         forecast: forecast, now: model.now, formatting: model.formatting)
        VStack(spacing: 3 * k) {
            WeekRing(used: reading?.week ?? 0, elapsed: forecast?.elapsedFraction ?? 0,
                     color: light == .red ? Palette.crit : Palette.accent, size: 44 * k)
                .overlay(alignment: .topTrailing) {
                    // A rim in the glass's colour keeps the dot readable on top of the ring.
                    StoplightDot(light: light, size: 9 * k)
                        .background(Circle().fill(scheme == .dark ? Color.black.opacity(0.35) : Color.white.opacity(0.7))
                            .padding(-2 * k))
                        .offset(x: -1 * k, y: 1 * k)
                }
            Text(org.name)
                .font(.system(size: max(10 * k, 9), weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 54 * k)
            UsageBar(used: reading?.session ?? 0, tick: reading?.sessionElapsedFraction(now: model.now),
                     color: Palette.accent, height: 4 * k)
                .frame(width: 46 * k)
        }
        .frame(width: 56 * k)
        .opacity(reading != nil && !model.isFresh(org) && !model.isStale ? 0.55 : 1)
        .orgButton(summary, open: open)
    }
}

private extension View {
    /// An org reads as one button to VoiceOver, its sentence also the tooltip.
    func orgButton(_ summary: String, open: @escaping () -> Void) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(summary)
            .accessibilityHint("Opens the details")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, open)
            .help(summary)
    }
}
```

- [ ] **Step 3: Render compact in `--render`**

In `Sources/ClaudeDock/Renderer.swift`, inside the `for scheme in ...` loop, after the line that writes `-widget-`, add:

```swift
                write(WidgetView(model: model, actions: .none, compact: true), scheme,
                      dir.appendingPathComponent("\(scenario.name)-compact-\(suffix).png"))
```

- [ ] **Step 4: Add compact rows and strips to `--matrix`**

In `Sources/ClaudeDock/Showcase.swift`'s `renderMatrix`, replace the `rows` and `strips` building with:

```swift
            var rows: [(String, AppModel, Bool)] = []
            for set in sets {
                for size in [0.8, 1.0, 1.5] { rows.append(("\(set.0) · \(Int(size * 100))%", model(set, size: size, vertical: false), false)) }
                rows.append(("\(set.0) · compact", model(set, size: 1, vertical: false), true))
            }
            write(MatrixSheet(rows: rows), size: CGSize(width: 1500, height: 2400), scheme: scheme, to: dir, "matrix-horizontal-\(suffix).png")
            let strips = sets.flatMap { [($0.0, model($0, size: 1, vertical: true), false),
                                         ("\($0.0) · compact", model($0, size: 1, vertical: true), true)] }
            write(StripSheet(strips: strips), size: CGSize(width: 1500, height: 760), scheme: scheme, to: dir, "matrix-vertical-\(suffix).png")
```

Change `MatrixSheet` to take `var rows: [(String, AppModel, Bool)]` and draw `WidgetView(model: row.1, actions: .none, compact: row.2).fixedSize()`. Change `StripSheet` to take `var strips: [(String, AppModel, Bool)]`, draw `WidgetView(model: strip.1, actions: .none, compact: strip.2).fixedSize()`, and give its label `.frame(width: 110).lineLimit(2).multilineTextAlignment(.center)` so long labels don't widen the columns.

- [ ] **Step 5: Build and render**

Run:
```bash
swift build 2>&1 | grep -E "error:" ; \
R=${TMPDIR:-/tmp}/claudedock-render && rm -rf $R && \
.build/debug/ClaudeDock --render $R && .build/debug/ClaudeDock --matrix $R/matrix && ls $R | head -40
```
Expected: no errors; files such as `green-and-red-compact-dark.png` and `matrix/matrix-horizontal-dark.png`.

- [ ] **Step 6: Check the renders by eye (Review Focus 4)**

Open with the Read tool: `green-and-red-compact-dark.png`, `switch-for-desktop-app-compact-light.png`, `matrix/matrix-horizontal-dark.png`, `matrix/matrix-vertical-light.png`. Each compact org must show a 44 pt ring with its percentage, the dot sitting on the ring's top-right edge, the name under it and the 5-hour line under that. The switch scenario has an amber ⇄ strip on the left (and across the top in the vertical sheet). In the matrix, "long names" and "long, unshortened" must be cut off with "…" inside their 56 pt columns, three orgs must sit side by side with even spacing, and the org with no reading must show a 0% ring and its name. Fix anything that overflows or misaligns before going on.

- [ ] **Step 7: Commit**

```bash
git add Sources/ClaudeDock/WidgetView.swift Sources/ClaudeDock/Renderer.swift Sources/ClaudeDock/Showcase.swift
git commit -m "Add the compact widget: each org's ring, name and 5-hour line

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Grow on hover

**Files:**
- Create: `Sources/ClaudeDock/WidgetContainer.swift`
- Modify: `Sources/ClaudeDock/DockController.swift` (full replacement below)
- Modify: `Sources/ClaudeDock/Settings.swift` (`compact`)
- Modify: `Sources/ClaudeDock/Components.swift` (`WidgetActions.compact`)
- Modify: `Sources/ClaudeDock/WidgetView.swift` (menu item)
- Modify: `Sources/ClaudeDock/AppDelegate.swift` (wire the action)

**Interfaces:**
- Consumes: `WidgetPlacement.anchor`, `WidgetPlacement.expandedFrame`, `GrowthAnchor` (Task 1); `WidgetView(model:actions:compact:)` (Task 4).
- Produces: `Settings.compact: Bool` (default true); `WidgetActions.compact: (Bool) -> Void`; `DockController.setCompact(_ on: Bool)`.

- [ ] **Step 1: Add the setting**

In `Sources/ClaudeDock/Settings.swift`, add after `sizeScale`:

```swift
    /// Shrinks the widget to each org's ring, name and 5-hour line until the pointer rests on it.
    @Published var compact: Bool { didSet { defaults.set(compact, forKey: "compact") } }
```

and in `init`, after `sizeScale = ...`:

```swift
        compact = defaults.object(forKey: "compact") as? Bool ?? true
```

- [ ] **Step 2: Add the action and the menu item**

In `WidgetActions` (`Sources/ClaudeDock/Components.swift`), add after `size`:

```swift
    /// Turns Shrink until hovered on or off.
    var compact: (Bool) -> Void = { _ in }
```

In `WidgetView.menu`, after the `Menu("Size") { ... }` block, add:

```swift
        check("Shrink until hovered", settings.compact) { actions.compact(!settings.compact) }
```

In `AppDelegate.applicationDidFinishLaunching`, add to the `WidgetActions(...)` call after `size:`:

```swift
            compact: { [weak self] in self?.dock.setCompact($0) },
```

- [ ] **Step 3: Create the container view**

Create `Sources/ClaudeDock/WidgetContainer.swift`:

```swift
import AppKit

/// The widget window's content: the compact and full widgets stacked, each at its own size.
/// Reports the pointer coming onto it and leaving, even while the app is inactive (the widget
/// never becomes key).
final class WidgetContainer: NSView {
    var onHover: ((Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}
```

- [ ] **Step 4: Replace `DockController`**

Replace `Sources/ClaudeDock/DockController.swift` with the version below. Unchanged from today: the panel setup, `show`, `togglePanel`, the outside-click and Esc monitors, `dragEnded`, `place`, `setLayout`, `setSize`, `pinch`, the scale part of `layout()`, and `dockWidth(on:)`.

```swift
import AppKit
import Combine
import SwiftUI
import ClaudeDockCore

/// Owns the two floating windows: the always-on widget and the panel it opens. The widget
/// window holds the compact and the full widget. In compact mode it shows the compact one
/// and grows to the full one while the pointer rests on it or the panel is open.
@MainActor
final class DockController {
    var onPanelOpened: (() -> Void)?

    private let model: AppModel
    // No window shadow: the Dock has none, and on glass it reads as a dark outline.
    private let widget = FloatingPanel(allowsKey: false, shadow: false)
    private let container = WidgetContainer()
    private let fullHost: NSHostingView<WidgetView>
    private let compactHost: NSHostingView<WidgetView>
    private let panel = FloatingPanel(allowsKey: true)
    private let panelContent: NSHostingView<PanelView>
    private var monitors: [Any] = []
    private var changes: AnyCancellable?
    private var hiddenUntil: Date?
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var pinchFactor: Double = 1
    /// The owner scale the widget is drawn at now, after fitting it on screen.
    private var appliedScale: Double = 1
    private var settingsChanges: AnyCancellable?
    /// Where the compact and the full widget go, and the edges the widget grows from. With
    /// compact mode off, both are the full widget's frame.
    private var frames: (compact: NSRect, full: NSRect, anchor: GrowthAnchor)?
    /// Compact mode is showing the full widget: the pointer rests on it, or the panel is open.
    private var expanded = false
    private var pointerInside = false
    private var hoverWork: DispatchWorkItem?
    /// Counts grow and shrink animations, so one that was overtaken finishes quietly.
    private var generation = 0
    private var animating = false
    /// One level above the Dock (which draws over floating windows), for the expanded widget.
    private static let aboveDock = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)

    init(model: AppModel, actions: WidgetActions) {
        self.model = model
        fullHost = NSHostingView(rootView: WidgetView(model: model, actions: actions))
        compactHost = NSHostingView(rootView: WidgetView(model: model, actions: actions, compact: true))
        for host in [compactHost, fullHost] {
            // Sized by `arrange`, not by SwiftUI's constraints, so each keeps its size (and
            // SwiftUI doesn't re-lay it out) while the window grows and shrinks around it.
            host.sizingOptions = []
            container.addSubview(host)
        }
        widget.contentView = container
        container.onHover = { [weak self] inside in self?.pointerMoved(inside: inside) }
        // The panel scrolls when the screen is too short for it (a 13-inch laptop, three orgs).
        panelContent = NSHostingView(rootView: PanelView(model: model, actions: actions))
        let scroll = NSScrollView()
        scroll.documentView = panelContent
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.borderType = .noBorder
        panel.contentView = scroll
        changes = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.layout() } }
        }
        settingsChanges = model.settings.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.layout() } }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        // Apps that open or quit change the Dock's width.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.layout() }
            }
        }
    }

    func show() {
        hiddenUntil = nil
        layout()
        widget.orderFrontRegardless()
    }

    func hide(for seconds: TimeInterval) {
        hoverWork?.cancel()
        expanded = false
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
        hoverWork?.cancel()
        setExpanded(true)
        placePanel()
        panelContent.scroll(.zero)
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
        // The widget stayed full size for the panel: shrink it unless the pointer is on it.
        recheckPointer()
    }

    /// Moves the widget with the mouse. Screen coordinates, so the window moving under the
    /// pointer doesn't disturb the drag. In compact mode the compact widget is what moves.
    func dragChanged() {
        let mouse = NSEvent.mouseLocation
        if dragStart == nil {
            hoverWork?.cancel()
            collapseForDrag()
            dragStart = (mouse, widget.frame.origin)
            closePanel()
        }
        guard let start = dragStart else { return }
        widget.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
    }

    /// Near one of the six snap points the widget snaps there; anywhere else it stays put.
    func dragEnded() {
        dragStart = nil
        guard let screen = NSScreen.screens.first else { return }
        if let point = WidgetPlacement.snap(frame: widget.frame, screen: screen.frame, visible: screen.visibleFrame,
                                            dockWidth: Self.dockWidth(on: screen)) {
            model.settings.widgetSpot = .snapped(point)
        } else {
            model.settings.widgetSpot = .free(WidgetPlacement.offset(origin: widget.frame.origin, size: widget.frame.size,
                                                                     screen: screen.frame))
        }
        layout()
    }

    func place(_ point: SnapPoint) {
        model.settings.widgetSpot = .snapped(point)
        layout()
    }

    func setLayout(_ choice: LayoutChoice) {
        model.settings.layoutChoice = choice
        layout()
    }

    func setSize(_ scale: Double) {
        model.settings.sizeScale = WidgetLayout.clampSize(scale)
        layout()
    }

    func setCompact(_ on: Bool) {
        hoverWork?.cancel()
        expanded = false
        model.settings.compact = on
        layout()
    }

    /// Resizes live while pinching, and keeps the size when the pinch ends.
    func pinch(_ magnification: Double, ended: Bool) {
        if ended {
            pinchFactor = 1
            model.settings.sizeScale = WidgetLayout.clampSize(model.settings.sizeScale * magnification)
        } else {
            pinchFactor = WidgetLayout.clampSize(model.settings.sizeScale * magnification) / model.settings.sizeScale
        }
        layout()
    }

    // MARK: Growing and shrinking

    /// The pointer came onto the widget or left it. In compact mode the widget grows once
    /// the pointer has rested on it for 0.25 s, and shrinks 0.4 s after it leaves (not while
    /// the panel is open).
    private func pointerMoved(inside: Bool) {
        pointerInside = inside
        hoverWork?.cancel()
        guard model.settings.compact, dragStart == nil, inside != expanded, inside || !panel.isVisible else { return }
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.setExpanded(inside) } }
        hoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (inside ? 0.25 : 0.4), execute: work)
    }

    /// After the widget moves, changes size or the panel closes, the pointer may be
    /// somewhere else without an enter or exit event to say so.
    private func recheckPointer() {
        pointerMoved(inside: widget.isVisible && widget.frame.contains(NSEvent.mouseLocation))
    }

    /// Grows to the full widget or shrinks back to the compact one: the window's frame
    /// animates while the two crossfade. With Reduce Motion only the crossfade runs: the
    /// window grows before it, and shrinks after it (in `layout`).
    private func setExpanded(_ expand: Bool) {
        guard model.settings.compact, expand != expanded, dragStart == nil, let frames else { return }
        expanded = expand
        generation += 1
        let current = generation
        let target = expand ? frames.full : frames.compact
        let incoming = expand ? fullHost : compactHost
        let outgoing = expand ? compactHost : fullHost
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if expand { widget.level = Self.aboveDock }
        incoming.isHidden = false
        animating = true
        // Clip both widgets to the window's rounded shape while it changes size.
        container.layer?.masksToBounds = true
        if reduceMotion, expand { widget.setFrame(target, display: true) }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduceMotion ? 0.2 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if !reduceMotion { widget.animator().setFrame(target, display: true) }
            incoming.animator().alphaValue = 1
            outgoing.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.animating = false
                self.container.layer?.masksToBounds = false
                self.layout()  // settles the frame, hides the faded widget, sets the level
                self.recheckPointer()
            }
        })
    }

    /// A drag moves the compact widget: drop to it at once, overriding any animation under
    /// way. The full widget stays in the window, transparent, until the drag ends, so a drag
    /// that started on it keeps getting events.
    private func collapseForDrag() {
        guard model.settings.compact, expanded || animating, let frames else { return }
        generation += 1
        animating = false
        expanded = false
        container.layer?.masksToBounds = false
        widget.level = .floating
        compactHost.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            widget.animator().setFrame(frames.compact, display: true)
            compactHost.animator().alphaValue = 1
            fullHost.animator().alphaValue = 0
        }
    }

    // MARK: Layout

    /// Sizes the widget to the Dock bar and places it on the primary display (the one with the
    /// menu bar; `NSScreen.main` follows keyboard focus between displays): where the owner
    /// dragged it, or the bottom-right corner beside the Dock. In compact mode the compact
    /// widget is placed and the full one grows out of it.
    private func layout() {
        guard let screen = NSScreen.screens.first else { return }
        let settings = model.settings
        let tileSize = UserDefaults(suiteName: "com.apple.dock")?.object(forKey: "tilesize") as? Double
        // The owner's size, shrunk only if the full widget wouldn't fit on screen (size
        // measured from what's drawn now, divided back to scale 1).
        let current = fullHost.fittingSize
        let natural = CGSize(width: current.width / appliedScale, height: current.height / appliedScale)
        let ownerScale = WidgetLayout.fittedScale(settings.sizeScale * pinchFactor, natural: natural,
                                                  visible: screen.visibleFrame)
        let height = DockFit.height(screen: screen.frame, visible: screen.visibleFrame, tileSize: tileSize) * ownerScale
        let scale = DockFit.contentScale(screen: screen.frame, visible: screen.visibleFrame, tileSize: tileSize) * ownerScale
        let vertical = WidgetLayout.isVertical(spot: settings.widgetSpot, choice: settings.layoutChoice)
        if abs(model.widgetHeight - height) > 0.5 || abs(model.widgetScale - scale) > 0.001 || model.vertical != vertical {
            model.widgetHeight = height  // these changes trigger another layout with the new size
            model.widgetScale = scale
            model.vertical = vertical
            appliedScale = ownerScale
            return
        }
        guard dragStart == nil, !animating else { return }
        let full = fullHost.fittingSize
        let compactSize = settings.compact ? compactHost.fittingSize : full
        let origin = WidgetPlacement.origin(size: compactSize, screen: screen.frame, visible: screen.visibleFrame,
                                            spot: settings.widgetSpot, dockWidth: Self.dockWidth(on: screen))
        let compact = NSRect(origin: origin, size: compactSize)
        let anchor = WidgetPlacement.anchor(compact: compact, visible: screen.visibleFrame, spot: settings.widgetSpot)
        let grown = settings.compact
            ? WidgetPlacement.expandedFrame(compact: compact, size: full, anchor: anchor,
                                            screen: screen.frame, visible: screen.visibleFrame)
            : compact
        frames = (compact, grown, anchor)
        if !settings.compact { expanded = false }
        let showFull = !settings.compact || expanded
        let frame = showFull ? grown : compact
        if frame != widget.frame { widget.setFrame(frame, display: false) }
        arrange(in: frame)
        compactHost.isHidden = showFull
        compactHost.alphaValue = showFull ? 0 : 1
        fullHost.isHidden = !showFull
        fullHost.alphaValue = showFull ? 1 : 0
        widget.level = settings.compact && expanded ? Self.aboveDock : .floating
        if panel.isVisible { placePanel() }
    }

    /// Puts each widget at its own place inside a window at `frame`, pinned to the edges the
    /// widget grows from, so both stay put on screen while the window changes size.
    private func arrange(in frame: NSRect) {
        guard let frames else { return }
        var pin: NSView.AutoresizingMask = frames.anchor.horizontal == .right ? .minXMargin : .maxXMargin
        switch frames.anchor.vertical {
        case .bottom: pin.insert(.maxYMargin)
        case .top: pin.insert(.minYMargin)
        case .center: pin.formUnion([.minYMargin, .maxYMargin])
        }
        for (host, place) in [(compactHost, frames.compact), (fullHost, frames.full)] {
            host.autoresizingMask = pin
            host.frame = place.offsetBy(dx: -frame.minX, dy: -frame.minY)
        }
        container.layer?.cornerRadius = model.vertical ? 22 * model.widgetScale : model.widgetHeight * 0.27
    }

    /// The Dock's estimated width, from its settings and the apps running now.
    private static func dockWidth(on screen: NSScreen) -> Double? {
        let dock = UserDefaults(suiteName: "com.apple.dock")
        // Spacers and web apps have no bundle id but still take a slot.
        func apps(_ key: String) -> [String] {
            (dock?.array(forKey: key) as? [[String: Any]] ?? []).enumerated().map { index, tile in
                (tile["tile-data"] as? [String: Any])?["bundle-identifier"] as? String ?? "\(key)-\(index)"
            }
        }
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleIdentifier)
        let contents = DockFit.contents(pinned: apps("persistent-apps"), recent: apps("recent-apps"), running: running,
                                        folders: dock?.array(forKey: "persistent-others")?.count ?? 0,
                                        showRecents: dock?.object(forKey: "show-recents") as? Bool ?? true)
        return DockFit.estimatedWidth(items: contents.items, dividers: contents.dividers,
                                      screen: screen.frame, visible: screen.visibleFrame)
    }

    private func placePanel() {
        guard let screen = widget.screen ?? NSScreen.screens.first else { return }
        let size = panelContent.fittingSize
        if panelContent.frame.size != size { panelContent.frame = NSRect(origin: .zero, size: size) }
        // Against where the widget is going, not where an animation has it right now.
        let resting = frames.map { expanded || !model.settings.compact ? $0.full : $0.compact } ?? widget.frame
        panel.setFrame(WidgetPlacement.panelFrame(panel: size, widget: resting, visible: screen.visibleFrame),
                       display: true)
    }
}
```

- [ ] **Step 5: Build**

Run: `swift build 2>&1 | grep -E "error" ; echo done`
Expected: `done` with no `error:` lines. If the compiler rejects `NSAnimationContext`'s change closure capturing `widget` implicitly, write `self.widget`, `self.fullHost` and `self.compactHost` there.

- [ ] **Step 6: Run the app on the real desktop**

Ask the owner before quitting the copy of Claude Dock they have running (`pkill -f "Claude Dock.app/Contents/MacOS/ClaudeDock"`). Then run `./build.sh && open "build/Claude Dock.app"`.

- [ ] **Step 7: The smoothness check (spec risk 1)**

Ask the owner to rest the pointer on the widget and move it away a few times, and to say whether the growth looks smooth. If it stutters, switch to the fallback the spec allows: in `setExpanded`, treat the frame as Reduce Motion always does (grow before the fade, shrink after it), keeping the 0.22 s crossfade. To do that, change `let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` to `let reduceMotion = true // the frame animation stuttered on <Mac model>; see the spec's Risks`, then rebuild and check again.

- [ ] **Step 8: Check the edge cases with the owner (Review Focus 1–3)**

With the owner, check each one and fix any that fail before committing:
1. Move the pointer on and off quickly five times, and leave in the middle of a growth: it ends compact, and never stays stuck open.
2. Rest the pointer until it starts growing, then drag right away: the compact widget moves with no jump, snaps where dropped, and stays compact.
3. Right-click → **Shrink until hovered** off while the widget is expanded, then on again with the panel open: first the full widget in its normal place, then the compact one with the panel against the expanded widget.
4. Click the compact widget: it grows and the panel opens above the expanded widget. Press Esc with the pointer away: the panel closes and the widget shrinks.
5. Expanded beside the Dock, it draws over the Dock (not under it).
6. Right-click → **Position** → Right side: the compact strip grows to the left, staying centred vertically. Top left: it grows right and down.
7. System Settings → Accessibility → Display → Reduce motion on: the widget only crossfades. Turn it off again.

- [ ] **Step 9: Commit**

```bash
git add Sources/ClaudeDock/WidgetContainer.swift Sources/ClaudeDock/DockController.swift Sources/ClaudeDock/Settings.swift Sources/ClaudeDock/Components.swift Sources/ClaudeDock/WidgetView.swift Sources/ClaudeDock/AppDelegate.swift
git commit -m "Shrink until hovered: grow from the corner over the Dock, crossfading

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Particles on an org in use

**Files:**
- Create: `Sources/ClaudeDockCore/Effects.swift`
- Create: `Sources/ClaudeDock/InUseEffect.swift`
- Modify: `Sources/ClaudeDock/AppModel.swift` (`inUse(for:)`, `previous`, `claudeCodeActiveAt`, forward settings changes)
- Modify: `Sources/ClaudeDock/DemoData.swift` (`claudeCodeWorking`)
- Modify: `Sources/ClaudeDock/Settings.swift` (`effectStyle`, `effectAmount`)
- Modify: `Sources/ClaudeDock/Components.swift` (`WidgetActions.effect`, `.amount`)
- Modify: `Sources/ClaudeDock/WidgetView.swift` (effects on `OrgBlock` and `CompactOrg`; the menu)
- Modify: `Sources/ClaudeDock/AppDelegate.swift`
- Test: `Tests/ClaudeDockCoreTests/EffectsTests.swift`

**Interfaces:**
- Consumes: `InUse.isInUse` (Task 3); `CompactOrg` (Task 4).
- Produces:
  - `public enum EffectStyle: String, Codable, CaseIterable, Sendable { case sparks, flow, shimmer, off }`
  - `public enum EffectAmount: String, Codable, CaseIterable, Sendable { case subtle, normal, lots; var multiplier: Double }`
  - `AppModel.inUse(for: Org) -> Bool`, `AppModel.claudeCodeActiveAt: Date?` (`private(set)`, set by Task 7)
  - `InUseEffect(target: EffectTarget, style:, amount:, color: Color)`, `enum EffectTarget { case ring(fill: Double, radius: CGFloat), line(fill: Double) }`

- [ ] **Step 1: Write the failing test for the enums**

Create `Tests/ClaudeDockCoreTests/EffectsTests.swift`:

```swift
import Testing
@testable import ClaudeDockCore

@Suite struct EffectsTests {
    @Test func amountsScaleTheParticles() {
        #expect(EffectAmount.allCases.map(\.multiplier) == [0.5, 1, 1.8])
    }

    @Test func choicesAreSavedByName() {
        #expect(EffectStyle.allCases.map(\.rawValue) == ["sparks", "flow", "shimmer", "off"])
        #expect(EffectStyle(rawValue: "confetti") == nil)  // Settings falls back to the default
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `./test.sh --filter EffectsTests`
Expected: build failure, `cannot find 'EffectAmount' in scope`.

- [ ] **Step 3: Implement the enums**

Create `Sources/ClaudeDockCore/Effects.swift`:

```swift
/// How an org that's in use shows it, on its ring and its 5-hour line.
public enum EffectStyle: String, Codable, CaseIterable, Sendable {
    /// A glint around the ring that sheds sparks; the 5-hour line burns like a fuse.
    case sparks
    /// Specks of light streaming along the filled part of the ring and the line.
    case flow
    /// A soft sweep of light along both, with a few embers rising off the ring.
    case shimmer
    case off
}

/// How many particles, as a multiple of the normal birth rates and speck counts.
public enum EffectAmount: String, Codable, CaseIterable, Sendable {
    case subtle, normal, lots

    public var multiplier: Double {
        switch self {
        case .subtle: 0.5
        case .normal: 1
        case .lots: 1.8
        }
    }
}
```

Run: `./test.sh --filter EffectsTests` — Expected: 2 tests pass.

- [ ] **Step 4: Settings, actions and the menu**

In `Sources/ClaudeDock/Settings.swift`, add after `compact`:

```swift
    /// How an org that's in use shows it, and how many particles.
    @Published var effectStyle: EffectStyle { didSet { defaults.set(effectStyle.rawValue, forKey: "effectStyle") } }
    @Published var effectAmount: EffectAmount { didSet { defaults.set(effectAmount.rawValue, forKey: "effectAmount") } }
```

and in `init` after `compact = ...`:

```swift
        effectStyle = EffectStyle(rawValue: defaults.string(forKey: "effectStyle") ?? "") ?? .flow
        effectAmount = EffectAmount(rawValue: defaults.string(forKey: "effectAmount") ?? "") ?? .normal
```

In `WidgetActions`, add after `compact`:

```swift
    var effect: (EffectStyle) -> Void = { _ in }
    var amount: (EffectAmount) -> Void = { _ in }
```

In `AppDelegate`'s `WidgetActions(...)`, after `compact:`:

```swift
            effect: { [weak self] in self?.model.settings.effectStyle = $0 },
            amount: { [weak self] in self?.model.settings.effectAmount = $0 },
```

In `WidgetView.menu`, after the `Shrink until hovered` item:

```swift
        Menu("In-use effect") {
            ForEach(EffectStyle.allCases, id: \.self) { style in
                check(Self.title(style), settings.effectStyle == style) { actions.effect(style) }
            }
            Divider()
            ForEach(EffectAmount.allCases, id: \.self) { amount in
                check(Self.title(amount), settings.effectAmount == amount) { actions.amount(amount) }
            }
        }
```

and next to `static func title(_ point: SnapPoint)`:

```swift
    static func title(_ style: EffectStyle) -> String {
        switch style {
        case .sparks: "Sparks"
        case .flow: "Flow"
        case .shimmer: "Shimmer"
        case .off: "Off"
        }
    }

    static func title(_ amount: EffectAmount) -> String {
        switch amount {
        case .subtle: "Subtle"
        case .normal: "Normal"
        case .lots: "Lots"
        }
    }
```

- [ ] **Step 5: The model knows which orgs are in use**

In `Sources/ClaudeDock/AppModel.swift`:

Add `import Combine` at the top. Add these properties after `@Published var vertical = false`:

```swift
    /// When Claude Code last wrote a transcript; it writes every few seconds while it works.
    private(set) var claudeCodeActiveAt: Date?
    /// Each org's reading before its newest, to tell whether its usage just went up.
    private var previous: [String: Reading] = [:]
    private var settingsChanges: AnyCancellable?
```

At the end of `init`, so the widget redraws when the effect or amount changes:

```swift
        settingsChanges = settings.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
```

After `func light(for:)`:

```swift
    /// Whether an org is being used right now; it gets the in-use effect.
    func inUse(for org: Org) -> Bool {
        InUse.isInUse(org: org.id, latest: latest[org.id], previous: previous[org.id], claudeCodeOrg: claudeCodeOrg,
                      claudeCodeActiveAt: claudeCodeActiveAt, stale: isStale, now: now)
    }
```

In `ingest`, replace `for r in outcome.readings { latest[r.org] = r }` with:

```swift
        for r in outcome.readings {
            if let old = latest[r.org] { previous[r.org] = old }
            latest[r.org] = r
        }
```

In `apply(_ scenario:)`, after `latest = ...`, add:

```swift
        previous = [:]
        claudeCodeActiveAt = scenario.claudeCodeWorking ? scenario.now : nil
```

and in `leaveDemo()`, after `latest = [:]`, add `previous = [:]` and `claudeCodeActiveAt = nil`.

In `Sources/ClaudeDock/DemoData.swift`, add to `DemoScenario` after `claudeCodeOrg`:

```swift
    /// Claude Code is working on `claudeCodeOrg`, so it shows the in-use effect.
    var claudeCodeWorking = false
```

change the helper to `func scenario(_ name: String, working: Bool = false, _ readings: [Reading]) -> DemoScenario` passing `claudeCodeWorking: working` (the memberwise initializer's last argument after `now:`, so write it `DemoScenario(name: name, orgs: [pikachu, charizard], primary: pikachu.id, readings: readings, claudeCodeOrg: pikachu.id, now: now, claudeCodeWorking: working)`), and mark the busy one: `scenario("switch-for-desktop-app", working: true, [`.

- [ ] **Step 6: Draw the effects**

Create `Sources/ClaudeDock/InUseEffect.swift`:

```swift
import AppKit
import SwiftUI
import ClaudeDockCore

/// What an in-use effect decorates.
enum EffectTarget: Equatable {
    /// The week ring: how much is filled (0...1), and its radius to the middle of the stroke.
    case ring(fill: Double, radius: CGFloat)
    /// The 5-hour line: how much is filled (0...1).
    case line(fill: Double)

    var isLine: Bool { if case .line = self { true } else { false } }
}

/// Particles on an org that's in use, over its ring or its 5-hour line, in the owner's style
/// and amount. Core Animation runs them in the window server, so the app does no work per
/// frame. With Reduce Motion, and in image renders (which can't draw Core Animation), a
/// still glow at the end of the fill instead.
struct InUseEffect: View {
    var target: EffectTarget
    var style: EffectStyle
    var amount: EffectAmount
    var color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.renderStyle) private var renderStyle
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if style != .off {
            if reduceMotion || renderStyle != .live {
                TipGlow(target: target, color: color)
            } else {
                EffectLayers(config: EffectConfig(target: target, style: style, amount: amount,
                                                  color: NSColor(color), dark: scheme == .dark))
            }
        }
    }
}

extension View {
    /// The in-use effect over this ring or line, when `on`.
    func inUseEffect(_ on: Bool, _ target: EffectTarget, settings: Settings, color: Color) -> some View {
        overlay {
            if on { InUseEffect(target: target, style: settings.effectStyle, amount: settings.effectAmount, color: color) }
        }
    }
}

/// Where the effects go in a view of a given size.
enum EffectGeometry {
    /// The angle of the end of the ring's fill in y-up coordinates (Core Animation's): the
    /// ring starts at the top and fills clockwise, so the angle falls as it fills.
    static func tipAngle(_ fill: Double) -> CGFloat { .pi / 2 - 2 * .pi * CGFloat(min(max(fill, 0), 1)) }

    /// The end of the fill; `flipped` for SwiftUI's y-down coordinates.
    static func tip(_ target: EffectTarget, in size: CGSize, flipped: Bool) -> CGPoint {
        switch target {
        case .ring(let fill, let radius):
            let angle = tipAngle(fill)
            let y = size.height / 2 + radius * sin(angle)
            return CGPoint(x: size.width / 2 + radius * cos(angle), y: flipped ? size.height - y : y)
        case .line(let fill):
            return CGPoint(x: max(size.width * CGFloat(fill), 2), y: size.height / 2)
        }
    }

    /// The filled arc or stretch of line, for effects that travel along it (y-up); nil when
    /// there's too little fill to travel along.
    static func fillPath(_ target: EffectTarget, in size: CGSize) -> CGPath? {
        let path = CGMutablePath()
        switch target {
        case .ring(let fill, let radius):
            guard fill > 0.01 else { return nil }
            path.addArc(center: CGPoint(x: size.width / 2, y: size.height / 2), radius: radius,
                        startAngle: .pi / 2, endAngle: tipAngle(fill), clockwise: true)
        case .line(let fill):
            guard size.width * CGFloat(fill) >= size.height else { return nil }
            path.move(to: CGPoint(x: 0, y: size.height / 2))
            path.addLine(to: CGPoint(x: size.width * CGFloat(fill), y: size.height / 2))
        }
        return path
    }
}

/// A soft, still glow where the fill ends.
private struct TipGlow: View {
    var target: EffectTarget
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let radius = max(target.isLine ? geo.size.height * 1.2 : geo.size.width * 0.16, 5)
            Circle()
                .fill(RadialGradient(colors: [Color.white.opacity(0.75), color.opacity(0.45), color.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: radius))
                .frame(width: radius * 2, height: radius * 2)
                .position(EffectGeometry.tip(target, in: geo.size, flipped: true))
        }
        .allowsHitTesting(false)
    }
}

struct EffectConfig: Equatable {
    var target: EffectTarget
    var style: EffectStyle
    var amount: EffectAmount
    var color: NSColor
    var dark: Bool
}

private struct EffectLayers: NSViewRepresentable {
    var config: EffectConfig

    func makeNSView(context: Context) -> EffectView { EffectView() }
    func updateNSView(_ view: EffectView, context: Context) { view.config = config }
}

/// Holds the effect's layers, rebuilt only when what they show or the view's size changes.
private final class EffectView: NSView {
    var config: EffectConfig? { didSet { if config != oldValue { rebuild() } } }
    private var builtSize: CGSize = .zero

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Clicks, drags and hovers go to the widget underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        if bounds.size != builtSize { rebuild() }
    }

    private func rebuild() {
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        builtSize = bounds.size
        guard let config, let layer, bounds.width > 0, bounds.height > 0 else { return }
        for effect in EffectLayersBuilder.layers(config, size: bounds.size) {
            effect.frame = CGRect(origin: .zero, size: bounds.size)
            layer.addSublayer(effect)
        }
    }
}

/// The Core Animation layers for each style. Every layer is full-size; rates and counts
/// scale with the amount. Coordinates are y-up.
private enum EffectLayersBuilder {
    static func layers(_ c: EffectConfig, size: CGSize) -> [CALayer] {
        let m = c.amount.multiplier
        let tip = EffectGeometry.tip(c.target, in: size, flipped: false)
        let path = EffectGeometry.fillPath(c.target, in: size)
        let light: NSColor = c.dark ? .white : c.color
        switch (c.style, c.target) {
        case (.off, _):
            return []
        case (.sparks, .ring(let fill, let radius)):
            let k = radius / 18  // 1 on the full widget's 48 pt ring
            // Sparks fly back along the ring (it fills clockwise) and a little outward.
            let back = EffectGeometry.tipAngle(fill) + .pi / 2 - 0.5
            var result: [CALayer] = []
            if let path {
                result.append(travellers(along: path, count: 8, spacing: 0.03, period: 1.8, timing: .easeInEaseOut,
                                         size: 4.5 * k, color: light, opacity: [0, 0.95, 0.95, 0], fade: -0.11))
            }
            result.append(sparks(at: tip, direction: back, spread: .pi / 4, rate: 55 * m, speed: 30 * k, gravity: 0,
                                 life: 0.7, scale: 0.18 * k, colors: c.dark ? [.white, c.color] : [c.color], dark: c.dark))
            result.append(glow(at: tip, radius: 7 * k, color: c.color))
            return result
        case (.sparks, .line):
            let big: CGFloat = size.height >= 6 ? 1.25 : 1
            let warm = NSColor(srgbRed: 1, green: 0.84, blue: 0.55, alpha: 1)
            return [sparks(at: tip, direction: .pi / 2 - 0.4, spread: .pi / 3, rate: 70 * m * Double(big), speed: 50 * big,
                           gravity: 190, life: 0.5, scale: 0.13 * big, colors: c.dark ? [warm, c.color] : [c.color], dark: c.dark),
                    glow(at: tip, radius: 6 * big, color: warm)]
        case (.flow, .ring(_, let radius)):
            guard let path else { return [] }
            let count = max(4, Int((12 * m).rounded()))
            return [travellers(along: path, count: count, spacing: 2.9 / Double(count), period: 2.9, timing: .linear,
                               size: 2.6 * radius / 18, color: light, opacity: [0, 0.9, 0], fade: 0)]
        case (.flow, .line):
            guard let path else { return [] }
            let count = max(3, Int((6 * m).rounded()))
            return [travellers(along: path, count: count, spacing: 1.7 / Double(count), period: 1.7, timing: .linear,
                               size: max(2, size.height * 0.65), color: .white, opacity: [0, 0.9, 0], fade: 0)]
        case (.shimmer, .ring(_, let radius)):
            let k = radius / 18
            var result: [CALayer] = []
            if let path {
                result.append(travellers(along: path, count: 6, spacing: 0.04, period: 2.6, timing: .easeInEaseOut,
                                         size: 4 * k, color: light, opacity: [0, 0.5, 0.5, 0], fade: -0.15))
            }
            result.append(embers(around: CGPoint(x: size.width / 2, y: size.height / 2), radius: radius + 4 * k,
                                 rate: 5 * m, k: k, color: c.color, dark: c.dark))
            return result
        case (.shimmer, .line(let fill)):
            let width = size.width * CGFloat(fill)
            guard width >= size.height else { return [] }
            return [sweep(width: width, height: size.height)]
        }
    }

    /// A small round particle, white so emitter cells can tint it.
    static let particle: CGImage = {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray
        let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
        context.drawRadialGradient(gradient, startCenter: CGPoint(x: 8, y: 8), startRadius: 0,
                                   endCenter: CGPoint(x: 8, y: 8), endRadius: 8, options: [])
        return context.makeImage()!
    }()

    /// Sparks from one point, mostly at `direction` (radians, y-up), falling with `gravity`.
    static func sparks(at point: CGPoint, direction: CGFloat, spread: CGFloat, rate: Double, speed: CGFloat,
                       gravity: CGFloat, life: Float, scale: CGFloat, colors: [NSColor], dark: Bool) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = point
        emitter.emitterShape = .point
        emitter.renderMode = dark ? .additive : .oldestLast
        emitter.emitterCells = colors.map { color in
            let cell = CAEmitterCell()
            cell.contents = particle
            cell.birthRate = Float(rate) / Float(colors.count)
            cell.lifetime = life
            cell.lifetimeRange = life * 0.3
            cell.velocity = speed
            cell.velocityRange = speed * 0.5
            cell.emissionLongitude = direction
            cell.emissionRange = spread
            cell.yAcceleration = -gravity
            cell.scale = scale
            cell.scaleRange = scale * 0.4
            cell.scaleSpeed = -scale / CGFloat(life)
            cell.alphaSpeed = -1 / life
            cell.color = color.cgColor
            return cell
        }
        return emitter
    }

    /// A few slow embers drifting up off a circle.
    static func embers(around center: CGPoint, radius: CGFloat, rate: Double, k: CGFloat, color: NSColor, dark: Bool) -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.emitterPosition = center
        emitter.emitterShape = .circle
        emitter.emitterMode = .outline
        emitter.emitterSize = CGSize(width: radius * 2, height: radius * 2)
        emitter.renderMode = dark ? .additive : .oldestLast
        let cell = CAEmitterCell()
        cell.contents = particle
        cell.birthRate = Float(rate)
        cell.lifetime = 2
        cell.lifetimeRange = 0.5
        cell.velocity = 14 * k
        cell.velocityRange = 6 * k
        cell.emissionLongitude = .pi / 2
        cell.emissionRange = 0.3
        cell.scale = 0.11 * k
        cell.alphaSpeed = -0.4
        cell.color = color.withAlphaComponent(0.8).cgColor
        emitter.emitterCells = [cell]
        return emitter
    }

    /// `count` dots travelling along `path` one after another every `period` seconds,
    /// `spacing` seconds apart, fading through `opacity`. `fade` dims each one after the
    /// first, for a trail.
    static func travellers(along path: CGPath, count: Int, spacing: CFTimeInterval, period: CFTimeInterval,
                           timing: CAMediaTimingFunctionName, size: CGFloat, color: NSColor,
                           opacity: [Float], fade: Float) -> CALayer {
        let dot = CALayer()
        dot.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        dot.cornerRadius = size / 2
        dot.backgroundColor = color.cgColor
        dot.opacity = 0
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.calculationMode = .paced
        let fadeInOut = CAKeyframeAnimation(keyPath: "opacity")
        fadeInOut.values = opacity
        let travel = CAAnimationGroup()
        travel.animations = [move, fadeInOut]
        travel.duration = period
        travel.timingFunction = CAMediaTimingFunction(name: timing)
        travel.repeatCount = .infinity
        travel.fillMode = .backwards
        travel.isRemovedOnCompletion = false
        dot.add(travel, forKey: "travel")
        let replicator = CAReplicatorLayer()
        replicator.instanceCount = count
        replicator.instanceDelay = spacing
        replicator.instanceAlphaOffset = fade
        replicator.addSublayer(dot)
        return replicator
    }

    /// A soft round glow.
    static func glow(at point: CGPoint, radius: CGFloat, color: NSColor) -> CALayer {
        let holder = CALayer()
        let glow = CAGradientLayer()
        glow.type = .radial
        glow.colors = [NSColor.white.withAlphaComponent(0.8).cgColor, color.withAlphaComponent(0.4).cgColor,
                       color.withAlphaComponent(0).cgColor]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.frame = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        holder.addSublayer(glow)
        return holder
    }

    /// A band of light sweeping along the filled part of the line.
    static func sweep(width: CGFloat, height: CGFloat) -> CALayer {
        let holder = CALayer()
        let fill = CALayer()
        fill.frame = CGRect(x: 0, y: 0, width: width, height: height)
        fill.cornerRadius = height / 2
        fill.masksToBounds = true
        let band = CAGradientLayer()
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        band.colors = [NSColor.white.withAlphaComponent(0).cgColor, NSColor.white.withAlphaComponent(0.75).cgColor,
                       NSColor.white.withAlphaComponent(0).cgColor]
        band.frame = CGRect(x: -24, y: 0, width: 24, height: height)
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = -12
        move.toValue = width + 12
        move.duration = 1.6
        move.repeatCount = .infinity
        band.add(move, forKey: "sweep")
        fill.addSublayer(band)
        holder.addSublayer(fill)
        return holder
    }
}
```

`EffectView.rebuild` sets every returned layer's frame to the view's bounds. That is why `glow` and `sweep` wrap their positioned layers in a full-size holder, and why the emitters and replicators use the view's coordinates.

- [ ] **Step 7: Put the effects on the rings and lines**

In `WidgetView.swift`'s `OrgBlock.content`, after `let light = ...`, add `let inUse = model.inUse(for: org)`. Change the `ring` and `bar` definitions to:

```swift
        let ringColor = light == .red ? Palette.crit : Palette.accent
        let ring = WeekRing(used: reading?.week ?? 0, elapsed: forecast?.elapsedFraction ?? 0, color: ringColor, size: 48 * k)
            .inUseEffect(inUse, .ring(fill: (reading?.week ?? 0) / 100, radius: 18 * k), settings: model.settings, color: ringColor)
```

```swift
        let bar = UsageBar(used: reading?.session ?? 0, tick: reading?.sessionElapsedFraction(now: model.now),
                           color: Palette.accent, height: 6 * k)
            .inUseEffect(inUse, .line(fill: (reading?.session ?? 0) / 100), settings: model.settings, color: Palette.accent)
```

In `CompactOrg.body`, do the same: after `let light = ...` add `let inUse = model.inUse(for: org)` and `let ringColor = light == .red ? Palette.crit : Palette.accent`; pass `color: ringColor` to its `WeekRing`, add `.inUseEffect(inUse, .ring(fill: (reading?.week ?? 0) / 100, radius: 16.5 * k), settings: model.settings, color: ringColor)` right after the `WeekRing(...)` (before its dot overlay), and add `.inUseEffect(inUse, .line(fill: (reading?.session ?? 0) / 100), settings: model.settings, color: Palette.accent)` after the `UsageBar(...)` (before `.frame(width: 46 * k)`, so the effect is sized to the line).

- [ ] **Step 8: Build, render and look**

Run:
```bash
swift build 2>&1 | grep -E "error" ; \
R=${TMPDIR:-/tmp}/claudedock-render && rm -rf $R && \
.build/debug/ClaudeDock --render $R && ls $R | grep switch
```
Expected: no errors. Open `switch-for-desktop-app-widget-dark.png` and `switch-for-desktop-app-compact-light.png` with the Read tool: Pikachu (Claude Code working in this scenario) has a soft glow at the end of its ring's fill and of its 5-hour line; Charizard has none.

- [ ] **Step 9: See it move, with the owner**

Run `./build.sh && open "build/Claude Dock.app"`, then right-click → **Settings…** → **Demo mode** on. Demo mode moves to the next scenario every 6 seconds; in the second one Pikachu is in use. For each of Sparks, Flow and Shimmer at Subtle, Normal and Lots, in compact and expanded, ask the owner whether it looks right. Tune the numbers in `EffectLayersBuilder` (rates, speeds, sizes, periods) to what they ask for.

While particles run, measure CPU (spec: near 0%):
```bash
top -l 6 -s 1 -stats pid,command,cpu | grep -i claudedock
```
Expected: ClaudeDock under 2% in the later samples. If it's higher, the usual cause is a SwiftUI re-render each frame. Check that nothing in `InUseEffect` depends on a value that changes continuously. Then turn demo mode off.

- [ ] **Step 10: Run the tests and commit**

Run: `./test.sh` — Expected: all pass.

```bash
git add Sources/ClaudeDockCore/Effects.swift Sources/ClaudeDock/InUseEffect.swift Sources/ClaudeDock/AppModel.swift Sources/ClaudeDock/DemoData.swift Sources/ClaudeDock/Settings.swift Sources/ClaudeDock/Components.swift Sources/ClaudeDock/WidgetView.swift Sources/ClaudeDock/AppDelegate.swift Tests/ClaudeDockCoreTests/EffectsTests.swift
git commit -m "Show particles on an org that's in use: Sparks, Flow or Shimmer

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Notice Claude Code working

**Files:**
- Create: `Sources/ClaudeDockCore/ClaudeCodeActivity.swift`
- Modify: `Sources/ClaudeDock/AppModel.swift` (`claudeCodeWorked(at:)`)
- Modify: `Sources/ClaudeDock/AppDelegate.swift` (start the watcher)
- Test: `Tests/ClaudeDockCoreTests/ClaudeCodeActivityTests.swift`

**Interfaces:**
- Consumes: `AppModel.claudeCodeActiveAt` (Task 6), `InUse.claudeCodeQuiet` (Task 3).
- Produces: `ClaudeCodeActivity(folder: URL = ~/.claude/projects, onActivity: @escaping @Sendable (Date) -> Void)`, `.start()`, `.stop()`; `AppModel.claudeCodeWorked(at: Date)`.

- [ ] **Step 1: Write the failing tests (Review Focus 5)**

Create `Tests/ClaudeDockCoreTests/ClaudeCodeActivityTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeDockCore

@Suite(.serialized) struct ClaudeCodeActivityTests {
    /// Counts reports from the watcher's queue.
    final class Reports: @unchecked Sendable {
        private let lock = NSLock()
        private var times: [Date] = []
        func add(_ time: Date) { lock.withLock { times.append(time) } }
        var count: Int { lock.withLock { times.count } }
    }

    /// A fresh `projects` folder with one project in it, like `~/.claude/projects`.
    func makeProjects() throws -> URL {
        let projects = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeDockActivity-\(UUID().uuidString)/projects")
        try FileManager.default.createDirectory(at: projects.appendingPathComponent("-Users-ash-pallet-town"),
                                                withIntermediateDirectories: true)
        return projects
    }

    func wait(for reports: Reports, atLeast count: Int, seconds: Double) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if reports.count >= count { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return reports.count >= count
    }

    @Test func aTranscriptWriteIsActivity() async throws {
        let projects = try makeProjects()
        let reports = Reports()
        let watcher = ClaudeCodeActivity(folder: projects) { reports.add($0) }
        watcher.start()
        defer {
            watcher.stop()
            try? FileManager.default.removeItem(at: projects.deletingLastPathComponent())
        }
        try await Task.sleep(for: .milliseconds(300))
        try Data("{}\n".utf8).write(to: projects.appendingPathComponent("-Users-ash-pallet-town/session.jsonl"))
        #expect(await wait(for: reports, atLeast: 1, seconds: 5))
    }

    @Test func otherFilesAreNot() async throws {
        let projects = try makeProjects()
        let reports = Reports()
        let watcher = ClaudeCodeActivity(folder: projects) { reports.add($0) }
        watcher.start()
        defer {
            watcher.stop()
            try? FileManager.default.removeItem(at: projects.deletingLastPathComponent())
        }
        try await Task.sleep(for: .milliseconds(300))
        try Data("notes".utf8).write(to: projects.appendingPathComponent("-Users-ash-pallet-town/notes.txt"))
        #expect(await !wait(for: reports, atLeast: 1, seconds: 2.5))
    }

    // Someone who has never run Claude Code has no ~/.claude/projects.
    @Test func aMissingFolderIsQuiet() {
        let watcher = ClaudeCodeActivity(folder: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/projects")) { _ in }
        watcher.start()
        watcher.stop()
    }
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./test.sh --filter ClaudeCodeActivityTests`
Expected: build failure, `cannot find 'ClaudeCodeActivity' in scope`.

- [ ] **Step 3: Implement the watcher**

Create `Sources/ClaudeDockCore/ClaudeCodeActivity.swift`:

```swift
import CoreServices
import Foundation

/// Notices Claude Code working: while it runs it appends to its transcripts in
/// `~/.claude/projects` every few seconds. Watches that folder with FSEvents and reports only
/// *that* a transcript changed, and when. It never opens the files.
public final class ClaudeCodeActivity: @unchecked Sendable {
    public let folder: URL
    private let onActivity: @Sendable (Date) -> Void
    private let queue = DispatchQueue(label: "ClaudeDock.ClaudeCodeActivity")
    private var stream: FSEventStreamRef?

    public init(folder: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects"),
                onActivity: @escaping @Sendable (Date) -> Void) {
        self.folder = folder
        self.onActivity = onActivity
    }

    deinit { stop() }

    /// Starts watching. A folder that doesn't exist (Claude Code never ran) reports nothing.
    public func start() {
        guard stream == nil else { return }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<ClaudeCodeActivity>.fromOpaque(info).takeUnretainedValue()
            let changed = Unmanaged<NSArray>.fromOpaque(paths).takeUnretainedValue() as? [String] ?? []
            if changed.contains(where: { $0.hasSuffix(".jsonl") }) { watcher.onActivity(Date()) }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        // Up to a second's latency: FSEvents batches a busy second's writes into one report.
        guard let stream = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
```

- [ ] **Step 4: Run to verify they pass**

Run: `./test.sh --filter ClaudeCodeActivityTests`
Expected: 3 tests pass (the first two take a few seconds).

- [ ] **Step 5: Tell the model, without redrawing on every write**

In `Sources/ClaudeDock/AppModel.swift`, add after `private var settingsChanges`:

```swift
    private var claudeCodeQuietCheck: Timer?
```

and after `func setClaudeCodeOrg(_:)`:

```swift
    /// Claude Code wrote a transcript. Publishes only when that starts its org's in-use
    /// effect (writes come every second or so while it works); a check just after the quiet
    /// period ends the effect on time.
    func claudeCodeWorked(at time: Date) {
        guard !showingDemo else { return }
        let wasWorking = claudeCodeActiveAt.map { time.timeIntervalSince($0) < InUse.claudeCodeQuiet } ?? false
        claudeCodeActiveAt = time
        if !wasWorking { now = time }
        claudeCodeQuietCheck?.invalidate()
        claudeCodeQuietCheck = Timer.scheduledTimer(withTimeInterval: InUse.claudeCodeQuiet + 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }
```

- [ ] **Step 6: Start the watcher**

In `Sources/ClaudeDock/AppDelegate.swift`, add a property after `private var clock: Timer?`:

```swift
    private var claudeCodeActivity: ClaudeCodeActivity?
```

and in `applicationDidFinishLaunching`, after the `clock = Timer.scheduledTimer(...)` block:

```swift
        claudeCodeActivity = ClaudeCodeActivity { [weak self] time in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.model.claudeCodeWorked(at: time) } }
        }
        claudeCodeActivity?.start()
```

- [ ] **Step 7: Watch it live with the owner**

Run `./build.sh && open "build/Claude Dock.app"` (demo mode off). This Claude Code session is writing transcripts, so the org Claude Code is signed into must show particles within about 2 s. Then measure CPU while Claude Code keeps working:

```bash
top -l 6 -s 1 -stats pid,command,cpu | grep -i claudedock
```
Expected: under 2%. This confirms the widget doesn't redraw on every write (Review Focus 5). Ask the owner to check that the particles stop about 60 s after Claude Code goes quiet (after this turn ends), and that a desktop-app chat on the primary org brings particles there within one 3-minute poll.

- [ ] **Step 8: Commit**

```bash
git add Sources/ClaudeDockCore/ClaudeCodeActivity.swift Sources/ClaudeDock/AppModel.swift Sources/ClaudeDock/AppDelegate.swift Tests/ClaudeDockCoreTests/ClaudeCodeActivityTests.swift
git commit -m "Notice Claude Code working from its transcript writes, without opening them

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: README, screenshots and manual checks

**Files:**
- Modify: `README.md`
- Modify: `docs/manual-checks.md`
- Modify: `Sources/ClaudeDock/Showcase.swift` (a compact scene)
- Modify: `docs/images/*.jpg` (regenerated), create `docs/images/compact.jpg`
- Modify: `docs/superpowers/specs/2026-10-07-compact-widget-design.md` (status line)

- [ ] **Step 1: Add a compact scene to `--showcase`**

In `Showcase.render`, after the `vertical.png` line, add:

```swift
        write(CompactScene(model: main), size: CGSize(width: 1180, height: 330), scheme: .dark, to: dir, "compact.png")
```

and add this view next to `DesktopScene`:

```swift
/// The bottom-right of a desktop twice: the compact widget beside the Dock, and the full
/// widget it grows to when the pointer rests on it.
private struct CompactScene: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Wallpaper(dark: true)
            VStack(spacing: 40) {
                row(compact: true)
                row(compact: false)
            }
            .padding(.vertical, 30)
        }
    }

    private func row(compact: Bool) -> some View {
        ZStack {
            FakeDock()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, -160)
            WidgetView(model: model, actions: .none, compact: compact).fixedSize()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
        }
    }
}
```

- [ ] **Step 2: Regenerate the README's images**

Run:
```bash
swift build && S=${TMPDIR:-/tmp}/claudedock-showcase && rm -rf $S && \
.build/debug/ClaudeDock --showcase $S && \
for f in hero-dark hero-light states panel-dark panel-light vertical compact; do sips -s format jpeg -s formatOptions 85 "$S/$f.png" --out "docs/images/$f.jpg" >/dev/null; done && \
sips -s format jpeg -s formatOptions 85 -Z 1280 "$S/social-card.png" --out docs/images/social-card.jpg >/dev/null && \
sips -g pixelWidth -g pixelHeight docs/images/*.jpg
```
Expected: every image the same size as before (hero 2360×1640, states 2200×1520, panels 1040×1800, vertical 2000×1640, social card 1280×640), plus compact 2360×660. Open each changed image with the Read tool and check it: no pulse ring on any dot, the states captions match, and compact.jpg shows the compact widget above the full one. `live-widget.jpg` is a real screen capture and can't be regenerated: leave it.

- [ ] **Step 3: Update the README**

Make these edits in `README.md`:

1. In **Reading the widget**, replace the **Dot** row with:
   `| **Dot** | 🟢 **use it**: at your current pace tokens would go unused at reset · 🟡 **on pace** · 🔴 **nearly out** |`
   and add after the **Caption** row:
   `| **Particles** | The org is in use right now: Claude Code is working on it, or its usage went up at the last reading (which also catches the desktop app, up to 3 minutes late). |`
2. After the paragraph that ends "VoiceOver reads the same).", add:

   ```markdown
   **Small until you need it.** The widget starts compact: each org's ring, name and 5-hour
   line. Rest the pointer on it and it grows into the full widget, over the Dock if it has
   to; move away and it shrinks back. Click it for the panel either way.

   <p align="center">
     <img src="docs/images/compact.jpg" alt="The compact widget beside the Dock, and the full widget it grows to on hover" width="880">
   </p>
   ```
3. In **Put it anywhere**, replace the last paragraph with:

   ```markdown
   Right-click it for **Position** (any corner or side), **Layout** (automatic, horizontal or
   vertical), **Size** (Small, Match Dock, Large, Extra large), **Shrink until hovered** (on
   by default) and **In-use effect** (Sparks, Flow, Shimmer or Off, and Subtle, Normal or
   Lots), or pinch on your trackpad over it to resize freely.
   ```
4. In **How it decides**, replace the 🟢 row with `| 🟢 | 5% or more would go unused |`.
5. In **Privacy**, after the `~/.claude.json` line, add:
   `- It watches \`~/.claude/projects\` for changes, to know when Claude Code is working. It never opens those files.`

- [ ] **Step 4: Add the manual checks**

Append to `docs/manual-checks.md`, before `## When things go wrong`:

```markdown
## Compact and in use

- [ ] Hover grows the widget and leaving shrinks it, with another app in front, over a
      full-screen app, on every Position, and in the vertical strip.
- [ ] Expanded beside the Dock, it draws over the Dock.
- [ ] Click: the panel opens against the expanded widget, which stays expanded until the
      panel closes.
- [ ] Reduce Motion: the widget only crossfades, and an org in use shows a still glow.
- [ ] Claude Code working: particles on its org within about 2 s, gone about 60 s after it
      stops.
- [ ] A desktop-app chat on the primary org: particles there within one poll (3 minutes).
- [ ] Each In-use effect and amount: Activity Monitor shows Claude Dock near 0% CPU.
```

- [ ] **Step 5: Mark the spec implemented**

In `docs/superpowers/specs/2026-10-07-compact-widget-design.md`, change the status line to `Status: approved and implemented (plan: docs/superpowers/plans/2026-10-07-compact-widget.md).`

- [ ] **Step 6: Commit**

```bash
git add README.md docs/manual-checks.md docs/images Sources/ClaudeDock/Showcase.swift docs/superpowers/specs/2026-10-07-compact-widget-design.md
git commit -m "Document the compact widget and the in-use effect; refresh the screenshots

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Final check

- [ ] **Step 1: Everything builds and passes**

Run: `./test.sh 2>&1 | tail -3 && ./build.sh 2>&1 | tail -2`
Expected: `Test run with N tests ... passed` (about 155), and `Built build/Claude Dock.app`.

- [ ] **Step 2: Privacy sweep of the branch**

Run: `git diff main --stat && git diff main | grep -inE "@|org_|[0-9a-f]{8}-[0-9a-f]{4}-" | grep -v "Co-Authored-By\|noreply@anthropic" | head`
Expected: no email addresses, real org names or real IDs (UUID-shaped strings only in the existing `00000000-...` fixtures).

- [ ] **Step 3: Review the whole branch**

Use superpowers:requesting-code-review for the branch against `main`, fix what it finds, then use superpowers:finishing-a-development-branch.
