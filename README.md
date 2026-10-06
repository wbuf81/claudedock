<h1 align="center">Claude Dock</h1>

<p align="center">
  <b>Your Claude plan usage, always in the corner of your screen.</b><br>
  A tiny Liquid Glass widget that sits beside the macOS Dock and shows, for every Claude
  organization you belong to, how much of this week and this 5-hour window you've used,
  and whether you should be using it right now.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-black?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white" alt="Swift 6">
  <img src="https://img.shields.io/badge/SwiftUI-Liquid%20Glass-0A84FF" alt="SwiftUI, Liquid Glass">
  <img src="https://img.shields.io/badge/tests-Swift%20Testing-34C759" alt="Tested with Swift Testing">
  <img src="https://img.shields.io/badge/dependencies-none-lightgrey" alt="No dependencies">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/hero-dark.jpg">
    <img src="docs/images/hero-light.jpg" alt="Claude Dock beside the macOS Dock, with its panel open above it" width="880">
  </picture>
</p>

<p align="center"><sub>All screenshots use the built-in demo data: Pikachu and Charizard are two Claude organizations.</sub></p>

## Why

If you have more than one Claude plan (say a team plan shared with the Claude desktop app,
and another you switch Claude Code to when the first runs low), it's hard to tell how much
is left in each, when each one resets, and whether you're about to waste tokens that expire
at the end of the week. Claude Dock answers that at a glance, without opening a browser.

## Reading the widget

<p align="center">
  <img src="docs/images/live-widget.jpg" alt="The widget on a real desktop, in clear Liquid Glass" width="560">
</p>

| | What it shows |
|---|---|
| **Ring** | How much of this week's limit is used. The **tick** on the ring is how much of the week has gone by: keep the fill up near the tick and nothing goes unused. |
| **Bar** | How much of the current **5-hour window** is used. Its tick is how far into the window you are. |
| **Dot** | 🟢 **use it**: at your current pace tokens would go unused at reset (it pulses faster the more would go to waste) · 🟡 **on pace** · 🔴 **nearly out** |
| **Caption** | `5h 19% · ↺ Fri 4 AM`: the 5-hour window's use, then when the week resets. |
| **⇄ tab** | Appears only when Claude Code should switch orgs, e.g. `Charizard first`. |

It's as tall as your Dock, its rings are the size of your Dock icons, and it uses the same
clear Liquid Glass, so it looks like part of the Dock.

## Every state

<p align="center">
  <img src="docs/images/states.jpg" alt="The widget in five situations, each explained" width="880">
</p>

## The panel

Click the widget for the detail: your week on a Monday-to-Sunday chart with **today**
highlighted, the pace that would use everything by reset against the pace you're on, the
**amber wedge** that would go unused, what to do today, the model-specific weekly limit, and
the 5-hour window. Both orgs share one calendar, so their days line up even though their
weeks reset at different times.

<table>
  <tr>
    <td><img src="docs/images/panel-dark.jpg" alt="The panel in dark mode"></td>
    <td><img src="docs/images/panel-light.jpg" alt="The panel in light mode"></td>
  </tr>
</table>

## How it decides

**Stoplight** (first match wins):

| Dot | When |
|---|---|
| 🔴 | under 10% of the week left, or on track to run out 12+ hours before reset, or the 5-hour window is 95%+ used |
| 🟡 | the 5-hour window is 80%+ used, or less than 5% would go unused, or running out slightly early |
| 🟢 | 5% or more would go unused. Pulses slowly under 10%, normally at 10–25%, fast above 25% |

**Switching orgs:** an org can take Claude Code when it has at least 10% of its week left and
its 5-hour window is under 80% used (the org shared with the desktop app also keeps a 15%
buffer). Of those, the one whose week resets soonest wins (use it before it expires). Advice
has to hold for two readings before it shows, and won't flip back within an hour unless the
org you're on turns red. Every threshold is adjustable in Settings.

"Your pace" is your usage over the last 3 days, so one heavy afternoon or a quiet weekend
doesn't swing the forecast.

## Install

Needs macOS 14 or later and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/wbuf81/claudedock.git
cd claudedock
./build.sh                      # builds build/Claude Dock.app (Apple Silicon + Intel)
open "build/Claude Dock.app"    # first launch asks you to sign in to claude.ai once
```

Then:

- **Click** the widget to open the panel; click anywhere else or press Esc to close it.
- **Drag** it anywhere; it remembers the spot. Right-click → **Snap back to corner** returns it.
- **Right-click** for Refresh now, Hide for 1 hour, Settings, Sign out and Quit.
- **Settings** picks which orgs to show and which one the desktop app shares, sets every
  threshold, toggles notifications, and has a **demo mode** with Pokémon sample data.

It launches at login, and sends a notification when Claude Code should switch orgs or when
the org it's on turns red.

## Privacy

- Claude Dock signs in to claude.ai in **its own private web view**, separate from your
  browsers and the Claude desktop app. Sign out in the menu deletes that session.
- It only **reads**: GET requests to claude.ai's usage endpoints every 3 minutes. It never
  sends chats, changes settings or touches billing.
- It reads **one field** from `~/.claude.json`: which org Claude Code is signed into.
- History stays on your Mac in `~/Library/Application Support/ClaudeDock/`, kept 35 days.
- No analytics, no other servers.

claude.ai's usage endpoints are not a public API and may change; if they do, the widget
greys out and shows when it last updated rather than guessing.

## Developing

```sh
./test.sh                                                   # unit tests (Swift Testing)
"build/Claude Dock.app/Contents/MacOS/ClaudeDock" --render DIR    # every demo state as PNGs
"build/Claude Dock.app/Contents/MacOS/ClaudeDock" --showcase DIR  # the README images
```

`ClaudeDockCore` holds all the logic (parsing, pace, stoplight, switch advice, chart
geometry, the on-screen sentences) as pure, tested Swift; `ClaudeDock` is the AppKit +
SwiftUI app around it. The design spec and implementation plan live in
[`docs/superpowers/`](docs/superpowers/). `test.sh` exists because, with only the Command
Line Tools installed, SwiftPM can't find the Swift Testing macro plugin on its own.

## Contributing safely

This repository is public. Hooks in `.githooks/` block commits and pushes that contain
secrets, real account or organization IDs, email addresses, home-folder paths, or any
word on your private list. After cloning, turn them on:

```sh
git config core.hooksPath .githooks
```

Put your own private words (employer, organization names, real IDs), one per line, in
`.git/info/sensitive-patterns`. That file lives inside `.git/`, so it is never committed.
Images and PDFs can't be scanned, so they are blocked until you have looked at them
and run the commit and the push with `CLAUDEDOCK_ALLOW_MEDIA=1`.
Install [gitleaks](https://github.com/gitleaks/gitleaks) for an extra secret scan; the
hooks use it when present. To audit everything already tracked:

```sh
.githooks/scan-sensitive.sh --all
```

Examples in this repository use Pokémon names for organizations, never real ones.

---

<sub>Claude Dock is an independent project, not affiliated with or endorsed by Anthropic.
Claude is a trademark of Anthropic, PBC.</sub>
