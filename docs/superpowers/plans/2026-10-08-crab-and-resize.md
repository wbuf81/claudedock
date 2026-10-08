# Crab and Drag-to-Resize Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hover growth with an inner-edge resize drag, and perch an animated crab on the org Claude Code is signed into that acts out Claude Code's state from hooks Claude Dock installs.

**Architecture:** Pure logic (crab moods, hook merge/unmerge and the settings-file round trip, crab band geometry, compact-from-full frame) lives in `ClaudeDockCore` with Swift Testing tests. The app adds a sessions-folder watcher, a Core Animation sprite view, a SwiftUI overlay that puts the crab above the active ring inside a transparent band of the widget window, and a `DockController` that shows one size at a time and resizes by dragging the inner edge.

**Tech Stack:** Swift 6 toolchain in Swift 5 language mode, SwiftPM, SwiftUI + AppKit, Core Animation, FSEvents, Swift Testing (`import Testing`). macOS 14+.

**Spec:** `docs/superpowers/specs/2026-10-08-crab-and-resize-design.md`

## Global Constraints

- The repo is **public**: no real org names, employer, emails, org IDs or `/Users/<name>/` paths in code, tests, docs or commit messages. Example orgs are **Pikachu** (primary) and **Charizard** (overflow). Hooks in `.githooks/` enforce this; never bypass them with `--no-verify`.
- Committing PNGs is blocked by the hooks until a person has looked at them. The owner approved the crab sprites; commit them with `CLAUDEDOCK_ALLOW_MEDIA=1 git commit …` **only** in Task 1.
- Tests: `./test.sh` (wraps `swift test`, loads the Testing plugin with only the Command Line Tools). Build the app: `./build.sh` → `build/Claude Dock.app`.
- Swift language mode 5 (see `Package.swift`). macOS 14 minimum. No new package dependencies.
- Comment density and style: short doc comments in plain English on every type and non-obvious function, like the existing files. Copy in the UI is sentence case.
- Crab: sprites 96×96 px, 24 frames, 70 ms per frame (1.68 s loop); moods `idle`, `thinking`, `tool`, `permission`, `done`; drawn at `50 * k` pt where `k = model.widgetScale`; perched with its top 58% outside the glass (`crabDepth = 29 * k`).
- Mood priority: `permission` > `tool` > `thinking` > `done` > `idle`. `done` lasts 10 s, then `idle`. Any non-idle, non-done mood unchanged for 10 min becomes `idle`. Session files older than 12 h are ignored.
- Hook marker: every command Claude Dock adds ends with `# claude-dock`. Sessions folder: `~/Library/Application Support/ClaudeDock/sessions/`, one file per Claude Code process id containing `"<mood> <unix seconds>\n"`.
- Verified on this Mac (2026-10-08): inside a hook command, `$PPID` is the `claude` process and stays the same for every event of a session.
- Commit messages: imperative sentence, no prefix (match `git log`), ending with the attribution line `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>` (or the implementing model's own line).

## Review Focus

- **`settings.json` with comments, trailing commas or an empty file:** Connect must refuse with a readable message and write nothing (empty file counts as `{}`). → test in Task 3.
- **Hooks already present on the same events (another status app):** Connect keeps them in order and Disconnect leaves them byte-for-byte. → test in Task 3.
- **A session killed with `kill -9` (no `SessionEnd`):** its file must stop counting once the pid is gone, even if the file says `permission`. → test in Task 2.
- **Pid reuse after a reboot:** a stale file whose pid now belongs to another process must expire by age (12 h) rather than show forever. → test in Task 2.
- **Resizing while the card is open, or starting a move drag on the inner edge:** the edge strip must win only within its 6 pt; the card follows the new frame. → manual check in Task 8 (listed in `docs/manual-checks.md`).

---

## File Structure

| File | Responsibility |
|---|---|
| `Resources/crab/<mood>/NN.png` (create, moved from `assets/crab`) | Sprite frames, shipped in the app |
| `Sources/ClaudeDockCore/Crab.swift` (create) | `CrabMood`, `CrabSession`, mood rules |
| `Sources/ClaudeDockCore/ClaudeCodeHooks.swift` (create) | Hook commands; merge into / remove from a settings dictionary |
| `Sources/ClaudeDockCore/ClaudeCodeHookFile.swift` (create) | Connect/disconnect against `settings.json` on disk with backup |
| `Sources/ClaudeDockCore/Placement.swift` (modify) | `CrabEdge`, `crabEdge`, `withCrabBand`, `compactFrame(full:…)` |
| `Sources/ClaudeDock/CrabSprites.swift` (create) | Loads frames as `CGImage`s once |
| `Sources/ClaudeDock/CrabView.swift` (create) | Sprite animation layer; still frame for Reduce Motion and renders |
| `Sources/ClaudeDock/CrabSessions.swift` (create) | Watches the sessions folder; reports live sessions |
| `Sources/ClaudeDock/AppModel.swift` (modify) | Sessions, connection state, `crabMood(for:)`, timers, demo crab |
| `Sources/ClaudeDock/WidgetView.swift` (modify) | Ring anchors, crab overlay, band padding, menu |
| `Sources/ClaudeDock/WidgetContainer.swift` (modify) | Edge handle for resizing; hover removed |
| `Sources/ClaudeDock/DockController.swift` (modify) | One size at a time, resize drag, crab band in the window frame |
| `Sources/ClaudeDock/Settings.swift`, `Components.swift`, `AppDelegate.swift` (modify) | `showCrab`, actions, wiring |
| `Sources/ClaudeDock/DemoData.swift`, `Renderer.swift` (modify) | Demo crab moods |
| `build.sh` (modify) | Copy `Resources/crab` into the app |
| `README.md`, `docs/manual-checks.md` (modify) | Docs |

---

### Task 1: Ship the sprites and load them

**Files:**
- Create: `Resources/crab/{idle,thinking,tool,permission,done}/00.png … 23.png` (moved from `assets/crab/…`)
- Create: `Sources/ClaudeDock/CrabSprites.swift`
- Modify: `build.sh` (after the `Info.plist` heredoc, before `codesign`)

**Interfaces:**
- Produces: `enum CrabSprites { static func frames(_ mood: CrabMood) -> [CGImage] }` (empty array if missing). `CrabMood` comes from Task 2; to keep this task self-contained, this task takes a `String` instead: `static func frames(_ mood: String) -> [CGImage]`. Task 6 calls it with `mood.rawValue`.

- [ ] **Step 1: Move the frames.** `assets/` is untracked. Keep only the five moods (`unknown` is a copy of `idle`; `meta.json` isn't needed: 24 frames, 70 ms are constants).

```bash
mkdir -p Resources/crab
for m in idle thinking tool permission done; do mkdir -p Resources/crab/$m && cp assets/crab/$m/*.png Resources/crab/$m/; done
ls Resources/crab/*/ | grep -c png   # expect 120
```

- [ ] **Step 2: Write `Sources/ClaudeDock/CrabSprites.swift`.**

```swift
import AppKit

/// The crab's animation frames, read once from the app bundle (`Contents/Resources/crab`), or
/// from the repo's `Resources/crab` when run with `swift run` from the repo.
@MainActor
enum CrabSprites {
    static let frameCount = 24
    static let frameDuration: CFTimeInterval = 0.07

    private static var cache: [String: [CGImage]] = [:]

    static func frames(_ mood: String) -> [CGImage] {
        if let cached = cache[mood] { return cached }
        let loaded = (0..<frameCount).compactMap { index -> CGImage? in
            let name = String(format: "%02d.png", index)
            guard let folder = folder?.appendingPathComponent(mood),
                  let image = NSImage(contentsOf: folder.appendingPathComponent(name)) else { return nil }
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        cache[mood] = loaded.count == frameCount ? loaded : []
        return cache[mood]!
    }

    private static let folder: URL? = {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("crab"),
           FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/crab")
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }()
}
```

- [ ] **Step 3: Copy the sprites in `build.sh`.** Insert right before the line starting with `codesign --force`:

```bash
# The crab's animation frames.
mkdir -p "$APP/Contents/Resources"
cp -R Resources/crab "$APP/Contents/Resources/crab"
```

- [ ] **Step 4: Build and check.**

Run: `./build.sh && ls "build/Claude Dock.app/Contents/Resources/crab/tool" | wc -l`
Expected: build succeeds, `24`.

- [ ] **Step 5: Commit.** The owner viewed every frame and approved publishing them.

```bash
git add Resources/crab Sources/ClaudeDock/CrabSprites.swift build.sh
CLAUDEDOCK_ALLOW_MEDIA=1 git commit -m "Ship the crab's animation frames in the app

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Crab moods (Core)

**Files:**
- Create: `Sources/ClaudeDockCore/Crab.swift`
- Test: `Tests/ClaudeDockCoreTests/CrabTests.swift`

**Interfaces:**
- Produces:
  - `public enum CrabMood: String, CaseIterable, Sendable { case idle, thinking, tool, permission, done }` with `public var urgency: Int`
  - `public struct CrabSession: Equatable, Sendable { public var pid: Int32; public var mood: CrabMood; public var time: Date }`
  - `public enum Crab` with `doneLasts`, `stuckAfter`, `fileExpires`, `parse(_:pid:)`, `mood(_:isAlive:now:)`, `nextChange(_:now:)`, `fallbackMood(claudeCodeActiveAt:now:)`

- [ ] **Step 1: Write the failing tests** in `Tests/ClaudeDockCoreTests/CrabTests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify it fails.** Run: `./test.sh --filter CrabTests` → Expected: compile error, `cannot find 'Crab' in scope`.

- [ ] **Step 3: Write `Sources/ClaudeDockCore/Crab.swift`.**

```swift
import Foundation

/// What the crab acts out: what Claude Code is doing in a session.
public enum CrabMood: String, CaseIterable, Sendable {
    case idle, thinking, tool, permission, done

    /// With several sessions the crab shows the most urgent one.
    public var urgency: Int {
        switch self {
        case .permission: 4
        case .tool: 3
        case .thinking: 2
        case .done: 1
        case .idle: 0
        }
    }
}

/// One Claude Code session's last hook event: its process, the mood the event means, and when.
public struct CrabSession: Equatable, Sendable {
    public var pid: Int32
    public var mood: CrabMood
    public var time: Date

    public init(pid: Int32, mood: CrabMood, time: Date) {
        self.pid = pid
        self.mood = mood
        self.time = time
    }
}

/// Turns Claude Code's sessions into the crab's one mood.
public enum Crab {
    /// "Done" plays this long, then the crab rests.
    public static let doneLasts: TimeInterval = 10
    /// A working mood that hasn't changed this long was probably missed (a hook that didn't
    /// run, a killed session): rest.
    public static let stuckAfter: TimeInterval = 600
    /// Files older than this are ignored: after a reboot their pid may belong to anything.
    public static let fileExpires: TimeInterval = 12 * 3600

    /// Reads a session file: `"<mood> <unix seconds>"`.
    public static func parse(_ text: String, pid: Int32) -> CrabSession? {
        let parts = text.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, let mood = CrabMood(rawValue: String(parts[0])),
              let seconds = TimeInterval(parts[1]) else { return nil }
        return CrabSession(pid: pid, mood: mood, time: Date(timeIntervalSince1970: seconds))
    }

    /// The crab's mood for these sessions, or nil when none is live.
    public static func mood(_ sessions: [CrabSession], isAlive: (Int32) -> Bool, now: Date) -> CrabMood? {
        sessions
            .filter { now.timeIntervalSince($0.time) < fileExpires && isAlive($0.pid) }
            .map { current($0, now: now) }
            .max { $0.urgency < $1.urgency }
    }

    /// When the mood next changes with no new event (a "done" ending, a stuck mood resting),
    /// so the widget can redraw then.
    public static func nextChange(_ sessions: [CrabSession], now: Date) -> Date? {
        sessions.compactMap { session -> Date? in
            let edge: TimeInterval
            switch session.mood {
            case .idle: return nil
            case .done: edge = doneLasts
            case .thinking, .tool, .permission: edge = stuckAfter
            }
            let at = session.time.addingTimeInterval(edge)
            return at > now ? at : nil
        }.min()
    }

    /// Without hooks: "tool" while Claude Code wrote a transcript in the last minute, then
    /// "done" for a moment, then no crab.
    public static func fallbackMood(claudeCodeActiveAt: Date?, now: Date) -> CrabMood? {
        guard let active = claudeCodeActiveAt else { return nil }
        let quiet = now.timeIntervalSince(active)
        if quiet < InUse.claudeCodeQuiet { return .tool }
        if quiet < InUse.claudeCodeQuiet + doneLasts { return .done }
        return nil
    }

    private static func current(_ session: CrabSession, now: Date) -> CrabMood {
        let age = now.timeIntervalSince(session.time)
        switch session.mood {
        case .done where age >= doneLasts: return .idle
        case .thinking, .tool, .permission: return age >= stuckAfter ? .idle : session.mood
        default: return session.mood
        }
    }
}
```

- [ ] **Step 4: Run tests.** Run: `./test.sh --filter CrabTests` → Expected: all pass. Then `./test.sh` → all pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/ClaudeDockCore/Crab.swift Tests/ClaudeDockCoreTests/CrabTests.swift
git commit -m "Work out the crab's mood from Claude Code's sessions

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Hooks in `settings.json` (Core)

**Files:**
- Create: `Sources/ClaudeDockCore/ClaudeCodeHooks.swift`, `Sources/ClaudeDockCore/ClaudeCodeHookFile.swift`
- Test: `Tests/ClaudeDockCoreTests/ClaudeCodeHooksTests.swift`

**Interfaces:**
- Produces:
  - `public enum ClaudeCodeHooks { static let marker: String; static func command(_ action: String) -> String; static func install(into: [String: Any]) -> [String: Any]; static func remove(from: [String: Any]) -> [String: Any]; static func isInstalled(_: [String: Any]) -> Bool }`
  - `public struct ClaudeCodeHookFile { init(settings: URL, support: URL); func isConnected() -> Bool; func connect() throws; func disconnect() throws }` and `public enum HookFileError: Error, Equatable { case unreadable(String) }`
  - `public static let defaultSupport: URL` on `ClaudeCodeHookFile` = `~/Library/Application Support/ClaudeDock`

Hook JSON shape (Claude Code): `{"hooks": {"<Event>": [ {"matcher": "<m>"?, "hooks": [ {"type": "command", "command": "<sh>"} ]} ]}}`.

Events and actions:

| Event | matcher | action written |
|---|---|---|
| `SessionStart` | — | `idle` |
| `UserPromptSubmit` | — | `thinking` |
| `PreToolUse` | `*` | `tool` |
| `PostToolUse` | `*` | `thinking` |
| `Notification` | `permission_prompt` | `permission` |
| `PermissionRequest` | `*` | `permission` |
| `Stop` | — | `done` |
| `SessionEnd` | — | `end` (deletes the file) |

- [ ] **Step 1: Write the failing tests** in `Tests/ClaudeDockCoreTests/ClaudeCodeHooksTests.swift`:

```swift
import Foundation
import Testing
@testable import ClaudeDockCore

@Suite struct ClaudeCodeHooksTests {
    /// Another status app's hooks on some of the same events.
    let theirs: [String: Any] = [
        "model": "opus",
        "hooks": [
            "Stop": [["hooks": [["type": "command", "command": "node other/update.js stop"]]]],
            "PreToolUse": [["matcher": "*", "hooks": [["type": "command", "command": "node other/update.js pre"]]]],
        ],
    ]

    func same(_ a: [String: Any], _ b: [String: Any]) -> Bool { NSDictionary(dictionary: a).isEqual(to: b) }

    @Test func commandsWriteOnlyTheMoodAndTime() {
        let tool = ClaudeCodeHooks.command("tool")
        #expect(tool.hasPrefix("cat >/dev/null;"))
        #expect(tool.contains("printf '%s %s\\n' tool"))
        #expect(tool.contains("$PPID"))
        #expect(tool.hasSuffix(ClaudeCodeHooks.marker))
        #expect(ClaudeCodeHooks.command("end").contains("rm -f"))
    }

    @Test func installsIntoNothing() {
        let installed = ClaudeCodeHooks.install(into: [:])
        let hooks = installed["hooks"] as! [String: Any]
        #expect(Set(hooks.keys) == ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                                     "Notification", "PermissionRequest", "Stop", "SessionEnd"])
        let notification = (hooks["Notification"] as! [[String: Any]])[0]
        #expect(notification["matcher"] as? String == "permission_prompt")
        #expect(ClaudeCodeHooks.isInstalled(installed))
        #expect(!ClaudeCodeHooks.isInstalled([:]))
    }

    // Review focus: other apps' hooks stay, in order, and come back untouched.
    @Test func keepsOtherHooksAndRemovesCleanly() {
        let installed = ClaudeCodeHooks.install(into: theirs)
        let stop = (installed["hooks"] as! [String: Any])["Stop"] as! [[String: Any]]
        #expect(stop.count == 2)
        #expect(((stop[0]["hooks"] as! [[String: Any]])[0]["command"] as? String) == "node other/update.js stop")
        #expect(installed["model"] as? String == "opus")
        #expect(same(ClaudeCodeHooks.remove(from: installed), theirs))
        #expect(same(ClaudeCodeHooks.remove(from: ClaudeCodeHooks.install(into: [:])), [:]))
    }

    @Test func installingTwiceAddsNothing() {
        let once = ClaudeCodeHooks.install(into: theirs)
        #expect(same(ClaudeCodeHooks.install(into: once), once))
    }

    // MARK: The file on disk

    func temp() -> (settings: URL, support: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir.appendingPathComponent("settings.json"), dir.appendingPathComponent("support"))
    }

    @Test func connectThenDisconnectIsByteIdentical() throws {
        let (settings, support) = temp()
        let original = Data("{\n    \"model\" : \"opus\",   \"hooks\": {}\n}\n".utf8)
        try original.write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        #expect(file.isConnected())
        try file.disconnect()
        #expect(!file.isConnected())
        #expect(try Data(contentsOf: settings) == original)
    }

    @Test func disconnectAfterOtherEditsKeepsThem() throws {
        let (settings, support) = temp()
        try Data("{}".utf8).write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        var edited = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        edited["model"] = "sonnet"
        try JSONSerialization.data(withJSONObject: edited).write(to: settings)
        try file.disconnect()
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        #expect(after["model"] as? String == "sonnet")
        #expect(!ClaudeCodeHooks.isInstalled(after))
    }

    @Test func missingOrEmptyFileCountsAsEmpty() throws {
        let (settings, support) = temp()
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        try file.connect()
        #expect(file.isConnected())
        try Data().write(to: settings)
        try file.connect()
        #expect(file.isConnected())
    }

    // Review focus: JSON with comments or trailing commas must not be overwritten.
    @Test func refusesAFileItCantRead() throws {
        let (settings, support) = temp()
        let original = Data("{ \"model\": \"opus\", // mine\n }".utf8)
        try original.write(to: settings)
        let file = ClaudeCodeHookFile(settings: settings, support: support)
        #expect(throws: HookFileError.self) { try file.connect() }
        #expect(try Data(contentsOf: settings) == original)
        #expect(!file.isConnected())
    }
}
```

- [ ] **Step 2: Run to verify it fails.** Run: `./test.sh --filter ClaudeCodeHooksTests` → Expected: compile error, `cannot find 'ClaudeCodeHooks' in scope`.

- [ ] **Step 3: Write `Sources/ClaudeDockCore/ClaudeCodeHooks.swift`.**

```swift
import Foundation

/// The hooks Claude Dock adds to Claude Code's settings so the crab knows what Claude Code is
/// doing. Each writes only a mood and the time to a file named after the Claude Code process
/// (`$PPID` inside a hook), and never reads the hook's input or any transcript.
public enum ClaudeCodeHooks {
    /// Marks our commands, so we find and remove exactly ours.
    public static let marker = "# claude-dock"

    /// (event, matcher, action) for every hook we add.
    static let events: [(event: String, matcher: String?, action: String)] = [
        ("SessionStart", nil, "idle"),
        ("UserPromptSubmit", nil, "thinking"),
        ("PreToolUse", "*", "tool"),
        ("PostToolUse", "*", "thinking"),
        ("Notification", "permission_prompt", "permission"),
        ("PermissionRequest", "*", "permission"),
        ("Stop", nil, "done"),
        ("SessionEnd", nil, "end"),
    ]

    /// The shell command for one action: a mood, or "end" to delete the session's file.
    public static func command(_ action: String) -> String {
        let folder = #"d="$HOME/Library/Application Support/ClaudeDock/sessions""#
        let body = action == "end"
            ? #"rm -f "$d/$PPID" || true"#
            : #"mkdir -p "$d" && printf '%s %s\n' \#(action) "$(date +%s)" > "$d/$PPID.$$.tmp" && mv -f "$d/$PPID.$$.tmp" "$d/$PPID" || true"#
        return "cat >/dev/null; \(folder); \(body) \(marker)"
    }

    public static func isInstalled(_ settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { groups in (groups as? [[String: Any]] ?? []).contains(where: isOurs) }
    }

    /// `settings` with our hooks added after any already there. Installing twice changes nothing.
    public static func install(into settings: [String: Any]) -> [String: Any] {
        var result = remove(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for entry in events {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command(entry.action)]]]
            if let matcher = entry.matcher { group["matcher"] = matcher }
            hooks[entry.event] = (hooks[entry.event] as? [[String: Any]] ?? []) + [group]
        }
        result["hooks"] = hooks
        return result
    }

    /// `settings` without our hooks; events and the "hooks" key we emptied are removed too.
    public static func remove(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        var result = settings
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]], groups.contains(where: isOurs) else { continue }
            let kept = groups.filter { !isOurs($0) }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        result["hooks"] = hooks.isEmpty && !((settings["hooks"] as? [String: Any])?.isEmpty ?? false) ? nil : hooks
        return result
    }

    private static func isOurs(_ group: [String: Any]) -> Bool {
        (group["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.hasSuffix(marker) == true }
    }
}
```

Note on `remove`: an originally empty `"hooks": {}` stays (the byte-identical test relies on the backup, not on this), but a `hooks` key that only held our entries is removed.

- [ ] **Step 4: Write `Sources/ClaudeDockCore/ClaudeCodeHookFile.swift`.**

```swift
import Foundation

public enum HookFileError: Error, Equatable {
    /// Claude Code's settings file isn't plain JSON (comments, trailing commas…): we leave it alone.
    case unreadable(String)
}

/// Connects and disconnects Claude Dock's hooks in `~/.claude/settings.json`. Before the first
/// change it keeps a backup, and remembers exactly what it wrote: disconnecting before anyone
/// else changed the file puts the original bytes back.
public struct ClaudeCodeHookFile: Sendable {
    public var settings: URL
    public var support: URL

    public static let defaultSettings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    public static let defaultSupport = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/ClaudeDock")

    public init(settings: URL = defaultSettings, support: URL = defaultSupport) {
        self.settings = settings
        self.support = support
    }

    private var backup: URL { support.appendingPathComponent("settings-before-connect.json") }
    private var written: URL { support.appendingPathComponent("settings-after-connect.json") }

    public func isConnected() -> Bool { (try? read()).map(ClaudeCodeHooks.isInstalled) ?? false }

    public func connect() throws {
        let before = (try? Data(contentsOf: settings)) ?? Data()
        let parsed = try read()
        guard !ClaudeCodeHooks.isInstalled(parsed) else { return }
        let after = try encode(ClaudeCodeHooks.install(into: parsed))
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try before.write(to: backup, options: .atomic)
        try after.write(to: written, options: .atomic)
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try after.write(to: settings, options: .atomic)
    }

    public func disconnect() throws {
        let current = (try? Data(contentsOf: settings)) ?? Data()
        if let mine = try? Data(contentsOf: written), mine == current, let original = try? Data(contentsOf: backup) {
            try original.write(to: settings, options: .atomic)
        } else {
            try encode(ClaudeCodeHooks.remove(from: try read())).write(to: settings, options: .atomic)
        }
        try? FileManager.default.removeItem(at: written)
        try? FileManager.default.removeItem(at: backup)
    }

    /// The settings as a dictionary; a missing or empty file is an empty one.
    private func read() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settings),
              !String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data), let dictionary = object as? [String: Any] else {
            throw HookFileError.unreadable("\(settings.lastPathComponent) isn't plain JSON, so Claude Dock left it alone.")
        }
        return dictionary
    }

    private func encode(_ dictionary: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}
```

- [ ] **Step 5: Run tests.** Run: `./test.sh --filter ClaudeCodeHooksTests` → all pass; then `./test.sh` → all pass. If `keepsOtherHooksAndRemovesCleanly` fails on the `[:]` case, check `remove`'s last line: a `hooks` key we created must be dropped.

- [ ] **Step 6: Commit.**

```bash
git add Sources/ClaudeDockCore/ClaudeCodeHooks.swift Sources/ClaudeDockCore/ClaudeCodeHookFile.swift Tests/ClaudeDockCoreTests/ClaudeCodeHooksTests.swift
git commit -m "Add and remove Claude Dock's hooks in Claude Code's settings

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Crab band and compact-from-full geometry (Core)

**Files:**
- Modify: `Sources/ClaudeDockCore/Placement.swift` (add after `GrowthAnchor`, and inside `enum WidgetPlacement`)
- Test: `Tests/ClaudeDockCoreTests/PlacementTests.swift` (append a suite)

**Interfaces:**
- Consumes: `GrowthAnchor` (`horizontal: .left/.right`, `vertical: .bottom/.top/.center`), `WidgetPlacement.expandedFrame`.
- Produces:
  - `public enum CrabEdge: Equatable, Sendable { case top, bottom, left, right }`
  - `WidgetPlacement.crabEdge(anchor: GrowthAnchor, vertical: Bool) -> CrabEdge`
  - `WidgetPlacement.withCrabBand(_ glass: CGRect, edge: CrabEdge, depth: Double) -> CGRect`
  - `WidgetPlacement.compactFrame(full: CGRect, size: CGSize, anchor: GrowthAnchor) -> CGRect` (the inverse of `expandedFrame`'s anchoring, without clamping)

- [ ] **Step 1: Write the failing tests** (append to `PlacementTests.swift`):

```swift
@Suite struct CrabBandTests {
    @Test func theCrabSitsOnTheSideFacingTheMiddle() {
        #expect(WidgetPlacement.crabEdge(anchor: GrowthAnchor(.right, .bottom), vertical: false) == .top)
        #expect(WidgetPlacement.crabEdge(anchor: GrowthAnchor(.left, .bottom), vertical: false) == .top)
        #expect(WidgetPlacement.crabEdge(anchor: GrowthAnchor(.right, .top), vertical: false) == .bottom)
        #expect(WidgetPlacement.crabEdge(anchor: GrowthAnchor(.right, .center), vertical: true) == .left)
        #expect(WidgetPlacement.crabEdge(anchor: GrowthAnchor(.left, .center), vertical: true) == .right)
        #expect(WidgetPlacement.crabEdge(anchor: GrowthAnchor(.right, .center), vertical: false) == .top)
    }

    @Test func theBandExtendsTheGlassOnThatSide() {
        let glass = CGRect(x: 100, y: 10, width: 150, height: 80)
        #expect(WidgetPlacement.withCrabBand(glass, edge: .top, depth: 29) == CGRect(x: 100, y: 10, width: 150, height: 109))
        #expect(WidgetPlacement.withCrabBand(glass, edge: .bottom, depth: 29) == CGRect(x: 100, y: -19, width: 150, height: 109))
        #expect(WidgetPlacement.withCrabBand(glass, edge: .left, depth: 29) == CGRect(x: 71, y: 10, width: 179, height: 80))
        #expect(WidgetPlacement.withCrabBand(glass, edge: .right, depth: 29) == CGRect(x: 100, y: 10, width: 179, height: 80))
        #expect(WidgetPlacement.withCrabBand(glass, edge: .top, depth: 0) == glass)
    }

    @Test func compactFrameUndoesTheGrowth() {
        let full = CGRect(x: 900, y: 20, width: 500, height: 80)
        #expect(WidgetPlacement.compactFrame(full: full, size: CGSize(width: 150, height: 80), anchor: GrowthAnchor(.right, .bottom))
                == CGRect(x: 1250, y: 20, width: 150, height: 80))
        #expect(WidgetPlacement.compactFrame(full: full, size: CGSize(width: 150, height: 80), anchor: GrowthAnchor(.left, .top))
                == CGRect(x: 900, y: 20, width: 150, height: 80))
        let strip = CGRect(x: 10, y: 300, width: 104, height: 400)
        #expect(WidgetPlacement.compactFrame(full: strip, size: CGSize(width: 68, height: 200), anchor: GrowthAnchor(.left, .center))
                == CGRect(x: 10, y: 400, width: 68, height: 200))
    }
}
```

If `GrowthAnchor`'s initializer isn't `GrowthAnchor(_:_:)`, read `Placement.swift:90-101` and match it (the existing `anchor(...)` builds it as `GrowthAnchor(horizontal, .center)`).

- [ ] **Step 2: Run to verify it fails.** Run: `./test.sh --filter CrabBandTests` → compile error, `CrabEdge` not found.

- [ ] **Step 3: Implement** in `Placement.swift`. After the `GrowthAnchor` struct:

```swift
/// The side of the widget the crab perches on: the one facing the middle of the screen.
public enum CrabEdge: Equatable, Sendable { case top, bottom, left, right }
```

Inside `enum WidgetPlacement`:

```swift
    /// Above the widget in the lower half, below it in the upper half; beside a vertical
    /// strip, on its inner side.
    public static func crabEdge(anchor: GrowthAnchor, vertical: Bool) -> CrabEdge {
        if vertical { return anchor.horizontal == .right ? .left : .right }
        return anchor.vertical == .top ? .bottom : .top
    }

    /// The window's frame: the glass plus a clear band `depth` deep on the crab's side.
    public static func withCrabBand(_ glass: CGRect, edge: CrabEdge, depth: Double) -> CGRect {
        switch edge {
        case .top: CGRect(x: glass.minX, y: glass.minY, width: glass.width, height: glass.height + depth)
        case .bottom: CGRect(x: glass.minX, y: glass.minY - depth, width: glass.width, height: glass.height + depth)
        case .left: CGRect(x: glass.minX - depth, y: glass.minY, width: glass.width + depth, height: glass.height)
        case .right: CGRect(x: glass.minX, y: glass.minY, width: glass.width + depth, height: glass.height)
        }
    }

    /// The compact frame that `full` grew out of from its anchored edges: where the widget is
    /// saved when the owner moves it while it's full size.
    public static func compactFrame(full: CGRect, size: CGSize, anchor: GrowthAnchor) -> CGRect {
        let x = anchor.horizontal == .right ? full.maxX - size.width : full.minX
        let y: Double
        switch anchor.vertical {
        case .bottom: y = full.minY
        case .top: y = full.maxY - size.height
        case .center: y = full.midY - size.height / 2
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
```

- [ ] **Step 4: Run tests.** `./test.sh` → all pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/ClaudeDockCore/Placement.swift Tests/ClaudeDockCoreTests/PlacementTests.swift
git commit -m "Place the crab's band and find the compact frame of a full widget

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Watch Claude Code's sessions, Connect and Disconnect

**Files:**
- Create: `Sources/ClaudeDock/CrabSessions.swift`
- Modify: `Sources/ClaudeDock/AppModel.swift`, `Sources/ClaudeDock/Settings.swift`, `Sources/ClaudeDock/AppDelegate.swift`, `Sources/ClaudeDock/Components.swift` (`WidgetActions`), `Sources/ClaudeDock/WidgetView.swift` (menu only)

**Interfaces:**
- Consumes: `Crab`, `CrabSession`, `CrabMood` (Task 2); `ClaudeCodeHookFile`, `HookFileError` (Task 3).
- Produces:
  - `final class CrabSessions { init(folder: URL = ClaudeCodeHookFile.defaultSupport.appendingPathComponent("sessions"), onChange: @escaping @Sendable ([CrabSession]) -> Void); func start(); func stop(); func reload() }`
  - `AppModel`: `@Published private(set) var crabSessions: [CrabSession]`, `@Published var hooksConnected: Bool`, `func sessionsChanged(_: [CrabSession])`, `func crabMood(for org: Org) -> CrabMood?`
  - `Settings.showCrab: Bool` (default true, key `"showCrab"`)
  - `WidgetActions.showCrab: (Bool) -> Void`, `WidgetActions.connectHooks: (Bool) -> Void`

- [ ] **Step 1: Write `Sources/ClaudeDock/CrabSessions.swift`.**

```swift
import CoreServices
import Foundation
import ClaudeDockCore

/// Reads the files Claude Dock's hooks write, one per Claude Code process, whenever one
/// changes. Files of processes that have exited are deleted.
final class CrabSessions: @unchecked Sendable {
    let folder: URL
    private let onChange: @Sendable ([CrabSession]) -> Void
    private let queue = DispatchQueue(label: "ClaudeDock.CrabSessions")
    private var stream: FSEventStreamRef?

    init(folder: URL = ClaudeCodeHookFile.defaultSupport.appendingPathComponent("sessions"),
         onChange: @escaping @Sendable ([CrabSession]) -> Void) {
        self.folder = folder
        self.onChange = onChange
    }

    deinit { stop() }

    func start() {
        guard stream == nil else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<CrabSessions>.fromOpaque(info).takeUnretainedValue().readNow()
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
        reload()
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    /// Reads the folder again (also used by a timer, since a process can exit without a write).
    func reload() { queue.async { self.readNow() } }

    private func readNow() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var sessions: [CrabSession] = []
        for name in names {
            guard let pid = Int32(name) else { continue }   // skips "<pid>.tmp"
            let url = folder.appendingPathComponent(name)
            guard Self.isAlive(pid) else { try? FileManager.default.removeItem(at: url); continue }
            if let text = try? String(contentsOf: url, encoding: .utf8), let session = Crab.parse(text, pid: pid) {
                sessions.append(session)
            }
        }
        onChange(sessions)
    }

    /// The process exists (EPERM means it exists but isn't ours).
    static func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno == EPERM }
}
```

- [ ] **Step 2: Add `showCrab` to `Settings.swift`.** After `effectAmount`'s declaration:

```swift
    /// The crab on the org Claude Code is signed into.
    @Published var showCrab: Bool { didSet { defaults.set(showCrab, forKey: "showCrab") } }
```

In `init`, after `effectAmount = …`: `showCrab = defaults.object(forKey: "showCrab") as? Bool ?? true`.

- [ ] **Step 3: Add the crab to `AppModel.swift`.**

Properties (after `claudeCodeActiveAt`):

```swift
    /// Live Claude Code sessions, from Claude Dock's hooks.
    @Published private(set) var crabSessions: [CrabSession] = []
    /// Claude Dock's hooks are in Claude Code's settings.
    @Published var hooksConnected = false
    /// The crab's mood in a demo scenario.
    private var demoCrab: CrabMood?
    private var crabCheck: Timer?
```

Methods (after `inUse(for:)`; and change `inUse(for:)` as shown):

```swift
    /// The crab on this org, or nil: it shows on the org Claude Code is signed into while a
    /// session is live (or, without hooks, while Claude Code is writing transcripts).
    func crabMood(for org: Org) -> CrabMood? {
        guard settings.showCrab, !isStale, org.id == claudeCodeOrg else { return nil }
        if showingDemo { return demoCrab }
        return hooksConnected
            ? Crab.mood(crabSessions, isAlive: CrabSessions.isAlive, now: now)
            : Crab.fallbackMood(claudeCodeActiveAt: claudeCodeActiveAt, now: now)
    }

    /// Whether an org is being used right now; it gets the in-use effect. Claude Code's own
    /// activity shows as the crab instead, so only a rise in usage counts on the crab's org.
    func inUse(for org: Org) -> Bool {
        InUse.isInUse(org: org.id, latest: latest[org.id], previous: previous[org.id], claudeCodeOrg: claudeCodeOrg,
                      claudeCodeActiveAt: crabMood(for: org) == nil ? claudeCodeActiveAt : nil, stale: isStale, now: now)
    }

    /// The hooks wrote, or the sessions were re-read. Redraws now and when the mood next
    /// changes by itself ("done" ending, a stuck mood resting).
    func sessionsChanged(_ sessions: [CrabSession]) {
        crabSessions = sessions
        now = Date()
        crabCheck?.invalidate()
        if let next = Crab.nextChange(sessions, now: now) {
            crabCheck = Timer.scheduledTimer(withTimeInterval: next.timeIntervalSince(now) + 0.2, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
    }
```

In `claudeCodeWorked(at:)`, the quiet check must also fire after the fallback "done": change its interval from `InUse.claudeCodeQuiet + 0.5` to `InUse.claudeCodeQuiet + Crab.doneLasts + 0.5`, and add a second one-shot timer at `InUse.claudeCodeQuiet + 0.5` (keep both in an array property `claudeCodeQuietChecks: [Timer]`, invalidating all on each call), so the crab switches tool → done → gone on time.

Demo: in `apply(_:)` add `demoCrab = scenario.crab`; in `leaveDemo()` add `demoCrab = nil`. (`DemoScenario.crab` is added in Task 8; until then add `var crab: CrabMood? = nil` to `DemoScenario` in `DemoData.swift` now so this compiles.)

- [ ] **Step 4: Menu actions.** In `Components.swift` `WidgetActions`, add:

```swift
    /// Shows or hides the crab.
    var showCrab: (Bool) -> Void = { _ in }
    /// Connects (true) or disconnects (false) Claude Dock's hooks.
    var connectHooks: (Bool) -> Void = { _ in }
```

In `WidgetView.menu`, after the `Size` menu (leave "Shrink until hovered" for Task 7):

```swift
        check("Show the crab", settings.showCrab) { actions.showCrab(!settings.showCrab) }
        Button(model.hooksConnected ? "Disconnect from Claude Code" : "Connect to Claude Code…") {
            actions.connectHooks(!model.hooksConnected)
        }
```

- [ ] **Step 5: Wire it in `AppDelegate.swift`.** Add a property `private var crabSessions: CrabSessions?` and `private let hookFile = ClaudeCodeHookFile()`. In the `WidgetActions(...)` call add:

```swift
            showCrab: { [weak self] in self?.model.settings.showCrab = $0 },
            connectHooks: { [weak self] in self?.setHooks($0) },
```

After `claudeCodeActivity?.start()`:

```swift
        model.hooksConnected = hookFile.isConnected()
        crabSessions = CrabSessions { [weak self] sessions in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.model.sessionsChanged(sessions) } }
        }
        crabSessions?.start()
```

In the existing 30 s `clock` timer closure, also call `self.crabSessions?.reload()` (catches sessions that exited without a hook).

Add:

```swift
    /// Adds or removes Claude Dock's hooks, after saying what Connect will change.
    private func setHooks(_ connect: Bool) {
        if connect {
            let alert = NSAlert()
            alert.messageText = "Connect to Claude Code?"
            alert.informativeText = """
                Claude Dock will add hooks to ~/.claude/settings.json. Each writes only what \
                Claude Code is doing (thinking, using a tool, waiting for you, done) and the time \
                to a file in Claude Dock's folder. Your prompts and transcripts are never read. \
                Your other hooks stay as they are. Disconnect removes them.
                """
            alert.addButton(withTitle: "Connect")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            try connect ? hookFile.connect() : hookFile.disconnect()
        } catch HookFileError.unreadable(let why) {
            let alert = NSAlert()
            alert.messageText = "Couldn't connect to Claude Code"
            alert.informativeText = why
            alert.runModal()
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
        model.hooksConnected = hookFile.isConnected()
        crabSessions?.reload()
    }
```

- [ ] **Step 6: Build and test.** Don't connect against the real `~/.claude/settings.json` here; the live check is Task 8 Step 5.

Run: `./test.sh && swift build`
Expected: tests pass, build succeeds.

- [ ] **Step 7: Commit.**

```bash
git add Sources/ClaudeDock
git commit -m "Read Claude Code's sessions from Claude Dock's hooks; connect and disconnect them

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Draw the crab on the widget

**Files:**
- Create: `Sources/ClaudeDock/CrabView.swift`
- Modify: `Sources/ClaudeDock/WidgetView.swift`, `Sources/ClaudeDock/AppModel.swift`

**Interfaces:**
- Consumes: `CrabSprites.frames(_ mood: String) -> [CGImage]`, `CrabSprites.frameDuration` (Task 1); `AppModel.crabMood(for:)` (Task 5); `CrabEdge` (Task 4); `RenderStyle` environment `\.renderStyle` (existing, `.live` when on screen).
- Produces:
  - `struct CrabView: View { var mood: CrabMood; var size: CGFloat }`
  - `AppModel`: `@Published var crabEdge: CrabEdge = .top`, `var crabDepth: CGFloat { settings.showCrab ? 29 * widgetScale : 0 }`, `var crabSize: CGFloat { 50 * widgetScale }`
  - `WidgetView` draws the glass inset by `crabDepth` on `crabEdge`; `DockController` (Task 7) relies on: the hosting view's `fittingSize` = glass size + `crabDepth` along the edge's axis.

- [ ] **Step 1: Write `Sources/ClaudeDock/CrabView.swift`.**

```swift
import AppKit
import SwiftUI
import ClaudeDockCore

/// The crab acting out a mood. Core Animation flips through the frames in the window server,
/// so the app does no work per frame. With Reduce Motion, and in image renders (which can't
/// draw Core Animation), it holds the mood's first frame.
struct CrabView: View {
    var mood: CrabMood
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.renderStyle) private var renderStyle

    var body: some View {
        Group {
            if reduceMotion || renderStyle != .live {
                if let first = CrabSprites.frames(mood.rawValue).first {
                    Image(decorative: first, scale: 1).resizable().interpolation(.high)
                }
            } else {
                CrabLayer(mood: mood)
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CrabLayer: NSViewRepresentable {
    var mood: CrabMood
    func makeNSView(context: Context) -> CrabLayerView { CrabLayerView() }
    func updateNSView(_ view: CrabLayerView, context: Context) { view.mood = mood }
}

final class CrabLayerView: NSView {
    private let sprite = CALayer()
    var mood: CrabMood? { didSet { if mood != oldValue { restart() } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        sprite.contentsGravity = .resizeAspect
        sprite.minificationFilter = .trilinear
        layer?.addSublayer(sprite)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sprite.frame = bounds
        CATransaction.commit()
    }

    private func restart() {
        sprite.removeAllAnimations()
        guard let mood else { return }
        let frames = CrabSprites.frames(mood.rawValue)
        sprite.contents = frames.first
        guard frames.count > 1 else { return }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames
        animation.calculationMode = .discrete
        animation.duration = CrabSprites.frameDuration * Double(frames.count)
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        sprite.add(animation, forKey: "frames")
    }
}
```

- [ ] **Step 2: Model geometry.** In `AppModel.swift` after `vertical`:

```swift
    /// The side the crab perches on; `DockController` sets it with the layout.
    @Published var crabEdge: CrabEdge = .top
    /// The crab's size, and how far it sticks out of the glass (its top 58%).
    var crabSize: CGFloat { 50 * widgetScale }
    var crabDepth: CGFloat { settings.showCrab ? crabSize * 0.58 : 0 }
```

- [ ] **Step 3: Mark the active ring and draw the crab in `WidgetView.swift`.**

Add at file scope:

```swift
/// The ring the crab perches on, in the widget's coordinates.
private struct CrabRingKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = value ?? nextValue() }
}

private extension View {
    /// Reports this ring's bounds when the crab sits on its org.
    func crabRing(_ on: Bool) -> some View {
        anchorPreference(key: CrabRingKey.self, value: .bounds) { on ? $0 : nil }
    }
}
```

In `OrgBlock.content`, append `.crabRing(model.crabMood(for: org) != nil)` to the `ring` expression (after `.inUseEffect(...)`). In `CompactOrg.body`, append the same modifier after the ring's `.overlay(alignment: .topTrailing) { … }`.

In `WidgetView.body`, change the `Group { … }` so the crab overlay and the band padding wrap the glass. Replace:

```swift
        Group {
            if compact && !model.orgs.isEmpty {
                if model.vertical { compactStrip } else { compactBar }
            } else {
                if model.vertical { strip } else { bar }
            }
        }
        .opacity(model.isStale ? 0.55 : 1)
        .contentShape(Rectangle())
```

with:

```swift
        Group {
            if compact && !model.orgs.isEmpty {
                if model.vertical { compactStrip } else { compactBar }
            } else {
                if model.vertical { strip } else { bar }
            }
        }
        .opacity(model.isStale ? 0.55 : 1)
        .contentShape(Rectangle())
        .overlayPreferenceValue(CrabRingKey.self) { anchor in crab(anchor) }
        .padding(crabPadding, model.crabDepth)
```

and keep the gestures and `.contextMenu` chained after it as they are. Add to `WidgetView`:

```swift
    private var crabPadding: Edge.Set {
        switch model.crabEdge {
        case .top: .top
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    /// The crab perched on the edge of the glass beside its ring: 58% of it outside the glass.
    @ViewBuilder
    private func crab(_ anchor: Anchor<CGRect>?) -> some View {
        if let anchor, let mood = model.orgs.lazy.compactMap({ model.crabMood(for: $0) }).first {
            GeometryReader { proxy in
                let ring = proxy[anchor], size = model.crabSize, out = size * 0.58
                let center: CGPoint = switch model.crabEdge {
                case .top: CGPoint(x: ring.midX, y: -out + size / 2)
                case .bottom: CGPoint(x: ring.midX, y: proxy.size.height + out - size / 2)
                case .left: CGPoint(x: -out + size / 2, y: ring.midY)
                case .right: CGPoint(x: proxy.size.width + out - size / 2, y: ring.midY)
                }
                CrabView(mood: mood, size: size).position(center)
            }
        }
    }
```

(The overlay's coordinate space is the glass, before the padding, so `-out` reaches into the band the padding adds.)

- [ ] **Step 4: Check with a render.** Task 8 adds demo crabs; for now run `swift build` and `./test.sh`. Expected: both pass. Run the app (`swift run ClaudeDock`) only if a quick look is wanted; the band isn't in the window frame until Task 7, so the crab may be clipped until then.

- [ ] **Step 5: Commit.**

```bash
git add Sources/ClaudeDock
git commit -m "Draw the crab perched over its org's ring

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: One size at a time, resize by dragging the inner edge

**Files:**
- Modify: `Sources/ClaudeDock/DockController.swift`, `Sources/ClaudeDock/WidgetContainer.swift`, `Sources/ClaudeDock/WidgetView.swift` (menu), `Sources/ClaudeDock/Components.swift`, `Sources/ClaudeDock/AppDelegate.swift`, `Sources/ClaudeDock/Settings.swift` (comment only)

**Interfaces:**
- Consumes: `WidgetPlacement.crabEdge`, `withCrabBand`, `compactFrame(full:size:anchor:)` (Task 4); `model.crabEdge`, `model.crabDepth` (Task 6).
- Produces: `DockController.setCompact(_ on: Bool)` keeps its name and now means "show compact (true) or full (false)". `WidgetContainer.onResize: ((ResizePhase) -> Void)?` with `enum ResizePhase { case began, moved(dx: CGFloat, dy: CGFloat), ended }`, and `WidgetContainer.handleFrame: NSRect`.

Behaviour to implement (spec Part 1):

1. **Remove hover.** Delete `WidgetContainer.onHover`, its tracking area, `mouseEntered/Exited`; in `DockController` delete `pointerInside`, `hoverWork`, `pointerMoved`, `recheckPointer`, `recheckPointerSoon` and their calls, and `collapseForDrag`. `expanded` becomes a computed `private var showingFull: Bool { !model.settings.compact }`.
2. **Frames.** In `layout()`, keep computing `compact` (glass) and `grown` (glass, via `expandedFrame`) as now, but from glass sizes: `glassSize(host) = host.fittingSize` minus `model.crabDepth` along the band's axis (height for `.top/.bottom`, width for `.left/.right`). Compute `edge = WidgetPlacement.crabEdge(anchor: anchor, vertical: model.vertical)` and set `model.crabEdge = edge` (return early like the existing scale changes if it changed, so the hosts re-measure). Window frames: `WidgetPlacement.withCrabBand(glass, edge: edge, depth: model.crabDepth)` for each size. Show the full one when `!settings.compact`.
3. **`arrange(in:)`** places each host at its window frame (glass + band), pinned to the anchor as now; the container's corner radius no longer applies to the window (the band is clear), so set `container.layer?.cornerRadius = 0` and clip only during animations by the glass shape is unnecessary: remove the `masksToBounds` toggling.
4. **Edge handle.** In `WidgetContainer` add a 6 pt wide subview `EdgeHandle` (an `NSView` with an `NSTrackingArea` `[.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .cursorUpdate]`, setting `NSCursor.resizeLeftRight` on enter/cursorUpdate and `NSCursor.arrow` on exit, and `mouseDown/mouseDragged/mouseUp` forwarding `onResize` with screen-coordinate deltas from `NSEvent.mouseLocation`). For a vertical strip (`edge` `.left/.right`) use `NSCursor.resizeLeftRight` too. `DockController.arrange` sets `container.handleFrame` to the glass's inner edge (the side facing the middle: left side when `anchor.horizontal == .right`, else right side), full glass height, in window coordinates, and adds the handle above the hosts.
5. **Resize drag.** In `DockController`:

```swift
    /// Where a resize drag started: the window frames of both sizes and the progress then.
    private var resizeStart: (compact: NSRect, full: NSRect, progress: CGFloat, pointer: NSPoint)?

    private func resize(_ phase: ResizePhase) {
        guard let frames else { return }
        let compactWindow = windowFrame(frames.compact), fullWindow = windowFrame(frames.full)
        switch phase {
        case .began:
            panelWasOpen = panel.isVisible
            resizeStart = (compactWindow, fullWindow, showingFull ? 1 : 0, NSEvent.mouseLocation)
            fullHost.isHidden = false
            compactHost.isHidden = false
            widget.level = Self.aboveDock
        case .moved:
            guard let start = resizeStart else { return }
            let span = max(start.full.width - start.compact.width, 1)
            // Pulling the inner edge toward the middle of the screen grows the widget.
            let pull = frames.anchor.horizontal == .right ? start.pointer.x - NSEvent.mouseLocation.x
                                                          : NSEvent.mouseLocation.x - start.pointer.x
            let progress = min(max(start.progress + pull / span, 0), 1)
            setResize(progress, compact: start.compact, full: start.full)
        case .ended:
            guard let start = resizeStart else { return }
            resizeStart = nil
            let progress = fullHost.alphaValue
            model.settings.compact = progress < 0.5   // triggers layout() via the settings sink
            animateSettle(from: lerp(start.compact, start.full, progress))
        }
    }

    private func setResize(_ progress: CGFloat, compact: NSRect, full: NSRect) {
        widget.setFrame(lerp(compact, full, progress), display: true)
        fullHost.alphaValue = progress
        compactHost.alphaValue = 1 - progress
        if panel.isVisible { placePanel() }
    }

    private func lerp(_ a: NSRect, _ b: NSRect, _ t: CGFloat) -> NSRect {
        NSRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }
```

   `animateSettle(from:)` reuses the body of today's `setExpanded`: animate the window frame to the chosen size's window frame over 0.22 s ease-out while the hosts' alpha go to 1/0 (Reduce Motion: no frame animation, set the frame first when growing and after when shrinking, 0.2 s crossfade), then `layout()`. `layout()` must not move the window while `resizeStart != nil` or `animating` (extend its existing `guard dragStart == nil, !animating`). The vertical strip resizes by width the same way; its height follows the same `lerp`.
6. **Card.** `openPanel()` no longer calls `setExpanded(true)`; `closePanel()` no longer re-checks the pointer. `placePanel()` uses the glass frame of the size shown (`showingFull ? frames.full : frames.compact`).
7. **Move drag.** `dragChanged()` no longer collapses. `dragEnded()` snaps using the glass frame (`widget.frame` minus the band: keep the current glass frame in a property `glassFrame` updated in `arrange`, and offset it by the drag). For a free spot while full, save the offset of `WidgetPlacement.compactFrame(full: glass, size: frames.compact.size, anchor: WidgetPlacement.anchor(compact: glass, visible: screen.visibleFrame, spot: nil))`, so the compact widget lands where the full one grew from.
8. **Window level.** `.floating` when compact; `Self.aboveDock` when full (as the expanded widget is today).
9. **`setCompact(_:)`**: sets the setting and animates to that size with `animateSettle(from: widget.frame)`. Rename nothing else.
10. **Menu.** In `WidgetView.menu`, replace `check("Shrink until hovered", …)` with, inside the existing `Menu("Size")` after a `Divider()`:

```swift
            Divider()
            check("Compact", settings.compact) { actions.compact(true) }
            check("Full", !settings.compact) { actions.compact(false) }
```

    Update the `WidgetActions.compact` doc comment to "Shows the compact (true) or full (false) widget." and `Settings.compact`'s to "Shows the compact widget (each org's ring, name and 5-hour line) instead of the full one." Update `DockController`'s and `WidgetView`'s type doc comments that mention hovering.

- [ ] **Step 1:** Make changes 1–3 and 8; `swift build`. Run `./build.sh && open "build/Claude Dock.app"`: compact widget shows, hovering does nothing, the crab (if Claude Code is running in this terminal and connected… not yet) — at least the widget sits where it did, not shifted by the band (bottom-right: the glass's bottom edge still at the same height as before this change).
- [ ] **Step 2:** Make changes 4–5. Rebuild and open. Drag the inner edge: it follows the pointer and crossfades; release past halfway snaps to full; back below halfway snaps to compact; the choice survives a relaunch.
- [ ] **Step 3:** Make changes 6, 7, 9, 10. Rebuild. Click opens the card without resizing; Size ▸ Compact/Full switch with the animation; a move drag at full size saves a spot that puts the compact widget under where its corner was.
- [ ] **Step 4:** `./test.sh` → all pass (the placement matrix must still pass; the hosts' band doesn't touch Core).
- [ ] **Step 5: Commit.**

```bash
git add Sources/ClaudeDock
git commit -m "Resize the widget by dragging its inner edge; drop hover growth

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Demo crabs, renders, docs, and the live check

**Files:**
- Modify: `Sources/ClaudeDock/DemoData.swift`, `README.md`, `docs/manual-checks.md`

**Interfaces:**
- Consumes: `DemoScenario.crab: CrabMood?` (added in Task 5), `Renderer.renderDemo`.

- [ ] **Step 1: Demo moods.** In `DemoData.scenarios`, the scenario created with `working: true` gets `crab: .tool`; add `crab: .permission` to one other scenario whose Claude Code org is Pikachu. Use the existing `scenario(...)` helper: extend it with a `crab: CrabMood? = nil` parameter passed to `DemoScenario(... crab: crab)`.
- [ ] **Step 2: Render.** Run: `swift run ClaudeDock --render /tmp/claudedock-render` (check `main.swift` for the exact flag if this differs). Open the `*-compact-dark.png` of the `tool` scenario: the crab's first frame sits on the top edge above Pikachu's ring, about half above the glass. Nothing is committed from `/tmp`.
- [ ] **Step 3: README.** In the widget section: drag the inner edge to resize (Size ▸ Compact / Full), click for the card, no hover. New section "The crab": what each mood means (idle, thinking, using a tool, waiting for you with the red !, done), that it sits on the org Claude Code is signed into, **Show the crab**, **Connect to Claude Code…** and what it adds, and that without connecting the crab only types and celebrates. In-use effect: now "desktop app and browser use". **Privacy**: "Connecting adds hooks to `~/.claude/settings.json` that write only the event name and time to a file per session in `~/Library/Application Support/ClaudeDock/sessions`. Claude Dock never reads your prompts or transcripts. Disconnect removes them, and puts the file back exactly as it was if nothing else changed it." Uninstall section: Disconnect first. Do not update screenshots in this task.
- [ ] **Step 4: Manual checks.** Append to `docs/manual-checks.md` a "Crab and resizing" section with these unchecked items:

```markdown
## Crab and resizing

- [ ] Drag the inner edge at every snap point and in the vertical strip: follows the pointer, snaps to the nearer size, remembered after relaunch. Reduce Motion: no frame animation.
- [ ] Starting a drag 7 pt or more inside the inner edge moves the widget instead of resizing it.
- [ ] Resize while the card is open: the card follows the widget.
- [ ] Click opens the card at both sizes; the widget doesn't change size.
- [ ] Clicks on the clear band beside the crab reach the window behind (a Terminal window reaching down to the Dock).
- [ ] Connect: the confirmation; `~/.claude/settings.json` gains entries ending in `# claude-dock`; other hooks unchanged. Disconnect right after: the file is byte-identical (`shasum` before and after).
- [ ] A Claude Code prompt: thinking, then tool while it runs a command, then done for about 10 s, then idle; all within about a second of each event.
- [ ] A permission prompt shows the red ! within a second.
- [ ] Two sessions, one waiting for permission: the crab shows the !.
- [ ] `kill -9` a session: its crab goes within 30 s.
- [ ] Not connected: the crab types while Claude Code works, celebrates, then leaves.
- [ ] Activity Monitor: Claude Dock near 0% CPU while the crab animates.
```

- [ ] **Step 5: Live check on this Mac** (the implementer reports results; the owner confirms):
  - `shasum ~/.claude/settings.json`, then **Connect**; `grep -c 'claude-dock' ~/.claude/settings.json` → 8.
  - In another terminal, run a short Claude Code prompt that runs one Bash command: watch thinking → tool → done → idle.
  - **Disconnect**; `shasum` matches the first one.
- [ ] **Step 6: Commit.**

```bash
git add Sources/ClaudeDock/DemoData.swift README.md docs/manual-checks.md
git commit -m "Document the crab and drag-to-resize; demo crabs for renders

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>"
```

---

## Spec deviations (decided while planning)

- A move drag at full size saves the spot of the compact frame the full one grows from (`compactFrame(full:…)`), so switching sizes never jumps the widget. The spec said placement uses "the frame of the size shown now"; this keeps the saved spot meaning one thing.
- The crab band is always part of the window while **Show the crab** is on (not only while a session is live), so the window doesn't change size when Claude Code starts or stops.
