# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.

## Build

- Native macOS app, Swift + SwiftUI, deployment target macOS 14. Hand-authored `.xcodeproj` (no CocoaPods/Carthage/SPM deps; zero third-party).
- Headless build (two steps - signing is required for Spotify TCC):
  1. `xcodebuild -project notchmate.xcodeproj -scheme notchmate -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build`
  2. `codesign --force --deep --options runtime --entitlements notchmate/notchmate.entitlements --sign - build/Build/Products/Release/notchmate.app`
  Output: `build/Build/Products/Release/notchmate.app`.
  The xcodeproj sets `CODE_SIGN_IDENTITY = "-"` and `CODE_SIGN_ENTITLEMENTS = notchmate/notchmate.entitlements` for Xcode IDE builds; the CLI path needs the explicit post-build `codesign` step because `CODE_SIGNING_ALLOWED=NO` overrides it.
  **`--options runtime` is now required**: on macOS 26 (26.5.1, confirmed 2026-06-25), the OS blocks outgoing Apple Events for apps without hardened runtime + the `com.apple.security.automation.apple-events` entitlement. Without these flags the app never appears in System Settings > Privacy > Automation and the Spotify widget is permanently stuck on "Nothing playing". Plain `--sign -` (without `--options runtime`) no longer suffices on macOS 26.
- `Info.plist` is checked in and wired via `INFOPLIST_FILE` with `GENERATE_INFOPLIST_FILE = NO`. `LSUIElement = true` (no dock icon / agent app), so the app has no standard window - all UI is the NSPanel.

## Architecture

