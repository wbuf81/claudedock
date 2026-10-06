# Claude Dock: design

Date: 2026-10-06. Status: design approved in brainstorming, awaiting spec review.

## Goal

A glanceable, always-on macOS widget that shows how much of each Claude plan's usage
limits are used, so the owner can:

1. use each week's allowance fully before it resets (no unused tokens),
2. keep the org that the Claude desktop app depends on from running dry, and
3. know which org Claude Code should be signed into right now.

## Context

One person, one Mac, one claude.ai login that belongs to two Claude Team orgs:

- **Primary org**: used all the time by the Claude desktop app, and by Claude Code.
- **Overflow org**: used only for extra Claude Code capacity. The owner switches
  Claude Code between the two with `/login`.

Any other org on the login (for example a free personal org) is hidden by default.
Which org is primary and which is overflow is set in Settings and stored locally. No
org names, IDs or account details appear in this repository.

Examples in this repository (tests, demo mode, docs) use Pokémon names for orgs:
**Pikachu** is the primary org and **Charizard** the overflow org.

Each org has a 5-hour session limit, a weekly limit, and sometimes a model-specific
weekly limit (for example "Fable"). Each org's week resets at its own day and time.

## What the owner sees

### Corner widget (always visible)

- Borderless, 60 pt tall (Dock height), in the bottom-right corner of the main screen.
  With the Dock at the bottom it sits beside the Dock (6 pt above the screen's bottom
  edge, 12 pt from the right); otherwise it sits 12 pt inside the visible frame, so a
  side Dock is never covered. Shows on every Space, including full-screen apps. Never
  takes keyboard focus. Floats above normal windows.
- One block per org, primary first:
  - **Week ring**: fill = % of the week's limit used; a white tick = % of the week that
    has elapsed; the used % in the center.
  - **Name and stoplight dot** (rules below).
  - **5-hour bar**: fill = % of the current 5-hour window used; a white tick = how far
    into the window we are in time. Subline: `5h: 1% used · 12m in`, or `5h idle` when no
    window is open, or `back Wed 9 PM` when the org is red.
  - A red org also gets a red ring and a red-tinted block.
