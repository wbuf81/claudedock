# Compact widget and in-use particles: design

Date: 2026-10-07. Status: design agreed in brainstorming (mockups in the visual companion),
awaiting spec review.

## Goal

The widget is too big to live beside the Dock all day. Make it small until you want the
detail, and make it show at a glance which org is being used right now:

1. **Compact widget**: each org shrinks to its week ring, its name and its 5-hour line.
   Hovering grows it to today's full widget; clicking still opens the panel.
2. **In-use particles**: an org that is being used right now gets a particle effect on its
   ring and 5-hour line. The stoplight dot stops pulsing.

Examples use the repository's Pokémon orgs: **Pikachu** (primary) and **Charizard**
(overflow).

## Part 1: Compact widget

### What it shows

Per org, stacked and centred, at scale `k` (the widget's existing content scale):

- **Week ring**, 44k pt (the full widget's is 48k): same fill, tick and percentage. Red
  when the org is red, as today.
- **Stoplight dot**, 9k pt, on the ring's top-right edge with a thin outline in the glass
  colour so it reads against the ring. Steady (see Part 2).
- **Name**, 10k pt semibold (never under 9 pt), one line, cut off with "…" at the column
  width (about 54k pt). The full name shows on hover.
- **5-hour line**, 46k × 4k pt: same fill and tick as today's 5-hour bar.

Columns are about 56k pt wide, 6k pt apart, with 10k pt of padding: about 150 pt for two
orgs at Dock height. No captions, no dividers.

- **Switch advice**: an amber strip (the switch tab's colour) with an amber ⇄, 26k pt wide
  on the widget's leading edge; in the vertical strip, a 24k pt band across the top. It
  carries the same accessibility sentence and tooltip as today's switch tab.
- **Vertical strip**: the same columns stacked, about 68k pt wide.
- **Placeholder** (sign in, loading, can't read usage): unchanged.
- **Stale and per-org problems**: the same dimming as today. The reason text is a caption,
  so it only shows when expanded.
- **VoiceOver**: each org is one element with today's summary sentence, the "Opens the
  details" hint and the default action, in both sizes.

### Hover, growth and click

- The pointer resting on the widget for **0.25 s** expands it to today's full layout. It
  collapses **0.4 s** after the pointer leaves.
- It grows out of its corner toward the middle of the screen, so the part under the
  pointer never moves away from it:
  - widget centre in the right half: right edge fixed; left half: left edge fixed;
  - lower half: bottom edge fixed; upper half: top edge fixed;
  - vertical strip on a side (`rightMiddle`, `leftMiddle`): vertical centre fixed.
  The expanded frame always contains the compact frame, stays on screen and stays below
  the menu bar.
- **Animation**: the window frame animates over 0.22 s (ease-out) while the compact and
  full views crossfade. Both views are laid out once at their own size and pinned to the
  fixed corner; the crossfade and frame change are Core Animation, so SwiftUI does not
  re-lay out the widget each frame. With **Reduce Motion**: no frame animation, a 0.2 s
  crossfade only.
- **Above the Dock**: the Dock draws over floating windows, so while expanded the widget's
  window level is one above the Dock's. It drops back to floating when it collapses. While
  expanded beside the Dock it covers part of the Dock until the pointer leaves.
- **Click** (compact or expanded) opens the panel as today, placed against the expanded
  frame. The widget stays expanded while the panel is open, and collapses when the panel
  closes if the pointer isn't over it.
- **Drag**: starting a drag collapses the widget immediately (no animation). The drag, the
  snap and the saved spot all use the compact frame.
- Hover is tracked with an `NSTrackingArea` that works while the app is inactive (the
  widget never becomes key). After any frame change the pointer position is re-checked, so
  a stale "inside" can't leave the widget stuck open.

### Placement and size

- The compact frame is placed exactly as today's widget, by `WidgetPlacement.origin`,
  using the compact size. Being smaller, it sits beside the Dock in more setups.
- The expanded frame comes from a new `WidgetPlacement.expandedFrame` (anchoring rules
  above).
- The owner's size (Size menu, pinch) scales both. The fit-on-screen check
  (`WidgetLayout.fittedScale`) uses the expanded size, so the expanded widget always fits.

### Turning it on and off

- Right-click menu: **Shrink until hovered** (checkmark), on by default for new installs
  and for existing ones after the update. Off gives today's always-full widget.

## Part 2: In-use particles

### What "in use" means

An org is **in use** when either is true:

1. **Claude Code is working on it**: Claude Code wrote to its transcripts in
   `~/.claude/projects/` within the last **60 s**, and `~/.claude.json` says it is
   signed into this org. The app watches that folder with FSEvents (file-level events,
   about 1 s latency) and records only *that* a `.jsonl` file changed. It never opens or
   reads those files.
2. **Its usage just rose**: compared with the org's previous reading (taken no more than
   10 minutes earlier), its 5-hour % or weekly % went up within the same window (reset
   times within 60 s of each other), or a new window already shows some use (windows open
   on first use). A reset to nothing is not a rise. It counts while the newest reading is
   under 4 minutes old. This catches the desktop app and claude.ai in a
   browser, up to one poll (3 minutes) late.

No particles while the widget is stale (signed out, or no reading for 10 minutes).

### The dot

The stoplight dot keeps its colours and meanings (green: tokens would go unused; yellow:
on pace; red: nearly out) but **no longer pulses**. A green, still ring is the nudge to
use that org. The pulse speeds and their two thresholds (`normalPulseUnused`,
`fastPulseUnused`) are removed from the stoplight and from Settings. Saved settings that
still contain them must keep loading.

### Styles and amounts

Chosen by the owner; one choice applies to every org. Each style covers both the ring and
the 5-hour line, compact and expanded:

- **Sparks**: a glint runs around the ring's filled arc and sparks shed off its tip; the
  5-hour line's tip glows and throws sparks like a lit fuse.
- **Flow** (default): specks of light stream along the filled part of the ring and the
  line.
- **Shimmer**: a soft light sweep runs along the ring and the line, and a few slow embers
  rise off the ring.
- **Off**: no in-use effect.

Amount: **Subtle** (0.5×), **Normal** (1×, default), **Lots** (1.8×), scaling birth rates
and speck counts.

With **Reduce Motion**, any style becomes a steady soft glow at the tip of the ring's fill
and of the 5-hour line: still visible, never moving.

### Drawing

Like today's pulse ring: `NSViewRepresentable` views holding Core Animation layers, so
the window server animates them and the app does no per-frame work. `CAEmitterLayer`
draws the sparks and embers, keyframe animations along the arc path draw the glint and
the Flow specks, and a gradient masked to the fill draws the line sweep. Effects follow
the ring's colour (accent, or red), stay inside the widget's bounds, and are added or
removed only when an org's in-use state, the style, the amount or the layout changes.
Image renders (`--render`, `--showcase`) can't draw these animations, so they show the
Reduce Motion glow.

## Part 3: Menu, settings, architecture, testing, docs

### Right-click menu

Added after Size:

- **Shrink until hovered** (checkmark)
- **In-use effect** ▸ Sparks, Flow, Shimmer, Off, a divider, then Subtle, Normal, Lots

### Settings (UserDefaults)

`compact: Bool` (default true), `effectStyle` (sparks, flow, shimmer, off; default flow),
`effectAmount` (subtle, normal, lots; default normal). Missing or unknown values fall back
to the defaults.

### Architecture

**`ClaudeDockCore`** (pure, unit-tested):

| Unit | Change |
|---|---|
| `Placement` | `WidgetPlacement.expandedFrame(compact:size:screen:visible:spot:)` with the anchoring rules |
| `Activity` (new) | `InUse.isInUse(org:latest:previous:claudeCodeOrg:claudeCodeActiveAt:stale:now:)` and the "rose" rule |
| `Stoplight` | green without a pulse speed; pulse thresholds removed |
| `Settings` types | `EffectStyle`, `EffectAmount` enums |

**`ClaudeDock`** (app):

| Unit | Change |
|---|---|
| `WidgetView` | a compact layout (`CompactOrg`) beside today's `OrgBlock`; the ⇄ badge |
| `DockController` | two hosting views (compact, full) in one container; hover tracking with delays; animated frame changes and crossfade; window level while expanded; drag collapses; layout measures both sizes |
| `ClaudeCodeActivity` (new) | FSEvents watcher on `~/.claude/projects`; publishes the time of the last `.jsonl` change |
| `AppModel` | `inUse(for:)` from `InUse`, the previous reading per org from `history`, and a re-check when the 60 s or 4 min windows run out |
| `Components` | `InUseEffect` (the three styles, amounts and the steady glow); `StoplightDot` loses `PulseRing` |
| `Settings`, `SettingsView` | the three new settings; the pulse thresholds removed |
| `Renderer`, `Showcase` | compact and expanded variants of every scenario; README images |

### Testing

`swift test` (Core):

- `expandedFrame`: each snap point and free spots in all four quadrants: the anchor rules,
  contains the compact frame, on screen, below the menu bar. The existing placement matrix
  (displays × Dock positions × icon sizes × Dock widths × 1–3 orgs × spots × sizes) gains
  the compact size and its expanded frame with the same assertions.
- `InUse`: Claude Code changed 59 s ago on this org → in use; 61 s → not; on the other org
  → not; 5-hour % up from the previous reading → in use while the reading is under 4
  minutes old, not after; a reset (lower %, new window) → not; no previous reading → not;
  stale → not.
- `Stoplight`: the existing threshold tests without pulse buckets.
- Settings decoding: a saved `thresholds` value that still has the two pulse fields loads.

The app is checked by running it: compact and expanded renders for every demo scenario in
light and dark, a demo scenario with one org in use, and the manual checks below.

### Docs

- **README**: the compact widget and hover, the new menu items, the dot no longer pulsing,
  the in-use effect and its two signals, and in **Privacy**: "It watches
  `~/.claude/projects` for changes to know when Claude Code is working. It never opens
  those files." New screenshots of the compact widget from the Pokémon demo data.
- **docs/manual-checks.md**, new items:
  - hover expands and collapses with the app inactive, over a full-screen app, on every
    snap point and in the vertical strip;
  - expanded beside the Dock draws over the Dock;
  - the panel opens against the expanded frame and the widget stays expanded until it
    closes;
  - Reduce Motion: no growth animation, steady glow;
  - Claude Code working: particles on its org within about 2 s, gone about 60 s after it
    stops;
  - desktop app use: particles on the primary org within one poll;
  - each style and amount: Activity Monitor shows Claude Dock near 0% CPU while particles
    run.

## Out of scope

A different effect per org; detecting the desktop app's activity locally; polling more
often while an org is in use; the Settings window showing the new options (the
right-click menu holds them, like Position, Layout and Size).

## Risks

- **Resize smoothness**: SwiftUI hosting views can stutter when the window frame animates.
  The first implementation step checks this on the real widget. If it stutters, growth
  falls back to the Reduce Motion behaviour (instant frame, crossfade).
- **Window level above the Dock**: if macOS draws it wrong (for example over full-screen
  transitions), the fallback is to raise the expanded frame above the Dock's band, as the
  panel does.
- **Claude Code's storage may change**: if transcripts move or change format, signal 1
  silently stops and signal 2 still works. A custom `CLAUDE_CONFIG_DIR` isn't followed,
  same as today's org lookup.
- **Sessions started before an org switch** keep using the old org, but signal 1 credits
  the org `~/.claude.json` names now. Signal 2 still shows the real one within a poll.
