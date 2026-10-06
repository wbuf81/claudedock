# Claude Dock

A small always-on macOS widget for people with more than one Claude plan. It sits in the
bottom-right corner at Dock height and shows, for each Claude organization you belong to:

- how much of this week's usage limit is used, against how much of the week has gone by
- how much of the current 5-hour window is used, against how far into it you are
- a stoplight dot: green when you should be using that plan (tokens would otherwise go
  unused at reset), yellow when you're on pace, red when it's nearly out

Click it for a panel with a week chart, a daily target, the model-specific weekly limit,
and advice on which organization Claude Code should be signed into.

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
