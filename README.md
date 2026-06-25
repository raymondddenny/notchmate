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
  Notch/      - NSPanel shell, screen/notch geometry, root SwiftUI view
  Spotify/    - Spotify AppleScript polling + the now-playing widget
```

Feature widgets are isolated per folder so future **premium** features (notifications, multi-agent fleet view, themes) can be added as self-contained widgets gated behind a license check, without touching the notch shell. See `AGENTS.md`.

## Credits

Notch positioning approach was informed by [Boring.Notch](https://github.com/TheBoredTeam/boring.notch) (MIT). This is an independent, lean implementation - no source was vendored.
