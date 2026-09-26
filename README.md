<p align="center">
  <img src="docs/images/app-icon.png" alt="Claude Meters app icon" width="96">
</p>

# Claude Meters

A tiny macOS menu bar utility that shows your Claude Code **Session (5-hour)** and **Weekly** usage as two glanceable ring meters — nothing else.

<p align="center">
  <img src="docs/images/menubar-demo.png" alt="Claude Meters menu bar demo showing Session 11% and Weekly 12%" width="240">
</p>

> Two meters. That's it.

## Features

- Two circular meters in the menu bar: Session (5h) and Weekly usage, as a percentage
- Click for a popover with reset countdowns for each meter
- Auto-refresh with exponential backoff on failure and re-fetch on wake from sleep
- Launch at login, configurable refresh interval (1 or 5 minutes)
- English and Japanese, following your system language
- VoiceOver support
- Light and dark mode
- Menu bar only — no Dock icon, no window

## Requirements

- macOS 13 (Ventura) or later
- [Claude Code](https://claude.com/product/claude-code) installed and signed in (Pro/Max subscription or Console billing with usage limits)

## Installation

Download the latest build from the [Releases](../../releases) page, unzip it, and move `Claude Meters.app` to `/Applications`.

> **Note on Gatekeeper:** until this project has a signed, notarized release, macOS will show an "unidentified developer" warning on first launch. Right-click (or Control-click) the app and choose **Open** to bypass it once. See [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) for the distribution plan.

## How it gets your usage data

Claude Meters never asks for or stores its own credentials. Instead it reads the OAuth token that Claude Code already stores in the macOS Keychain (`Claude Code-credentials`) and calls Anthropic's usage endpoint with it — the same one Claude Code itself uses. macOS will show a one-time Keychain access prompt the first time; approving it (with your login password) lets the app read that token.

This endpoint is **not part of Anthropic's public/documented API** and could change without notice — see [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) for the full investigation, the reasoning behind this approach, and its known risks (rate limits, format changes, Keychain access behavior).

## Development

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml` (not checked in as a hand-edited `.xcodeproj`).

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project ClaudeMeters.xcodeproj -scheme ClaudeMeters build
```

Run the tests:

```sh
xcodebuild -project ClaudeMeters.xcodeproj -scheme ClaudeMeters -destination "platform=macOS" test
```

Project layout, requirements, and the technical investigation behind the Keychain/usage-API approach are documented in [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) (Japanese).

## Not in v1

Usage history, graphs, usage forecasting, notifications, multiple accounts, per-model breakdowns, a web dashboard, auto-update. See [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) for the full scope.

## License

[MIT](LICENSE)
