# Manual checks

The unit tests cover the logic (parsing, pace, stoplight, advice, placement on 6 displays ×
4 Dock positions × 4 icon sizes × 4 Dock widths × 1–3 orgs × 7 spots × 6 sizes). These need
a real Mac, a real account, or a person. Tick what you checked and on what.

## Building

- [ ] macOS 14 or 15 with Xcode 16 (or its Command Line Tools): `./build.sh` and `./test.sh`
      both work; the widget has a frosted card instead of Liquid Glass.
- [ ] With full Xcode installed (not just the Command Line Tools), `./test.sh` runs every test.
- [ ] `./build.sh` while the app is running from `build/` quits it and reopens the new one.

## First launch

- [ ] From `/Applications`: one sign-in window, nothing else on top of it. The app appears in
      System Settings → General → Login Items.
- [ ] From `build/`: it does **not** add a login item.
- [ ] The notification permission prompt appears only with the first notification.

## Signing in

- [ ] Email: the emailed link, copied and opened with **Open copied sign-in link**, signs in.
- [ ] Google: the pop-up opens in its own window and signing in completes.
- [ ] Single sign-on (Okta or similar), if you have it.
- [ ] Right-click → **Sign out**, then sign in again with Google: it asks for the account again.
- [ ] Ending the session elsewhere (claude.ai → Settings → log out of all devices) brings a
      "Claude Dock was signed out" notification; clicking it opens sign-in.

## Accounts

- [ ] One paid org: no switch tab, no role chips, no "Shared with the desktop app" picker.
- [ ] Free account only: the widget shows the org, or says why it can't (for example
      "no weekly limit"), never "Loading usage…" for more than a minute.
- [ ] Enterprise account: its org is shown by default.
- [ ] Claude Code signed into an org that's turned off in Settings: the panel says so.
- [ ] Not using Claude Code at all: nothing claims it's on an org.

## Placement

- [ ] 13- or 14-inch laptop, Dock at the bottom, two orgs: the widget is beside the Dock or
      just above it, never under it. Repeat with two or three minimized windows.
- [ ] Dock on the left or right, and auto-hidden: the widget stays clear of it.
- [ ] Every right-click → **Position** spot, then drag back to the bottom right.
- [ ] Three orgs on a 13-inch screen: the panel scrolls and its corners stay rounded.
- [ ] A second display plugged in and out: the widget stays on the main display.

## Reading it

- [ ] Liquid Glass over a light wallpaper and a dark one: the text stays readable.
- [ ] Reduce Transparency and Increase Contrast (System Settings → Accessibility → Display):
      a frosted card instead of glass.
- [ ] VoiceOver: each org reads as one sentence; activating it opens the panel.
- [ ] Hovering an org shows the same sentence as a tooltip.
- [ ] A 24-hour region (System Settings → General → Language & Region): times read "16:00".
- [ ] Changing the time zone updates the times within a minute, without relaunching.

## In use

- [ ] Reduce Motion: the widget doesn't animate, and an org in use shows a still glow.
- [ ] With Show the crab off, Claude Code working: particles on its org within about 2 s, gone about 60 s after it
      stops.
- [ ] A desktop-app or browser chat on the primary org: particles there within one poll (3 minutes).
- [ ] Each In-use effect and amount: Activity Monitor shows Claude Dock near 0% CPU.

## When things go wrong

- [ ] Wi-Fi off: within a refresh the panel says "Can't reach claude.ai", the widget greys
      out; Wi-Fi back on and **Refresh now** brings it back.

## Uninstall

- [ ] The README's uninstall steps leave nothing behind (`ls ~/Library/*/com.wbuf81.claudedock*`).

## Crab and resizing

- [ ] Drag the inner edge at every snap point and in the vertical strip: follows the pointer, snaps to the nearer size, remembered after relaunch. Reduce Motion: no frame animation.
- [ ] Starting a drag 7 pt or more inside the inner edge moves the widget instead of resizing it.
- [ ] Resize while the card is open: the card follows the widget.
- [ ] Click opens the card at both sizes; the widget doesn't change size.
- [ ] Clicks on the clear band beside the crab reach the window behind (a Terminal window reaching down to the Dock).
- [ ] Connect: the confirmation; `~/.claude/settings.json` gains entries ending in `# claude-dock`; other hooks unchanged. Disconnect right after: the file is byte-identical (`shasum` before and after).
- [ ] A Claude Code prompt: thinking, then tool while it runs a command, then done for about 10 s, then idle; all within about a second of each event.
- [ ] A permission prompt shows the red ! within a second.
- [ ] Press Esc mid-turn: the crab rests within about a minute.
- [ ] Approve a long command: the ! stays until the command finishes (Claude Code sends no hook on approval).
- [ ] Two sessions, one waiting for permission: the crab shows the !.
- [ ] `kill -9` a session: its crab goes within 30 s.
- [ ] Not connected: the crab types while Claude Code works, celebrates, then leaves.
- [ ] Activity Monitor: Claude Dock near 0% CPU while the crab animates.
