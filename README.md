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

## Slice 6 (current)

**Notch HUDs** - replaces the macOS volume and brightness on-screen overlays with notch-native HUDs (`HUDs/`).

### Volume HUD

Observed via `AudioObjectAddPropertyListenerBlock` on the default output device (volume scalar + mute).
No permission or entitlement required.
Fires on any volume change - media keys, Control Center, external mixer.
When the default audio device changes (headphones plug/unplug), the listener re-attaches automatically.

### Brightness HUD

Polled every 0.1s via `DisplayServicesGetBrightness` from `DisplayServices.framework` (private framework, loaded at runtime via `dlopen`/`dlsym`).
Changes smaller than 1% are ignored to avoid noise.
Works on Intel and Apple Silicon.
**macOS 26 note:** `DisplayServicesGetBrightness` lives in the dyld shared cache; `dlopen` of the framework path still resolves through it.
If the function is unavailable the brightness HUD silently disables itself.

### HUD display

When a volume or brightness change fires, a compact icon + level bar + percentage pill **slides down from just below the collapsed notch**, stays visible ~1.5s, then slides back up and fades out.
It is a separate floating panel (not part of the strip), so it never disturbs the collapsed chips or the expanded (hover) state.

### System HUD suppression (off by default)

The native macOS volume/brightness overlay is drawn by `OSDUIHelper`, a user-level Launch Agent.
When "Replace system volume/brightness HUD" is enabled in Settings > HUDs, notchmate stops it via:

```sh
launchctl bootout gui/<uid>/com.apple.OSDUIHelper
```

And re-enables it via:

```sh
launchctl bootstrap gui/<uid> /System/Library/LaunchAgents/com.apple.OSDUIHelper.plist
```

Restoration runs when the toggle is switched off, or automatically when the app quits (via `NSApplication.willTerminateNotification`).
**Default:** OFF.
**macOS 26 caveat:** if the plist has moved or the service is protected, `bootout` will fail silently (logged to Console.app as `[HUDController] bootout failed`), leaving the native HUD intact.
The toggle is disabled in HUDs settings when the plist is not found at the expected path.

## Slice 7 (current)

A responsive UI + polish pass over the expanded grid, collapsed strip, and HUD:

- **Combined media + lyrics module.** The Media Player tile is now one unified card: artwork + title + artist on top, then the current synced lyric line stacked **directly above** the transport controls. There is no separate Lyrics module any more (it was folded in), so it never appears as two stacked sections.
- **At most 3 modules show.** The panel renders up to three modules at once. Settings > Layout shows an "N of 3 shown" counter and disables further toggles once the cap is reached; rendering also takes only the first three in order as a backstop. Each row sizes to a comfortable fixed column width so titles like "Filosofi Teduh" or "Sungai Suk..." get enough room and no longer truncate awkwardly - the panel width and height adapt to the actual module/row count.
- **Click a Claude session to manage it.** The Claude Sessions tile in the panel is clickable and opens **Settings > Claude Sessions**, which lists every running session (project + branch + path). Each has a **Stop** button that, after a confirmation dialog, sends `SIGTERM` to **only that session's resolved PID** - never a broad kill. Permission or already-exited failures surface a clear message.
- **Collapsed mascot at the left edge.** In the collapsed strip the mascot is pinned to the far left while the now-playing chips stay centered under the notch. The mascot is also smaller and cuter in the expanded view.
- **Now-playing animation in the collapsed strip.** The collapsed media chip shows animated equalizer bars (bouncing while playing, still when paused) ahead of the transport controls.

## Slice 8 (current)

**Claude session traffic lights.** The Claude Sessions module now shows a live status light per session instead of a bare count, so a glance at the notch tells you what every session is doing:

- 🟡 **yellow = running** - the session is actively working a turn.
- 🔴 **red = waiting** - it needs you (a confirmation, permission, or input prompt).
- 🟢 **green = idle/done** - the turn finished; it is ready for the next thing.

Collapsed, the module is a row of colored dots (one per session, with a "+N" overflow); expanded, it is a per-session list with the light, a name, the git branch, and the status word. Dead or long-stale sessions disappear automatically, and clicking still opens **Settings > Claude Sessions** to stop a session.

