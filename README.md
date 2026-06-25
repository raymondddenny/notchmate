# notchmate

Mac notch utility for developers - Spotify now-playing + (later) live Claude Code session monitoring.

Freemium, open-core. macOS app (Swift + SwiftUI).

## Slice 1 (current)

A minimal notch-app skeleton with a Spotify now-playing widget:

- A borderless, always-on-top, non-activating floating panel pinned to the screen's notch.
- **Collapsed** state: compact strip with artwork thumb, "Artist - Track", and a play-state glyph.
- **Expanded** state (on hover): larger artwork, full track/artist/album, and play / pause / next / prev controls.
- On Macs **without** a physical notch, the same content renders as a floating rounded pill centered at the top of the screen.
- Spotify is polled over AppleScript about once per second. When Spotify is closed or idle, a clean "Nothing playing" state is shown (no crashes, no error spam, and Spotify is never auto-launched).

## Slice 2 (current)

A live **Claude Code session** indicator, free-tier, in its own widget next to Spotify:

- **Collapsed:** a small glyph + count of running Claude Code sessions. Hidden entirely when there are none.
- **Expanded** (on hover): a short per-project list (e.g. `notchmate`, `firstmate ×3`), capped to a few rows with a `+N more` line.
- Running sessions are detected by enumerating live `claude` processes (see [How sessions are detected](#how-sessions-are-detected)). The count updates within a few seconds as sessions start and stop.
- With zero sessions the indicator simply disappears - no crash, no error spam.

### How sessions are detected

A session is a live `claude` process: `notchmate` lists processes with `ps` and keeps those whose executable (argv[0]) is `claude`.
Transient subcommand invocations such as `claude mcp login` are excluded (their first argument is a bareword, not a flag), so the count reflects interactive sessions rather than CLI helpers.
For each session the project name is the basename of the process's working directory, resolved with `lsof`.
Scanning runs on a background queue every ~3 seconds and publishes to the UI on the main thread.

**Limitations:** this slice is detect-and-count only. There is no working-vs-waiting status, no cost tracking, and no fleet view (those are later/premium slices).
If `lsof` cannot resolve a process's directory, that session still counts but is grouped under a generic `session` label.

### Permissions

No special entitlement is required: `ps` and `lsof` report on the user's own processes, and `notchmate` runs as that user.
The app is sandbox-free (no App Sandbox entitlement), which is what allows it to spawn `ps`/`lsof`; if it were ever sandboxed, process enumeration of other processes would be blocked.
If process enumeration ever fails it degrades silently to "no sessions".

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16+ (built and tested with Xcode 26)

## Build

Headless, unsigned, from the repo root:

```sh
xcodebuild -project notchmate.xcodeproj -scheme notchmate -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
```

The app bundle is produced at:

```
build/Build/Products/Release/notchmate.app
```

Or open `notchmate.xcodeproj` in Xcode and press Run.

## Run

```sh
open build/Build/Products/Release/notchmate.app
```

The app has no dock icon or menu bar item (it is an `LSUIElement` agent). It lives entirely in the notch/pill at the top of the screen. To quit, use Activity Monitor or:

```sh
killall notchmate
```

### Unsigned-build Gatekeeper note

The build above is **unsigned**. macOS Gatekeeper will block it on first launch. Clear the quarantine attribute:

```sh
xattr -dr com.apple.quarantine build/Build/Products/Release/notchmate.app
```

If macOS still refuses to open it, go to **System Settings > Privacy & Security**, scroll to the message about `notchmate` being blocked, and click **Open Anyway**.

### Automation permission (first run)

The Spotify widget talks to the Spotify desktop app via AppleScript. On first run, macOS shows a prompt:

> "notchmate" wants access to control "Spotify".

Click **OK**. If you dismiss it, the widget stays in the idle state - re-enable it under **System Settings > Privacy & Security > Automation > notchmate > Spotify**.

## Project layout

```
notchmate/
  App/        - app entry point + AppDelegate (sets up the panel)
  Notch/          - NSPanel shell, screen/notch geometry, root SwiftUI view
  Spotify/        - Spotify AppleScript polling + the now-playing widget
  ClaudeSessions/ - claude-process detection + the session-count widget
```

Feature widgets are isolated per folder so future **premium** features (notifications, multi-agent fleet view, themes) can be added as self-contained widgets gated behind a license check, without touching the notch shell. See `AGENTS.md`.

## Credits

Notch positioning approach was informed by [Boring.Notch](https://github.com/TheBoredTeam/boring.notch) (MIT). This is an independent, lean implementation - no source was vendored.