- `App/` - `@main` App + AppDelegate; AppDelegate sets activation policy `.accessory` and owns one `NotchWindowController`, `SettingsWindowController`, and `StatusBarController`.
- `Settings/` - `NotchPreferences` (shared `ObservableObject` preferences store, `@Published` fields backed by `UserDefaults`; `launchAtLogin` reads/writes `SMAppService.mainApp`), `SettingsWindowController` (creates/reuses an `NSWindow` hosting `SettingsView` on demand, activates the app on show), `SettingsView` (`NavigationSplitView` sidebar with `SettingsPane` enum rows), `GeneralPane` (show menu-bar icon toggle + launch at login via `SMAppService`), `AboutPane` (version/build from Bundle, link to repo), `MediaPane`/`HUDsPane` (stubs for future panes). Free-tier, no license gate.
- `App/StatusBarController.swift` - owns `NSStatusItem`; subscribes to `NotchPreferences.$showMenuBarIcon` and installs/removes the item reactively; menu provides "Settings..." and "Quit notchmate".
- `Notch/` - `NotchPanel` (borderless non-activating NSPanel at `.statusBar` level), `NotchWindowController` (screen/notch geometry + collapsed/expanded resize), `NotchView` (root SwiftUI, hover -> expand).
- `Media/` - `MediaController` (ObservableObject wrapper; aggregates `SpotifyController` + `SystemNowPlayingController`, routes transport to the active source, republishes `nowPlaying`/`artwork`/`permissionDenied` to the rest of the app) and `SystemNowPlayingController` (reads system-wide now-playing via MediaRemote private framework, loaded at runtime via dlopen/dlsym). Free-tier.
- `Spotify/` - `SpotifyController` (ObservableObject; AppleScript poll + transport; unchanged from v1) and `SpotifyWidget.swift` which now contains `MediaWidget` (the now-playing UI, backed by `MediaController`; supports Spotify and system sources, animated equalizer bars, artwork/compact layout from `NotchPreferences`).
- `ClaudeSessions/` - `ClaudeSessionsController` (ObservableObject; polls live `claude` processes off-main, publishes `[ClaudeSession]` + a project grouping) and `ClaudeSessionsWidget` (collapsed count glyph / expanded per-project list; renders nothing at zero). Free-tier, no license gate.
- `Mochi/` - the mascot. `MochiMood` (pure enum + `derive` + per-mood accent color; no UI deps) and `MochiView` (code-drawn SwiftUI mochi-robot; observes `MediaController` and `ClaudeSessionsController` - dances to ANY media source, not just Spotify). Free-tier, no license gate.
- `Git/` - `GitController` (ObservableObject; runs `git` off-main in the focused repo, publishes `GitState?` to main) and `GitWidget` (collapsed branch + dirty dot / expanded branch+repo+ahead/behind; renders nothing with no repo). Free-tier.
- `Timer/` - `FocusTimerController` (ObservableObject; Pomodoro state machine on a `Timer`, posts a local `UNUserNotification` on completion) and `FocusTimerWidget` (collapsed countdown when active / expanded time + Start/Pause/Reset). Free-tier.
- `SystemStats/` - `SystemStatsController` (ObservableObject; Mach host CPU/mem off-main, publishes `SystemSample` to main) and `SystemStatsWidget` (collapsed CPU% only above threshold / expanded CPU+mem bars). Free-tier.
- **Git focused-repo signal:** `GitController` reuses `ClaudeSessionsController`'s resolved session dirs rather than tracking the frontmost app (which needs more TCC scope and code for a marginal gain). Focused repo = `pickDir` = the dir of the highest-pid session (newest ≈ most-recently-active). For this `ClaudeSession` carries the full `dir` (not just the basename `project`). Pure helpers (`pickDir`, `parseAheadBehind`) have a `runSelfCheck()`. Poll 4s + re-target on session change.
- **Mood/derive unchanged by Git:** the mascot still observes only Spotify/Claude; the git/timer/stats widgets are independent and don't feed mood.
- **Expanded panel sizing:** `NotchWindowController.currentExpandedSize` sums per-widget height contributions (Spotify base + always-on Timer/Stats blocks + conditional Claude/Git blocks) and the panel re-fits (via a merged `claude.$sessions`/`git.$state` publisher) only for the blocks whose *presence* changes height. Timer countdown / stats values change content, not height, so they don't trigger a refit.
- **Collapsed strip rule:** each new chip self-hides until it has signal (timer running, repo present, CPU high) so the small strip stays uncluttered; Spotify holds the flexible middle and truncates. Full stats + timer controls are expanded-only.
- **Mascot mood derivation:** `MochiMood.derive(spotifyPlaying:spotifyPresent:claudeSessions:)` is a pure function (unit-testable; `runDeriveSelfCheck()` asserts the truth table from the SwiftUI preview). Priority: `dancing` (Spotify playing) > `thinking` (>=1 Claude session) > `idle` (a track loaded but paused) > `sleeping` (nothing). Dancing deliberately wins over thinking. **Extension point:** the app only knows session *count*, not working-vs-waiting; when a finer signal lands, branch inside `derive` (a "working" session -> livelier `thinking`, "waiting" -> calmer pose) and nothing in the view changes.
- **Mascot rendering:** pure SwiftUI shapes/`Path` + a `TimelineView(.animation)` clock - zero assets, zero deps. Continuous wobble/breathe/glow/blink come from `MochiPose.at(t,for:)` (bounded sin curves so a mood switch never jumps). Discrete face features (eye/mouth styles, cheeks, accent) crossfade via animatable opacities driven off an `@State mood` updated in `withAnimation`, so mood changes glide rather than snap. Reduce Motion (`accessibilityReduceMotion`) drops the per-frame `TimelineView` for a still pose.
- **Claude session detection:** enumerate processes via `ps -axww -o pid=,args=`, keep those whose argv[0] basename is `claude`. Subcommand invocations (`claude mcp login`, `claude config`, ...) are excluded by the rule "argv[1] must be a flag (`-`-prefixed) or absent" - their first arg is a bareword. Project name = basename of each pid's cwd, resolved in one `lsof -a -d cwd -p <csv> -Fpn` call. Count-only is the floor; project name is best-effort (unresolved cwd -> generic `session` bucket). Poll interval 3s.
- **Notch detection:** `screen.safeAreaInsets.top > 0` => notch present; notch width = `frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width`. No notch => top-center pill (all corners rounded, small top gap).
- **Premium seam:** each feature is a self-contained widget folder. Future premium widgets (notifications, fleet view, themes) get their own folder and are gated behind a license check at the point they're added to `NotchView` - the notch shell stays feature-agnostic. No paywall exists yet.

## Sharp edges