### Enabling the lights

The live state comes from **Claude Code hooks**, so it has to be switched on once:

1. Open **Settings > Claude Sessions** and turn on **Enable status lights**.
2. That installs a tiny helper (`~/.notchmate/bin/notchmate-hook`) and merges notchmate's hooks into `~/.claude/settings.json`. Your existing hooks and settings are preserved, and a backup is written to `~/.claude/settings.json.notchmate-backup`.
3. It applies to **every** Claude Code session on this Mac (interactive terminals and firstmate crewmates alike), since the hooks live in your user-level config.
4. **Restart any already-running Claude sessions** so they pick up the new hooks. New sessions get them automatically.

Turning the toggle off removes only notchmate's entries (your other hooks stay intact). The change is idempotent - toggling repeatedly never duplicates or loses anything.

### How a session is labelled

Each session shows a discriminator so concurrent sessions in the same directory still read distinctly. The helper prefers `basename($FM_HOME)` (e.g. `notchy` / `wedding-dashboard`), then the tmux session name, then the process id. So several firstmate crewmates sharing the `firstmate` working directory on branch `main` appear as their distinct project names rather than collapsing into identical rows.

### What it maps

| Claude Code hook  | Light            |
|-------------------|------------------|
| `SessionStart`    | 🟢 idle (register) |
| `UserPromptSubmit`| 🟡 running        |
| `PreToolUse`      | 🟡 running        |
| `Notification`    | 🔴 waiting        |
| `Stop`            | 🟢 idle           |
| `SessionEnd`      | (session removed) |

### `~/.notchmate/` layout

```
~/.notchmate/
  bin/notchmate-hook            # the installed hook helper (POSIX sh, zero deps)
  sessions/<session_id>.json    # one live status file per session:
                                #   { state, name, project, branch, cwd, pid, updated }
```

The widget reads `sessions/*.json`; the helper writes them on each hook event. Files for dead or >6h-stale sessions are pruned automatically.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16+ (built and tested with Xcode 26)

## Build

Headless, from the repo root - `build.sh` runs both steps (compile + sign) with the correct entitlements:

```sh
./build.sh
```

The app bundle is produced at:

```
build/Build/Products/Release/notchmate.app
```

`build.sh` ad-hoc signs with hardened runtime (`--options runtime`) and the trimmed
`notchmate/notchmate.entitlements` (just `com.apple.security.automation.apple-events`, required so
macOS 26 lets the Spotify widget send Apple Events).

> **Why not `keychain-access-groups`?** That entitlement is *restricted* - on macOS 26 it only
> validates against a real Apple certificate chain. Ad-hoc signing has none, so including it makes
> the OS kill the app at launch (`Launchd job spawn failed`, POSIX 163). Ad-hoc builds therefore use
> the **login keychain** for the Spotify OAuth token (compiled in via the `ADHOC_SIGNING` flag).

**After a rebuild:** the ad-hoc identity is derived from the binary hash, so it changes each time.
macOS re-prompts for **Automation** access (Spotify AppleScript) and, on first Spotify use after a
rebuild, for the **login keychain** password (to read the saved OAuth token). Approve both - if you
dismiss the keychain prompt the token can't be read and the widget stays on "Connect Spotify".

