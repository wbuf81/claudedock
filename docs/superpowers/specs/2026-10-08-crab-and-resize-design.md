# Crab and drag-to-resize: design

Date: 2026-10-08. Status: approved in brainstorming, awaiting spec review.

## Goal

The compact widget is the size the owner wants to live with. Hover growth gets in the way,
and the particles say *that* Claude Code is working but not *what* it's doing:

1. **No hover growth.** The owner resizes the widget between compact and full by dragging
   its inner edge. Clicking still opens the card.
2. **The crab.** An animated pixel crab perches on the widget above the org Claude Code is
   signed into and acts out what Claude Code is doing: idle, thinking, using a tool,
   waiting for permission, done.

Examples use the repository's Pokémon orgs: **Pikachu** (primary) and **Charizard**
(overflow). Mockups are in the gitignored `.superpowers/brainstorm/` (`crab-a-and-f.html`,
variant A2).

## Part 1: Widget size

### Hover is gone

- The pointer resting on the widget no longer grows it. `NSTrackingArea` hover tracking,
  the 0.25 s and 0.4 s delays and the "re-check the pointer after a frame change" logic are
  removed.
- The widget shows one size at a time: **Compact** or **Full**, the owner's choice.
- Opening the card no longer grows the widget. The card opens against the widget's
  current frame (`WidgetPlacement.panelFrame`, as today).

### Drag the inner edge to resize

- The **inner edge** is the edge facing the middle of the screen: the left edge when the
  widget's centre is in the right half, the right edge when in the left half. In the
  vertical strip it is the inner side edge too. The other edges don't resize.
- A 6 pt strip along that edge shows the resize cursor (`NSCursor.resizeLeftRight`) on
  hover and starts a resize drag instead of a move drag.
- While dragging, the window frame follows the pointer between the compact width and the
  full width (the fixed corner from `WidgetPlacement.anchor` stays put), and the compact
  and full views crossfade by how far along it is (alpha = progress). Both views stay laid
  out at their own sizes and pinned to the fixed corner, as the current growth animation
  does, so SwiftUI does not re-lay them out per pointer move.
- On release it snaps to the nearer size with the existing 0.22 s ease-out frame animation
  and crossfade, and saves the choice. With **Reduce Motion**: no frame animation, 0.2 s
  crossfade.
- Full is wider and also taller in the vertical strip; the drag only tracks the width.
  Height follows progress the same way.
- Window level: the full widget beside the Dock still draws over it (one level above the
  Dock), as the expanded widget does today. Compact stays `.floating`.

### Menu and setting

- **Size** menu gets a section: **Compact** / **Full** (checkmarks). It sets the same value
  as the drag. "Shrink until hovered" is removed.
- Setting `compact: Bool` keeps its key and meaning (true = Compact). Existing installs
  keep their value.
- Move drags (anywhere but the inner edge), snapping and the saved spot all use the frame
  of the size shown now. Placement is computed for that size, as today's compact frame is.

## Part 2: The crab

### Look and placement (variant A2)

- Sprites: `Resources/crab/<mood>/00…23.png`, 96×96 px RGBA, 24 frames at 70 ms (1.68 s
  loop), for `idle`, `thinking`, `tool`, `permission`, `done`. (`unknown` in the owner's
  folder is a copy of `idle` and is not shipped.) The owner confirmed they are free to
  publish under the repo's MIT license.