- **Switch tab** on the left edge, only when there is switch advice, for example
  `⇄ Overflow first` (using the org's real name at runtime).
- Click opens the panel. Right-click menu: Refresh now, Hide for 1 hour, Settings…,
  Sign out, Quit.
- **Stale state**: if the newest reading is older than 10 minutes, or the session is
  signed out, the widget greys out and the panel shows `as of 10:42 AM` and a Sign in
  button. The app never shows guessed numbers as live.

### Panel (click the widget)

Opens directly above the widget; closes on click outside or Esc. Everything is shown
as **used**, matching the widget.

- Header: `AI usage · week of Mon Oct 5` and the time of the newest reading.
- Status line: the switch advice with its reason, or
  `Claude Code is on <org>, the right place right now.`
- Per org:
  - Name, stoplight dot, role chip (`Desktop app + Claude Code` or `Extra Claude Code`),
    and `Claude Code is here` on the org Claude Code is signed into.
  - Large `55% used`, then `62% of the week gone · resets Fri 4 AM`.
  - **Week chart** on a shared Monday-to-Sunday calendar axis, so both orgs' days line
    up. Today's column is shaded and labelled TODAY, with a white "now" line.
    - Past: the real reading history. Before history exists, a straight line from the
      window start (0%) to now, which is the average so far.
    - Future: a dashed **use-it-all** line reaching 100% exactly at reset, and a dotted
      **your pace** line. The gap between them at reset is filled amber: tokens that
      would go unused.
    - Each org's reset is marked `↺ Fri 4 AM` where it falls; the line drops to 0% there
      and a faint line shows the next window at use-it-all pace.
    - A small legend under the first chart.
  - **TODAY box**: `Use about 9% more by midnight (to ~64% used), then about 17% a day.`
    plus `▲ At your current ~13% a day, about 11% goes unused on Fri 4 AM.` when that
    applies. A red org shows `Only 5% left until Wed 9 PM, about 7 hours at your recent
    pace.`
  - One bar per model-specific weekly limit (for example Fable): fill = used, tick = % of
    week elapsed.
  - 5-hour bar: fill = used, tick = time elapsed, and its reset time.
- Follows system light/dark mode. Reduce Motion turns off the pulse.

## Data

### Source: claude.ai, read-only

The app hosts a `WKWebView` with its own persistent website data store. On first launch
it shows a small window with the claude.ai sign-in page; the owner signs in once. All
requests run as `fetch()` inside that page (same origin, cookies included) via
`callAsyncJavaScript`, which avoids bot protection that blocks plain HTTP clients.

- `GET /api/organizations`: list of `{uuid, name, capabilities, rate_limit_tier,
  billing_type}`. Default orgs to show: those with a non-null `billing_type`. Settings can
  change the selection and roles. Re-read daily and after sign-in.
- `GET /api/organizations/{uuid}/usage`: use `limits[]`, each
  `{kind: session | weekly_all | weekly_scoped, percent, severity, resets_at,
  scope.model.display_name}`. If `limits` is missing, fall back to
  `five_hour.utilization/resets_at` and `seven_day.utilization/resets_at`. A session with
  `resets_at: null` means no 5-hour window is open. A weekly limit with
  `resets_at: null` means the week hasn't started: nothing used, no forecast, and a
  steady (not pulsing) green dot.
- Cadence: every 3 minutes; on panel open when the newest reading is over 30 seconds old;
  immediately on wake from sleep. On errors, back off 3 → 6 → 12 → 15 minutes.
- A 401 or 403, or a redirect to the login page, means signed out.
- The app only issues GET requests. It never sends chats, changes settings, or touches
  extra-usage credits.

### Which org Claude Code is signed into

Read `oauthAccount.organizationUuid` from `~/.claude.json` (only that field) at every
reading and whenever the file changes. If it can't be read, the app gives no switch
advice and omits `Claude Code is here`.

### Stored locally

- `~/Library/Application Support/ClaudeDock/history.jsonl`: one line per org per reading:
  `{t, org, session, sessionResetsAt, week, weekResetsAt, scoped: {model: percent}}`, where
  `org` is the org's UUID. Kept 35 days, pruned at launch. No names, cookies or tokens.
- Settings in `UserDefaults`: org selection and roles, thresholds, notification toggles,
  demo mode.
- The claude.ai session lives only in the app's website data store. Sign out deletes
  that store's claude.ai data.

## Rules

For each org's current week window: `U` = % used now; `H` = hours until reset;
`elapsed` = hours since the window started (reset time minus 7 days).

- **Pace `R`** (% per hour): `(U − U₇₂) / 72`, where `U₇₂` is the reading nearest to
  72 hours ago. If the window started less than 72 hours ago, or no reading that old
  exists, `R = U / elapsed`.
- **Forecast at reset** `F = min(100, U + R·H)`. **Would go unused** `W = 100 − F`.
- **Runs out early by** `H − (100 − U) / R` hours when `R·H > 100 − U`.
- **Use-it-all rate** `A = (100 − U) / H`. Per day `24·A`. **By midnight** `A ×` hours
  until local midnight (capped at `H`).

### Stoplight (first match wins)

| Dot | Condition |
|---|---|
| Red | under 10% of the week left; or runs out 12+ hours early; or 5-hour window ≥ 95% used |
| Yellow | 5-hour window ≥ 80% used; or `W < 5` (on pace); or runs out under 12 hours early |
| Green | otherwise (`W ≥ 5`): pulses every 2.8 s when `W < 10`, 1.6 s when `W` is 10–25, 0.9 s above 25 |

### Switch advice

- An org is **eligible** for Claude Code when it has at least 10% of the week left and
  its 5-hour window is under 80% used. The primary org also needs at least 15% of the week
  left, to keep a buffer for the desktop app.
- The **best** org is the eligible org whose week resets soonest. Ties go to the overflow
  org.
- Advice is shown only when a best org exists and it is not the org Claude Code is signed
  into. With no eligible org, the status line says which org comes back first.
- Reason text, for example: `<primary> 5h at 82%, desktop app needs room`,
  `<overflow> has 30% expiring Wed 9 PM`, `<org> is nearly out`.
- No flip-flopping: advice must be the same in two consecutive readings before it shows,
  and the app won't advise switching back within 60 minutes of the last advice unless the
  current org is red.

### Notifications

A macOS notification when switch advice appears, and when the org Claude Code is
signed into turns red. Once per change. Clicking one opens the panel. Each is a toggle in
Settings, and every threshold above is adjustable there.

## Architecture

A Swift package, macOS 14 or later, two targets:

**`ClaudeDockCore`** (library; no AppKit or WebKit, so it is fully unit-testable):

| Unit | Responsibility |
|---|---|
| `Models` | `Org`, `Limit`, `Reading`, `Role` |
| `UsageParser` | claude.ai JSON → `Reading`; tolerant of missing fields; throws on unusable input |
| `HistoryStore` | append, load and prune `history.jsonl`; injectable file URL and clock |
| `Pace` | pace, forecast, unused, run-out, use-it-all, by-midnight |
| `Stoplight` | state and pulse speed from a reading, pace and thresholds |
| `SwitchAdvisor` | best org, reason text, debounce and 60-minute hold |
| `WeekAxis` | Mon–Sun calendar mapping, today band, midnights, reset markers (DST-aware) |
| `Formatting` | `Fri 4 AM`, `in 1d 10h`, `12m in` |

**`ClaudeDock`** (the app):

| Unit | Responsibility |
|---|---|
| `AppDelegate` | lifecycle, menu-bar-less app (`LSUIElement`), launch at login via `SMAppService` |
| `WidgetWindow` + `WidgetView` | non-activating `NSPanel`, all Spaces, bottom-right placement, SwiftUI content |
| `PanelWindow` + `PanelView` | the expanded panel and its charts (SwiftUI shapes) |
| `ClaudeWebSession` | sign-in window, hidden fetcher web view, `fetch()` calls, signed-out detection |
| `Poller` | 3-minute timer, wake handling, backoff; turns responses into readings |
| `ClaudeCodeAccount` | reads and watches the org field in `~/.claude.json` |
| `Notifier` | user notifications |
| `SettingsView` | roles, thresholds, toggles, demo mode, sign out |
| `DemoData` | canned readings that cycle green, yellow, red and switch states |

`build.sh` builds a universal release binary, assembles `build/Claude Dock.app` with its
`Info.plist`, and ad-hoc signs it.

## Testing

`swift test` covers `ClaudeDockCore`:

- `UsageParser`: a fixture shaped like a real response with IDs replaced by
  `00000000-0000-4000-8000-00000000000N` and names by `Pikachu` / `Charizard`; the fallback shape
  without `limits`; a session with `resets_at: null`; malformed input.
- `Pace`: worked example U = 55, 103.4 h elapsed, H = 64.6 → about 16.7% a day to use it
  all, about 10.8% unused at the current pace, about 8.7% more by midnight at 11:32 AM.
- `Stoplight`: every threshold edge, and the pulse buckets.
- `SwitchAdvisor`: overflow at 5% → no advice; primary 5-hour window at 85% with overflow
  at 40% → overflow; overflow expiring sooner with 30% left → overflow; debounce; the
  60-minute hold and its red override.
- `WeekAxis`: Monday-to-Sunday mapping, and the week containing the Nov 1, 2026 daylight
  saving change (169 hours).
- `HistoryStore`: append, prune past 35 days, skip a corrupt line.

The app is checked by running it: live data, demo mode cycling every state, and a
screenshot review of the widget and panel.

## Out of scope for v1

OpenAI and Codex; switching accounts for the owner; extra-usage credits; a Claude Code
status-line fallback data source; Homebrew packaging; choosing a display other than the
main one.

## Risks

- The claude.ai endpoints are internal and undocumented and may change. The parser is
  tolerant, and failures show the stale state rather than wrong numbers.
- The stored claude.ai session grants full access to the account. It stays in the app's
  own website data store, the app only issues GET requests, and Sign out deletes it.
- The account is a work account; its owner should confirm this use fits their employer's
  policy.
