<div align="center">

# notchmate

**The MacBook notch, turned into a developer's command center.**

Now-playing media with synced lyrics, live Claude Code session monitoring, focus timer, git glance, system stats, notch-native HUDs, and a reactive mascot - all in the space macOS gives away for free.

[![Latest release](https://img.shields.io/github/v/release/raymondddenny/notchmate?label=release&color=brightgreen)](https://github.com/raymondddenny/notchmate/releases/latest)
[![License: MIT](https://img.shields.io/github/license/raymondddenny/notchmate?color=blue)](LICENSE)
[![Platform](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)](#requirements)
[![Built with Swift](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift)](https://www.swift.org)
[![Stars](https://img.shields.io/github/stars/raymondddenny/notchmate?style=social)](https://github.com/raymondddenny/notchmate/stargazers)

</div>

---

## Highlights

- **Now playing + synced lyrics** - a unified media tile (artwork, title, artist, transport controls) with the current synced lyric line stacked above the controls. Spotify via the Web API (OAuth + PKCE) or the desktop app via AppleScript.
- **Live Claude Code sessions** - per-session traffic-light status driven by Claude Code hooks: 🟡 running, 🔴 waiting on you, 🟢 idle/done. Click to stop any single session safely.
- **Notch-native HUDs** - volume and brightness overlays that slide out from under the notch, optionally replacing the macOS system HUD.
- **Focus timer** - a Pomodoro timer with a GitHub-style contribution heatmap and streak stats.
- **Git glance** - branch, dirty state, and ahead/behind for the repo you are actively working in.
- **System stats** - CPU and memory load, surfaced only when the machine is busy.
- **Reactive mascot** - an original, code-drawn character that dances to your music and thinks while Claude works.

Everything is free-tier. No paywall, no account, no telemetry.
Zero third-party dependencies - pure Swift + SwiftUI.

## Install

```sh
brew tap raymondddenny/notchmate https://github.com/raymondddenny/notchmate
brew install --cask notchmate
```

Update to the latest release:

```sh
brew upgrade --cask notchmate
```

> notchmate is ad-hoc signed (no paid Apple Developer certificate), so the cask strips the quarantine attribute on install to keep Gatekeeper from blocking launch.
> If a build still refuses to open, reinstall with `brew install --cask --no-quarantine notchmate`.

Prefer not to use Homebrew? Download the `.dmg` from the [latest release](https://github.com/raymondddenny/notchmate/releases/latest), drag the app to Applications, then run `xattr -dr com.apple.quarantine /Applications/notchmate.app`.

## Requirements

- macOS 14 (Sonoma) or later.
- Apple Silicon or Intel.
- For building from source: Xcode 16+ (built and tested with Xcode 26).

## Features in detail

### Media + lyrics

The media tile shows artwork, title, artist, the current synced lyric line, and play/pause/next/previous controls.
The collapsed strip shows animated equalizer bars (bouncing while playing) ahead of compact transport controls.

Two Spotify sources are supported:

- **Spotify (Web API)** - OAuth 2.0 + PKCE over HTTPS. Recommended on macOS 26. No Automation/TCC permission needed. See [Connecting Spotify](#connecting-spotify).
- **Spotify (AppleScript)** - polls the desktop app once per second. Requires Automation permission and a hardened-runtime build.

Lyrics are fetched from [LRCLIB](https://lrclib.net) (no API key) and synced line-by-line to playback position.
On Macs without a notch, the same UI renders as a floating rounded pill centered at the top of the screen.

### Claude Code session lights

A glance at the notch tells you what every Claude Code session is doing:

| Light | Meaning |
|-------|---------|
| 🟡 running | The session is actively working a turn. |
| 🔴 waiting | It needs you - a confirmation, permission, or input prompt. |
| 🟢 idle/done | The turn finished; ready for the next thing. |

Collapsed, the module is a row of colored dots (with a `+N` overflow).
Expanded, it is a per-session list with the light, a name, the git branch, and the status word.
Dead or long-stale sessions disappear automatically.
See [Enabling the session lights](#enabling-the-session-lights) for one-time setup.

### Notch HUDs

When the volume or brightness changes, a compact icon + level bar + percentage pill slides down from just below the notch, stays ~1.5s, then slides back up and fades.
Volume is observed via CoreAudio (no permission required) and fires on any change - media keys, Control Center, or an external mixer.
Brightness is polled from the built-in display.

Optionally, notchmate can replace the native macOS volume/brightness overlay entirely (Settings > HUDs).

> **Note on external displays:** brightness HUDs only work on the built-in Apple display - the private API macOS exposes (`DisplayServicesGetBrightness`) cannot read external monitor brightness. Volume HUDs work on any display.

### Focus timer, git glance, system stats

- **Focus timer** - a 25-minute Pomodoro with Start/Pause/Reset, a completion notification, a GitHub-style contribution heatmap, and current/best streak stats.
- **Git glance** - branch, a dirty/clean dot, and ahead/behind arrows for the focused repo (the working directory of your most-recently-active Claude session). Hides when there is no repo in context.
- **System stats** - a CPU badge that appears only under heavy load when collapsed, plus CPU and memory mini-bars when expanded.

### Mascot

An original, code-drawn mascot lives in the notch and reacts to the app:
**dancing** while music plays, **thinking** while Claude works, **idle** when paused, **sleeping** when nothing is happening.
Drawn entirely with SwiftUI shapes - no images, no Lottie, no dependencies - and it honors Reduce Motion.
A pixel-art duck character is also available; pick one in Settings > Mascot.

## Connecting Spotify

The recommended **Spotify (Web API)** source uses OAuth 2.0 + PKCE and works without any system permission.

1. Open **Settings > Media**.
2. Select **Spotify (Web API) - Recommended**.
3. Click **Connect Spotify**; your browser opens the Spotify authorization page.
4. Log in and click **Agree**. The notch immediately shows the live track.

Tokens (`access_token`, `refresh_token`) are stored only in the macOS Keychain under the service `notchmate.spotify.webapi`.
They are never written to disk, logged, or stored in UserDefaults, and they auto-refresh before expiry.
Reading now-playing works on any account; playback controls require Spotify Premium (controls dim with a hint on Free accounts).

To disconnect: **Settings > Media > Disconnect** (deletes the tokens from Keychain).

## Enabling the session lights

Live Claude Code status comes from Claude Code hooks, so it is switched on once:

1. Open **Settings > Claude Sessions** and turn on **Enable status lights**.
2. This installs a tiny helper at `~/.notchmate/bin/notchmate-hook` and merges notchmate's hooks into `~/.claude/settings.json`. Your existing hooks and settings are preserved, and a backup is written to `~/.claude/settings.json.notchmate-backup`.
3. It applies to every Claude Code session on this Mac, since the hooks live in your user-level config.
4. Restart any already-running Claude sessions so they pick up the new hooks. New sessions get them automatically.

Turning the toggle off removes only notchmate's entries; the operation is idempotent and never duplicates or loses anything.
Reading the status files and checking process liveness needs no special entitlement.

## Build from source

From the repo root, `build.sh` runs both steps (compile + sign) with the correct entitlements:

```sh
./build.sh
open build/Build/Products/Release/notchmate.app
```

The script ad-hoc signs with hardened runtime (`--options runtime`) and the trimmed `notchmate/notchmate.entitlements` (just `com.apple.security.automation.apple-events`, required so macOS 26 lets the Spotify widget send Apple Events).
A locally built binary is not quarantined, so Gatekeeper will not block it.

For a signed build with no per-rebuild keychain/Automation prompts:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

This compiles without the `ADHOC_SIGNING` flag (the OAuth token then uses the data-protection keychain) and signs with `notchmate/notchmate-devid.entitlements`.
Replace `TEAMID` in that file with your 10-character Apple team ID first.

> **Why ad-hoc by default?** The `keychain-access-groups` entitlement is restricted - on macOS 26 it validates only against a real Apple certificate chain, so including it under ad-hoc signing makes the OS kill the app at launch. Ad-hoc builds therefore use the login keychain for the Spotify token (compiled in via the `ADHOC_SIGNING` flag). The trade-off is a one-time keychain prompt after each rebuild.

You can also open `notchmate.xcodeproj` in Xcode and press Run.

## Releasing

Releases are automated. Push a version tag and GitHub Actions builds the DMG, publishes a release, and bumps the Homebrew cask:

1. Bump `CFBundleShortVersionString` (and `CFBundleVersion`) in `notchmate/Info.plist`.
2. Commit to `master`.
3. `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. CI ([`.github/workflows/release.yml`](.github/workflows/release.yml)) builds, releases, and commits the updated `Casks/notchmate.rb`.

A guard in CI fails the build if the tag version does not match `Info.plist`.

## Settings

Open Settings from the menu-bar icon (⌘,).

| Pane | Controls |
|------|----------|
| General | Show menu-bar icon; Launch at login (`SMAppService`) |
| Layout | Module order, enable/disable, row count (up to 3 modules shown) |
| Media | Spotify source; Connect/Disconnect Spotify Web API |
| HUDs | Replace system HUD; Volume HUD; Brightness HUD |
| Claude Sessions | Enable status lights; per-session list with a guarded Stop |
| Mascot | Enable mascot; character picker |
| About | Version, build, link to this repo |

## Project layout

```
notchmate/
  App/            - app entry point + AppDelegate + StatusBarController
  Notch/          - NSPanel shell, screen/notch geometry, root SwiftUI view
  Settings/       - preferences store, settings window, all panes
  Media/          - MediaController (aggregates Spotify + system NowPlaying)
  Spotify/        - AppleScript + Web API (PKCE OAuth) controllers + media widget
  Lyrics/         - LRCLIB fetch, LRC parsing, synced line view
  ClaudeSessions/ - hook-driven session status lights + installer
  Mochi/          - the reactive mascot (mood model + code-drawn views)
  Git/            - focused-repo branch/dirty glance
  Timer/          - Pomodoro focus timer + heatmap stats
  SystemStats/    - CPU/memory load via Mach host statistics
  HUDs/           - volume + brightness HUD controller and views
```

Feature widgets are isolated per folder, so new features can be added as self-contained modules without touching the notch shell.

## Contributing

Issues and pull requests are welcome.
For build, architecture, and sharp-edge notes, see [`CLAUDE.md`](CLAUDE.md).

## License

[MIT](LICENSE) © raymondddenny.

Notch positioning was informed by [Boring.Notch](https://github.com/TheBoredTeam/boring.notch) (MIT).
This is an independent, lean implementation - no source was vendored.

## Star history

If notchmate is useful to you, consider starring the repo - it helps others find it.

[![Star History Chart](https://api.star-history.com/svg?repos=raymondddenny/notchmate&type=Date)](https://star-history.com/#raymondddenny/notchmate&Date)
