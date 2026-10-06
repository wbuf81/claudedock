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

## When things go wrong

- [ ] Wi-Fi off: within a refresh the panel says "Can't reach claude.ai", the widget greys
      out; Wi-Fi back on and **Refresh now** brings it back.

## Uninstall

- [ ] The README's uninstall steps leave nothing behind (`ls ~/Library/*/com.wbuf81.claudedock*`).