- Size: 50k pt square (k = the widget's content scale), drawn smoothly scaled.
- **Perched, sitting low:** centred horizontally on the active org's ring, the sprite's top
  58% above the widget's top edge and the rest overlapping the glass, drawn over the ring's
  top. It sticks up about 22k pt above the widget, about half of a standing crab.
- In the **full** widget it sits the same way above that org's ring.
- At a **top** snap point or a free spot in the upper half: mirrored vertically in
  placement (not in drawing), so it hangs under the widget's bottom edge.
- In the **vertical strip** on a screen side: beside the org's ring, overlapping the strip's
  inner edge by the same 42%.
- The window gets a clear band on the crab's side, tall (or wide) enough for the sprite.
  It is fully transparent outside the sprite, so the window server passes clicks there to
  the window behind (as it does for any non-opaque borderless window's clear pixels). Placement (`WidgetPlacement.origin`,
  snapping, saved spot) keeps using the glass's frame; the band is added outside it, and
  the band is clipped to the screen's visible frame.
- The **stoplight dot stays** on the compact and full widget, unchanged.
- **Reduce Motion:** the crab shows frame 0 of its mood and never animates.
- Renders (`--render`, `--showcase`): frame 0 of the mood, so README images can show it.

### Moods

| Claude Code | Mood |
|---|---|
| The owner sent a prompt; a tool finished | `thinking` |
| A tool started | `tool` |
| A permission prompt is showing | `permission` |
| Claude finished its turn | `done`, for 10 s, then `idle` |
| Session open, nothing happening | `idle` |

- One crab, on the org `~/.claude.json` names (as today's in-use signal). With several live
  sessions, it shows the most urgent mood: `permission` > `tool` > `thinking` > `done` >
  `idle`.
- The crab shows while at least one session is live. No live session, no crab.
- A session is live while its Claude Code process exists (`kill(pid, 0) == 0`, or `EPERM`)
  and its state file is under 12 hours old. Files of dead sessions are deleted when seen.
- A mood other than `idle` that hasn't changed for 10 minutes falls back to `idle` (a
  missed hook, a killed session).
- No crab while the widget is stale (signed out, or no reading for 10 minutes), matching
  the particles.

### Where moods come from: Claude Dock's hooks

Right-click ▸ **Connect to Claude Code…** adds hooks to `~/.claude/settings.json` after a
confirmation that says what will be added. **Disconnect from Claude Code** removes exactly
those entries. Both are idempotent.

Each hook is one `/bin/sh` command with no other dependency, for example (PreToolUse):

```sh
cat >/dev/null; d="$HOME/Library/Application Support/ClaudeDock/sessions"; mkdir -p "$d" && printf 'tool %s\n' "$(date +%s)" > "$d/$PPID.$$.tmp" && mv -f "$d/$PPID.$$.tmp" "$d/$PPID" || true # claude-dock
```

- `$PPID` is the Claude Code process that ran the hook: it names the session file and is the
  liveness check. The command never reads the hook's JSON (it drains stdin) and never
  touches transcripts.
- Events: `UserPromptSubmit` → thinking, `PreToolUse` (matcher `*`) → tool, `PostToolUse`
  (matcher `*`) → thinking, `Notification` (matcher `permission_prompt`) → permission,
  `PermissionRequest` (matcher `*`) → permission, `Stop` → done, `SessionStart` → idle,
  `SessionEnd` → deletes the file.
- Our entries are recognised by a marker in the command (`# claude-dock`), not by position.
  Other hooks (for example another status app's) are left exactly as they were, including
  the order of other entries. Unknown keys in `settings.json` are preserved. The file is
  written atomically and keeps a one-time backup at `settings.json.claude-dock-backup`
  before the first change.
- If `settings.json` doesn't parse, Connect refuses and says so; nothing is written.
- The menu item shows **Connect** or **Disconnect** from whether our marker is present
  (read when the menu opens).

**Not connected:** the crab still appears, from today's folder watch: `tool` while a
transcript changed in the last 60 s, then `done` for 10 s, then no crab. No `thinking`,
`permission` or `idle`.

Claude Dock watches its `sessions` folder with FSEvents (file-level, about 0.3 s latency)
and re-reads the few small files on each change.

### Particles

The in-use particles (Sparks, Flow, Shimmer, Off, amounts) stay, but only for the "usage
rose" signal (desktop app or browser). An org that shows the crab doesn't also get
particles for Claude Code activity.

### Menu

After Size:

- **Show the crab** (checkmark, on by default; setting `showCrab: Bool`)
- **Connect to Claude Code…** / **Disconnect from Claude Code**
- **In-use effect** ▸ as today, its subtitle in the README now "desktop app and browser use"

## Architecture

**`ClaudeDockCore`** (pure, unit-tested):

| Unit | Change |
|---|---|
| `Crab` (new) | `CrabMood` enum; `CrabSession` (pid, mood, time); `Crab.mood(sessions:isAlive:now:)` with priority, the 10 s done, the 10 min fallback; `Crab.parse(file:)` for `"<mood> <epoch>"` |
| `ClaudeCodeHooks` (new) | `install(into: [String: Any]) -> [String: Any]`, `remove(from:)`, `isInstalled(_:)`; the hook commands |
| `InUse` | unchanged; callers skip the Claude Code signal when the crab shows |
| `Placement` | `crabBand(glass:anchor:vertical:k:visible:)` for the perch band; drop nothing else (`expandedFrame` stays: it is the full frame for a given compact frame) |

**`ClaudeDock`** (app):

| Unit | Change |
|---|---|
| `DockController` | hover removed; inner-edge resize drag with live crossfade and snap; window frame = glass frame plus crab band; level by size |
| `WidgetContainer` | hit-test pass-through outside the glass; the edge strip's cursor rect |
| `CrabView` (new) | `NSViewRepresentable`: a `CALayer` whose `contents` runs a `CAKeyframeAnimation` over the 24 `CGImage`s (discrete, 1.68 s, repeat forever); swaps the frames when the mood changes; frame 0 with Reduce Motion |
| `CrabSprites` (new) | loads frames once from `Bundle.main` `crab/`, or from the repo's `Resources/crab` when run with `swift run` |
| `CrabSessions` (new) | FSEvents watcher on the sessions folder; publishes `[CrabSession]`; deletes dead sessions' files |
| `AppModel` | `crabMood(for:)`; a timer for the 10 s and 10 min edges |
| `WidgetView` | the crab overlay; menu items |
| `Settings` | `showCrab` |
| `build.sh` | copies `Resources/crab` into `Contents/Resources/crab` |
| `Renderer`, `Showcase` | a crab in demo scenarios |

## Testing

`swift test` (Core):

- `Crab.mood`: each event's mood; priority across three sessions; done → idle after 10 s;
  a stuck mood → idle after 10 min; dead pid ignored; file over 12 h ignored; bad file
  ignored; no sessions → nil.
- `ClaudeCodeHooks`: install into empty, into a file with Daisy-style hooks on the same
  events (theirs kept, in order), twice (no duplicates); remove restores the original
  dictionary exactly; `isInstalled`.
- `crabBand`: bottom and top snap points, both sides of the vertical strip, clipped to the
  visible frame.

Manual (added to `docs/manual-checks.md`):

- Drag-resize from every snap point and the vertical strip; the snap; Reduce Motion.
- Click opens the card at both sizes; the widget doesn't change size.
- Clicks in the clear band beside the crab reach the window behind.
- Connect: the confirmation, the moods within about a second, the `!` on a permission
  prompt. Disconnect right after Connect leaves `settings.json` byte-identical.
- Two sessions, one waiting for permission: the crab shows `!`.
- Activity Monitor: Claude Dock near 0% CPU while the crab animates.

## Docs

README: drag-to-resize, the crab and its moods, Connect/Disconnect, and in **Privacy**:
"Connecting adds hooks to `~/.claude/settings.json` that write only the event name and time
to a file per session. Claude Dock never reads your prompts or transcripts." New
screenshots from demo data.

## Out of scope

A crab per session; the desktop app's activity as crab moods; a crab on orgs Claude Code
isn't signed into; sound.

## Risks

- **`$PPID` isn't the Claude Code process** if a future Claude Code runs hooks through an
  extra shell. Then liveness fails and the crab disappears. The first implementation step
  checks it on this Mac; the fallback is the hook JSON's `session_id` via the app binary
  (`ClaudeDock --hook <event>`).
- **Hook formatting:** rewriting `settings.json` with `JSONSerialization` changes its
  whitespace and key order. Writes keep keys sorted and 2-space indentation; Disconnect
  restores from the backup when nothing else changed since Connect, so it is byte-identical.
- **Perch band and clicks:** if clear pixels don't pass clicks through reliably, the crab
  moves to a separate `ignoresMouseEvents` child window and the widget window keeps the
  glass's frame.
