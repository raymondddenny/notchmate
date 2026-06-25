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
- **Expanded** (on hover): individual session rows showing the project name and current git branch (e.g. `notchmate  main`), capped to three rows with a `+N more` line.
- Running sessions are detected by enumerating live `claude` processes (see [How sessions are detected](#how-sessions-are-detected)). The count updates within a few seconds as sessions start and stop.
- With zero sessions the indicator simply disappears - no crash, no error spam.

### How sessions are detected

A session is a live `claude` process: `notchmate` lists processes with `ps` and keeps those whose executable (argv[0]) is `claude`.
Transient subcommand invocations such as `claude mcp login` are excluded (their first argument is a bareword, not a flag), so the count reflects interactive sessions rather than CLI helpers.
For each session the project name is the basename of the process's working directory, resolved with `lsof`.
Scanning runs on a background queue every ~3 seconds and publishes to the UI on the main thread.

**Limitations:** this slice is detect-and-count only. There is no working-vs-waiting status, no cost tracking, and no fleet view (those are later/premium slices).
If `lsof` cannot resolve a process's directory, that session still counts but is grouped under a generic `session` label.

## Slice 3 (current)

**Mochi**, an original reactive mascot that lives in the notch beside the other widgets (free-tier).

It is a small, code-drawn mochi-style robot: a soft cream blob body with a tiny face and a single glowing antenna.
The character is our own design - not based on any existing or branded character - and is drawn entirely with SwiftUI shapes and animated with SwiftUI (no images, no Lottie, no third-party deps).

It reacts to what the rest of the app is doing:

- **Dancing** - when Spotify is actively playing: it bobs and wobbles to a lively beat, eyes happy (`⌒⌒`), open "singing" mouth, antenna pulsing green. (Expanded: a `♪` note floats beside it.)
- **Thinking** - when one or more Claude Code sessions are running: an attentive upright pose with a blinking orange antenna and round eyes. (Expanded: three chasing dots above its head.)
- **Idle** - when a track is loaded but paused (nothing actively happening): calm slow breathing, round blinking eyes, a gentle smile, soft cyan antenna.
- **Sleeping** - when nothing is happening at all (no music, no sessions): eyes shut (`‿‿`), slow deep breaths, antenna dimmed. (Expanded: drifting `z z`.)

Mood is derived from the existing Spotify and Claude controllers with a simple priority: **dancing > thinking > idle > sleeping** (so music wins when both music and sessions are live).
Transitions between moods are animated (face features crossfade, the antenna recolors) rather than snapping.
The mascot honors **Reduce Motion**: when it is enabled the looping animation is dropped for a calm static pose.

It stays small when collapsed so it does not crowd the Spotify/Claude widgets, and grows more expressive when the notch is expanded on hover - in both the notch and the non-notch pill layout.

**Limitation / extension point:** the app currently only knows the session *count*, not whether a session is actively working vs. waiting on you, so `thinking` reacts to "sessions present".
When a finer Claude signal exists, the mood-derivation function (`MochiMood.derive`) is the single place to branch on it.

### Permissions

No special entitlement is required: `ps` and `lsof` report on the user's own processes, and `notchmate` runs as that user.
The app is sandbox-free (no App Sandbox entitlement), which is what allows it to spawn `ps`/`lsof`; if it were ever sandboxed, process enumeration of other processes would be blocked.
If process enumeration ever fails it degrades silently to "no sessions".

## Slice 4 (current)

The three remaining free-tier widgets that round out v1, each in its own folder beside the others.

### Git glance (`Git/`)

A "what am I working on" glance at the **focused repo**.

- **Focused repo** = the working directory of the most-recently-launched live Claude Code session (highest pid). This reuses the session dirs `ClaudeSessionsController` already resolves, so it needs no extra permission and is a reliable proxy for "the project you're in". When no session has a resolvable repo, the widget hides.
- **Collapsed:** branch name + a dot - amber when the working tree is dirty, green when clean.
- **Expanded:** branch + dirty dot, the repo name and a `clean`/`modified` label, plus ahead/behind arrows when an upstream is set.
- **Data source:** runs `git -C <dir>` (`rev-parse --show-toplevel` / `--abbrev-ref HEAD`, `status --porcelain`, and `rev-list --count --left-right @{upstream}...HEAD`) off-main, published to main. Polled every ~4s and re-targeted immediately when the session set changes. Any failure (no repo, no Command Line Tools, detached HEAD, no upstream) degrades to a partial or hidden state - never spams.

### Focus timer (`Timer/`)

A classic 25-minute Pomodoro focus timer, driven from the expanded notch.

- **Collapsed:** a compact `MM:SS` countdown while running (dimmed while paused); hidden when idle.
- **Expanded:** the time plus **Start/Pause** and **Reset** controls (always shown, so there's always a place to begin).
- **Data source:** a plain SwiftUI/Foundation `Timer`, no dependency. On completion it posts a local `UNUserNotification`.
- **Permission:** notification authorization is requested lazily the first time you press Start. If you deny it, the countdown still works - you just don't get the completion banner. Re-enable under **System Settings > Notifications > notchmate**.

### System stats (`SystemStats/`)

Live CPU and memory load, loudest exactly when the machine is busy.

- **Collapsed:** a CPU% badge that only appears when CPU is high (≥70%) - quiet when the machine is idle.
- **Expanded:** CPU and memory mini-bars with percentages, always shown.
- **Data source:** Mach host statistics (`host_statistics(HOST_CPU_LOAD_INFO)` for CPU as a delta between samples; `host_statistics64(HOST_VM_INFO64)` + `ProcessInfo.physicalMemory` for memory). No third-party dep, no permission. Polled every ~2s off-main. The first CPU reading is 0 until a baseline sample exists.

### Collapsed layout decisions

The collapsed strip stays uncluttered by surfacing each new widget only when it has something worth showing:

- The timer countdown shows only while a session is running.
- The git branch + dirty dot show only when a repo is in context.
- The CPU badge shows only under heavy load.

Full system stats and the timer controls live in the **expanded** panel only. Spotify keeps the flexible middle space (its title truncates), and the compact chips trail it. This holds for both the notch and the non-notch pill layout.

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

The Spotify widget talks to the Spotify desktop app via AppleScript.
On the first poll after Spotify is running, macOS shows a prompt:

> "notchmate" wants access to control "Spotify".

Click **OK**.

If you click **Don't Allow** (or if you previously dismissed the prompt), notchmate cannot read Spotify.
Instead of a misleading "Nothing playing", the widget shows **"Allow Spotify access in System Settings"**.
To fix it, open **System Settings > Privacy & Security > Automation**, find **notchmate**, and enable the **Spotify** toggle.

All AppleScript errors are logged to Console.app as `[SpotifyController] AppleScript error <code>: <message>` for diagnosis.
Error -1743 (`errAEEventNotPermitted`) is the TCC-denied code.

### Notification permission (focus timer)

The first time you press **Start** on the focus timer, macOS asks to allow notifications from notchmate. Allow it to get a banner when a focus session completes. Denying it only drops the banner; the timer itself is unaffected.

## Project layout

```
notchmate/
  App/        - app entry point + AppDelegate (sets up the panel)
  Notch/          - NSPanel shell, screen/notch geometry, root SwiftUI view
  Spotify/        - Spotify AppleScript polling + the now-playing widget
  ClaudeSessions/ - claude-process detection + the session-count widget
  Mochi/          - the reactive mascot (mood model + code-drawn SwiftUI view)
  Git/            - focused-repo branch/dirty glance (git via Process)
  Timer/          - Pomodoro focus timer + local-notification on completion
  SystemStats/    - CPU/memory load via Mach host statistics
```

Feature widgets are isolated per folder so future **premium** features (notifications, multi-agent fleet view, themes) can be added as self-contained widgets gated behind a license check, without touching the notch shell. See `AGENTS.md`.

## Credits

Notch positioning approach was informed by [Boring.Notch](https://github.com/TheBoredTeam/boring.notch) (MIT). This is an independent, lean implementation - no source was vendored.