- **Hover-region oscillation trap:** `.onHover` (backed by `NSTrackingArea`) fires spurious `mouseExited` events at intermediate window sizes while AppKit animates the panel frame. Without a grace window, this creates an expand/collapse loop: hover → expand starts → transient exit → collapse starts → re-enter → loop. Fix: `NotchWindowController.handleHoverChange` defers the collapse by 0.25 s (> animation duration 0.22 s) via a cancellable `DispatchWorkItem`; `mouseEntered` cancels it immediately so real exit still collapses promptly. Do NOT remove or shorten the delay - the 0.25 s is load-bearing.
- **Panel frame animation - use `panel.animator().setFrame` not `setFrame(animate:)`:** `NSWindow.setFrame(_:display:animate:)` with `animate: true` uses `NSWindow.animationResizeTime`, ignoring any enclosing `NSAnimationContext`. To honor `NSAnimationContext` duration/curve (easeOut 0.22 s), use `panel.animator().setFrame(frame, display: true)` inside `NSAnimationContext.runAnimationGroup`. This routes through Core Animation and matches the SwiftUI content animation.
- **Top-anchor invariant:** `positionPanel` always computes `originY = screen.maxY - size.height - topGap`, so `originY + height = screen.maxY - topGap` is constant regardless of panel size. This pins the top edge under the notch and makes the panel grow downward. Any refactor that changes `originY` without preserving this invariant will break the anchor.


- AppleScript MUST guard every call with `if application "Spotify" is running` - a bare `tell application "Spotify"` auto-launches Spotify.
The guard also keeps a closed Spotify silent (idle state, no error spam).
- `NSAppleScript` runs on a dedicated serial queue (not main); results published back to main.
Artwork is fetched from `artwork url` and cached per track id.
- **Apple Events on macOS 26 require hardened runtime + entitlement (ROOT CAUSE OF "prompt never fires"):** On macOS 26 (26.5.1, confirmed 2026-06-25), the OS blocks outgoing Apple Events for apps without hardened runtime (`--options runtime`) AND the `com.apple.security.automation.apple-events` entitlement. Without both:
  - The app never appears in System Settings > Privacy > Automation (TCC never records it).
  - No prompt fires.
  - Every Apple Event silently returns -1743 (`errAEEventNotPermitted`).
  - `osascript` works fine because CLI tools are unaffected; only app binaries with hardened runtime are subject to this gate.
  Fix: `codesign --force --deep --options runtime --entitlements notchmate/notchmate.entitlements --sign - <app>`.
  The entitlements file lives at `notchmate/notchmate.entitlements` and contains only `com.apple.security.automation.apple-events = true`.
  The xcodeproj now sets `ENABLE_HARDENED_RUNTIME = YES` and `CODE_SIGN_ENTITLEMENTS = notchmate/notchmate.entitlements` so Xcode IDE builds get this automatically.
  **Rebuild caveat:** ad-hoc identity = binary hash, so it changes each time you rebuild. macOS will re-prompt after each fresh build. Stable Developer ID signing eliminates re-prompts permanently.