**Developer ID build (no per-rebuild prompts):**

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build.sh
```

This compiles WITHOUT `ADHOC_SIGNING` (so the OAuth token uses the data-protection keychain - no
prompt) and signs with `notchmate/notchmate-devid.entitlements`. Replace `TEAMID` in that file with
your 10-character Apple team ID first. The first launch re-authorizes Spotify once (new identity);
after that there are no keychain or Automation re-prompts.

Or open `notchmate.xcodeproj` in Xcode and press Run (Xcode uses ad-hoc signing automatically from the project's `CODE_SIGN_IDENTITY = "-"` setting; it inherits the same `ADHOC_SIGNING` flag).

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

> **Signing requirement:** building via `build.sh` is mandatory for the Spotify widget to work.
> The app must be signed with `--options runtime` (hardened runtime) and the `com.apple.security.automation.apple-events` entitlement.
> Without these, macOS 26 silently blocks all outgoing Apple Events before TCC can record or prompt - the Spotify widget stays stuck on "Nothing playing" and the app never appears in System Settings > Privacy & Security > Automation.
> Ad-hoc signing (`--sign -`) is free; no developer account needed.

### Spotify Web API source (recommended on macOS 26)

The **Spotify (Web API)** source uses OAuth 2.0 + PKCE over HTTPS.
It requires no Automation/TCC permission and cannot be blocked by macOS entitlement restrictions.
This is the recommended source on macOS 26, where the AppleScript path requires careful ad-hoc signing.

**How to connect:**

1. Open **Settings > Media**.
2. Select **Spotify (Web API) - Recommended**.
3. Click **Connect Spotify**.
4. Your default browser opens the Spotify authorization page.
5. Log in and click **Agree**.
6. The browser shows "Spotify connected - return to notchmate".
7. The notch immediately shows the live track.

**What it requests:**

| Scope | Why |
|-------|-----|
| `user-read-playback-state` | Read current track, progress, and play/pause state |
| `user-read-currently-playing` | Read the currently playing item |
| `user-modify-playback-state` | Send play/pause/next/previous controls |

**Tokens:**
The `access_token` and `refresh_token` are stored in the **macOS Keychain** under the service name `notchmate.spotify.webapi`.
They are never written to disk, logged, or stored in UserDefaults.
The token expiry timestamp (not sensitive) is stored in UserDefaults.
Tokens auto-refresh ~60 seconds before expiry; no hourly re-login.

**Premium:**
Reading now-playing works on any Spotify account (Free or Premium).
Playback controls (play/pause/next/previous) require a Spotify Premium account.
On a Free account, the controls are dimmed and a "Spotify Premium required" hint is shown; the widget continues showing the current track.

**Configuration (for developers):**
The OAuth client ID is `5a058e7eb1b140a1a4b97bd801fc8734` (a public client - PKCE requires no secret).
The redirect URI is `http://127.0.0.1:8888/callback` (loopback - registered in the Spotify app dashboard).
Both are defined as constants in `notchmate/Spotify/SpotifyWebController.swift` under `SpotifyWebConfig`.
If you fork and register your own Spotify app, update those two values.

**To disconnect:**
Settings > Media > Disconnect.
This deletes the tokens from Keychain and clears the session.

### AppleScript Spotify source (fallback)

The **Spotify (AppleScript)** source polls the Spotify desktop app once per second over AppleScript.
It requires Automation/TCC permission and the hardened runtime entitlement.

**Prerequisite:** the binary must be ad-hoc signed (build via `./build.sh`, see [Build](#build) above).
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

| Pane    | Controls                                                                                                                                   |
|---------|--------------------------------------------------------------------------------------------------------------------------------------------|
| General | Show menu-bar icon toggle; Launch at login (`SMAppService`)                                                                                |
| Media   | **Music source** (Spotify Web API / Spotify AppleScript / Now Playing any app); Connect/Disconnect Spotify Web API; **Layout**; **Lyrics** |
| HUDs    | Volume HUD toggle; Brightness HUD toggle; Replace system HUD toggle (suppresses OSDUIHelper via launchctl)                                 |
| About   | Version, build, link to this repo                                                                                                          |

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
  Spotify/        - SpotifyController (AppleScript polling) + SpotifyWebController (Web API + PKCE OAuth) + MediaWidget (now-playing UI)
  ClaudeSessions/ - claude-process detection + the session-count widget
  Mochi/          - the reactive mascot (mood model + code-drawn SwiftUI view)
  Git/            - focused-repo branch/dirty glance (git via Process)
  Timer/          - Pomodoro focus timer + local-notification on completion
  SystemStats/    - CPU/memory load via Mach host statistics
  HUDs/           - volume + brightness HUD controller + compact HUD view
```

Feature widgets are isolated per folder so future **premium** features (notifications, multi-agent fleet view, themes) can be added as self-contained widgets gated behind a license check, without touching the notch shell. See `AGENTS.md`.

## Credits

Notch positioning approach was informed by [Boring.Notch](https://github.com/TheBoredTeam/boring.notch) (MIT). This is an independent, lean implementation - no source was vendored.
