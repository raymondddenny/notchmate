# notchmate

Mac notch utility for developers - now-playing music widget, live Claude Code session monitoring, and developer widgets.

Freemium, open-core. macOS app (Swift + SwiftUI).

## Slice 1 (current)

A minimal notch-app skeleton with a Spotify now-playing widget:

- A borderless, always-on-top, non-activating floating panel pinned to the screen's notch.
- **Collapsed** state: compact strip with optional artwork thumb, "Artist - Track", and an animated equalizer indicator (bouncing bars when playing, static when paused).
- **Expanded** state (on hover): artwork or compact text layout (user's choice), full track/artist/album, play / pause / next / prev controls.
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

## Slice 5 (current)

**Settings window** - a preferences window accessible from the menu-bar status item.

- Menu-bar icon (menubar rectangle symbol) with "Settings..." (⌘,) and "Quit notchmate".
- Settings window: `NavigationSplitView` sidebar with General, Media (stub), HUDs (stub), and About panes.
- **General pane:** "Show menu-bar icon" toggle (persists in UserDefaults); "Launch at login" toggle (wires `SMAppService.mainApp`).
- **About pane:** app name, version/build from `Info.plist`, one-line description, link to repo.
- Stub Media and HUDs panes mark the navigation slots for future work.
- Shared `NotchPreferences` singleton is the extensible preferences store - later panes add fields there.

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

Headless, from the repo root (two commands - the signing step is required for Spotify access):

```sh
# 1. Compile
xcodebuild -project notchmate.xcodeproj -scheme notchmate -configuration Release \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

# 2. Ad-hoc sign with hardened runtime + Apple Events entitlement.
#    Required for Spotify TCC: hardened runtime blocks outgoing Apple Events
#    unless com.apple.security.automation.apple-events is present, and macOS 26
#    requires this even for non-sandboxed apps.
codesign --force --deep --options runtime \
  --entitlements notchmate/notchmate.entitlements \
  --sign - build/Build/Products/Release/notchmate.app
```

The app bundle is produced at:

```
build/Build/Products/Release/notchmate.app
```

**After a rebuild:** the ad-hoc identity is derived from the binary hash, so it changes each time you rebuild.
macOS will re-prompt for Automation access after each fresh build.
Run both commands above again and approve the prompt when it appears.
Stable per-developer signing (Developer ID, the eventual $99 path) eliminates re-prompts permanently.

Or open `notchmate.xcodeproj` in Xcode and press Run (Xcode uses ad-hoc signing automatically from the project's `CODE_SIGN_IDENTITY = "-"` setting).

## Run

```sh
open build/Build/Products/Release/notchmate.app
```

The app shows a small **menu-bar icon** (a menubar rectangle) in the system status bar.
Click it for a **Settings...** shortcut (⌘,) and **Quit notchmate**.
The icon can be hidden from the General pane in Settings - use **Settings > General > Show menu-bar icon**.

To quit from the menu-bar icon:

```sh
# or use the menu-bar item: click icon → Quit notchmate
killall notchmate
```

### Gatekeeper note (locally-built binaries)

A locally-built, ad-hoc-signed binary is not quarantined (quarantine is set only on downloaded files), so Gatekeeper will not block it.
If you downloaded a pre-built binary instead of building from source, clear the quarantine attribute:

```sh
xattr -dr com.apple.quarantine build/Build/Products/Release/notchmate.app
```

If macOS still refuses to open it, go to **System Settings > Privacy & Security**, scroll to the message about `notchmate` being blocked, and click **Open Anyway**.

> **Signing requirement:** the `codesign` step above is mandatory for the Spotify widget to work.
> The app must be signed with `--options runtime` (hardened runtime) and the `com.apple.security.automation.apple-events` entitlement.
> Without these, macOS 26 silently blocks all outgoing Apple Events before TCC can record or prompt - the Spotify widget stays stuck on "Nothing playing" and the app never appears in System Settings > Privacy & Security > Automation.
> Ad-hoc signing (`--sign -`) is free; no developer account needed.

### Automation permission (first run)

**Prerequisite:** the binary must be ad-hoc signed (see the `codesign` step in [Build](#build) above).
Without a signature, macOS TCC has no stable identity to prompt for, and the Spotify permission never appears.

The Spotify widget talks to the Spotify desktop app via AppleScript.
On the first poll where Spotify is running, macOS shows a one-time prompt:

> "notchmate" wants access to control "Spotify".

Click **OK**.
The notch will immediately start showing the now-playing track.

**If you clicked "Don't Allow"** (or if a prior build's grant was revoked):
The widget shows an orange lock icon and a tappable **"Allow Spotify access"** button.
Click it - notchmate opens **System Settings > Privacy & Security > Automation** for you.
Find **notchmate** in the list and enable the **Spotify** toggle.
The widget picks up the change within one second (no restart needed).

**After a rebuild:**
The ad-hoc identity is the binary's hash - it changes with each build.
macOS treats the rebuilt binary as a new identity and re-prompts automatically on the next poll where Spotify is running.
Just click **OK** again.

All AppleScript errors are logged to Console.app as `[SpotifyController] AppleScript error <code>: <message>` for diagnosis.
Error -1743 (`errAEEventNotPermitted`) is the TCC-denied code.

### Notification permission (focus timer)

The first time you press **Start** on the focus timer, macOS asks to allow notifications from notchmate. Allow it to get a banner when a focus session completes. Denying it only drops the banner; the timer itself is unaffected.

## Settings

Open Settings with the menu-bar icon (⌘,) or via the status-bar item.

| Pane    | Controls                                                                                                                   |
|---------|----------------------------------------------------------------------------------------------------------------------------|
| General | Show menu-bar icon toggle; Launch at login (`SMAppService`)                                                                |
| Media   | **Music source** (Spotify only / Now Playing any app); **Layout** (with artwork thumbnail / compact text-only)            |
| HUDs    | Coming soon                                                                                                                |
| About   | Version, build, link to this repo                                                                                          |

**Show menu-bar icon** persists in `UserDefaults`.
When hidden, the icon is removed from the system status bar; it can be restored by toggling back on in a Settings window already open.

**Launch at login** calls `SMAppService.mainApp.register()` / `unregister()` (ServiceManagement, macOS 13+).
No helper target, no third-party dep.
Registration fails in unsigned builds; the toggle reflects real `SMAppService.mainApp.status` so it will flip back - this is correct behavior.

**Adding a new pane:** add a case to `SettingsPane` in `SettingsView.swift`, add the view file under `Settings/`, add it to the `switch` in `SettingsView`, and add the file to `project.pbxproj` (see `AGENTS.md` for the pbxproj edit pattern).

## Project layout

```
notchmate/
  App/            - app entry point + AppDelegate + StatusBarController
  Notch/          - NSPanel shell, screen/notch geometry, root SwiftUI view
  Settings/       - preferences store, settings window, all panes
  Media/          - MediaController (aggregates Spotify + system NowPlaying sources)
  Spotify/        - SpotifyController (AppleScript polling) + MediaWidget (now-playing UI)
  ClaudeSessions/ - claude-process detection + the session-count widget
  Mochi/          - the reactive mascot (mood model + code-drawn SwiftUI view)
  Git/            - focused-repo branch/dirty glance (git via Process)
  Timer/          - Pomodoro focus timer + local-notification on completion
  SystemStats/    - CPU/memory load via Mach host statistics
```

Feature widgets are isolated per folder so future **premium** features (notifications, multi-agent fleet view, themes) can be added as self-contained widgets gated behind a license check, without touching the notch shell. See `AGENTS.md`.

## Credits

Notch positioning approach was informed by [Boring.Notch](https://github.com/TheBoredTeam/boring.notch) (MIT). This is an independent, lean implementation - no source was vendored.