- **Spotify Automation TCC flow:** the TCC prompt fires on the first poll where Spotify is running (the `tell application "Spotify"` block sends the Apple Event).
`NSAppleEventsUsageDescription` is set in Info.plist.
`SpotifyController.executeScript` logs all errors with `NSLog("[SpotifyController] AppleScript error %d: %@")` so failures are diagnosable in Console.app.
Error -1743 (`errAEEventNotPermitted`) means TCC was explicitly denied; `SpotifyController.permissionDenied` is set to `true` and `SpotifyWidget.idleView` shows a tappable **"Allow Spotify access"** button that calls `SpotifyController.openAutomationSettings()` (opens Privacy & Security > Automation) rather than showing a misleading "Nothing playing".
Do NOT swallow -1743 as idle state - the two are semantically different and the widget must surface the distinction.
If TCC is denied after the first prompt, the user must re-enable under **System Settings > Privacy & Security > Automation > notchmate > Spotify**.
- **FocusTimerController.start() is the user action, not a controller init:** `FocusTimerController` has no background polling; its `start()` method begins the countdown and is called by user interaction only.
Do NOT call `focus.start()` from `NotchWindowController.show()` - that bug caused the Pomodoro to auto-start on launch.
The controller needs no explicit initialization; it is fully ready from its property defaults.
- **Claude session branch resolution:** `ClaudeSessionsController.detect()` calls `resolveBranches` after `resolveCwds`, running one `git -C <dir> rev-parse --abbrev-ref HEAD` per session dir.
`ClaudeSession` carries `branch: String?`; detached HEAD and non-git dirs produce `nil` (the widget omits the branch label).
The expanded widget shows individual sessions (not project groups) with project name + branch in monospaced accent text.
`NotchWindowController.currentExpandedSize` uses `claude.count` (session count) not `claude.groups.count` for height calculation.
- Claude session detection needs NO TCC permission, but it DOES depend on the app being **un-sandboxed** (no App Sandbox entitlement): enabling App Sandbox would block enumerating other users'/processes' info via `ps`/`lsof` and silently zero the count.
The controller swallows all `ps`/`lsof` launch/exit failures and degrades to "no sessions" - never throws or spams.
- `GitController` invokes `/usr/bin/git`. On a machine without Xcode Command Line Tools this shim exits non-zero / empty; `read()` gates on a non-empty `rev-parse --show-toplevel` and returns `nil`, so the widget just hides.
It only checks `terminationStatus == 0` per call - no error spam.
- Focus timer notifications use `UNUserNotificationCenter`, which needs a real bundle id (we have `com.notchmate.app`).
Authorization is requested lazily on first Start; denial is ignored (countdown still works).
For local **unsigned** builds the banner may not appear until the app is signed/trusted - the timer logic is unaffected.
No Info.plist key is required for local notifications.
- **Settings window:** open via the menu-bar status item ("Settings...") or the Quit entry.
`SettingsWindowController` is created once by `AppDelegate` and shared with `StatusBarController`.
The window is an `NSWindow` (`isReleasedWhenClosed = false`) so it survives close; `show()` calls `NSApp.activate(ignoringOtherApps: true)` to bring it forward in the LSUIElement activation model.
- **Extensible preferences store - `NotchPreferences`:** a singleton `ObservableObject` in `Settings/NotchPreferences.swift`.
Add new preference fields as `@Published var foo: T` with `didSet { UserDefaults.standard.set(...) }` + a `init` read.
Bind them in any pane view with `@ObservedObject private var prefs = NotchPreferences.shared`.
The `launchAtLogin` property is intentionally computed (no backing `@Published`) - it reads the real `SMAppService.mainApp.status` and calls `register()`/`unregister()`; errors are logged via `NSLog` and the toggle reflects true state.
- **SMAppService.mainApp in unsigned builds:** `register()` throws in unsigned/headless builds; the toggle will flip back immediately because the `get` reflects real state.
This is correct behavior - do not fake a persisted bool for this toggle.
- **MediaRemote (private framework) on macOS 26 - restricted:** `MRMediaRemoteGetNowPlayingInfo` (`Media/MediaController.swift`, `SystemNowPlayingController`) is loaded at runtime via `dlopen`/`dlsym` from `/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote`. On macOS 26 (26.5.1, confirmed 2026-06-25), the binary lives in the dyld shared cache (not on disk) but `dlopen` of the framework path still resolves through the shared cache - the function pointer is obtained successfully.
However, `MRMediaRemoteGetNowPlayingInfo` returns nil to its callback for apps without the private `com.apple.mediaremote` entitlement (reserved for first-party Apple apps). This means "Now Playing (any app)" will consistently show "Nothing playing" on macOS 15.4+ and macOS 26, even when music IS actively playing from another app.
The `SystemNowPlayingController` sets `unavailable = true` only when `dlopen`/`dlsym` completely fails (framework truly absent from shared cache). A nil callback result is treated as "nothing playing" - indistinguishable from silence.
`MRMediaRemoteSendCommand` (transport for the system NP source) is similarly a silent no-op on macOS 26 without entitlements.
**Consequence:** "Now Playing (any app)" is effectively non-functional on macOS 26. `MediaPane` surfaces a platform-version warning. Spotify source remains fully functional and is the recommended default.
- **MediaController and media source switching:** `NotchWindowController` owns one `MediaController` which wraps both `SpotifyController` and `SystemNowPlayingController`. Both controllers start polling on `show()` regardless of active source, so switching sources in Settings is instant. `rebind()` cancels old Combine subscriptions and creates new ones for the new source; it also seeds initial values immediately to prevent a stale-data flash.
