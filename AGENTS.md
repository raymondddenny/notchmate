# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.

## Build

- Native macOS app, Swift + SwiftUI, deployment target macOS 14. Hand-authored `.xcodeproj` (no CocoaPods/Carthage/SPM deps; zero third-party).
- Headless build: `xcodebuild -project notchmate.xcodeproj -scheme notchmate -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build`. Output: `build/Build/Products/Release/notchmate.app`.
- `Info.plist` is checked in and wired via `INFOPLIST_FILE` with `GENERATE_INFOPLIST_FILE = NO`. `LSUIElement = true` (no dock icon / agent app), so the app has no standard window - all UI is the NSPanel.

## Architecture

- `App/` - `@main` App + AppDelegate; AppDelegate sets activation policy `.accessory` and owns one `NotchWindowController`.
- `Notch/` - `NotchPanel` (borderless non-activating NSPanel at `.statusBar` level), `NotchWindowController` (screen/notch geometry + collapsed/expanded resize), `NotchView` (root SwiftUI, hover -> expand).
- `Spotify/` - `SpotifyController` (ObservableObject; AppleScript poll + transport) and `SpotifyWidget` (collapsed/expanded/idle SwiftUI).
- `ClaudeSessions/` - `ClaudeSessionsController` (ObservableObject; polls live `claude` processes off-main, publishes `[ClaudeSession]` + a project grouping) and `ClaudeSessionsWidget` (collapsed count glyph / expanded per-project list; renders nothing at zero). Free-tier, no license gate.
- `Mochi/` - the mascot. `MochiMood` (pure enum + `derive` + per-mood accent color; no UI deps) and `MochiView` (code-drawn SwiftUI mochi-robot; no controller of its own - it observes the existing Spotify/Claude controllers). Free-tier, no license gate.
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

- AppleScript MUST guard every call with `if application "Spotify" is running` - a bare `tell application "Spotify"` auto-launches Spotify. The guard also keeps a closed Spotify silent (idle state, no error spam).
- `NSAppleScript` runs on a dedicated serial queue (not main); results published back to main. Artwork is fetched from `artwork url` and cached per track id.
- Automation TCC prompt fires on first transport/poll; `NSAppleEventsUsageDescription` is set in Info.plist.
- Claude session detection needs NO TCC permission, but it DOES depend on the app being **un-sandboxed** (no App Sandbox entitlement): enabling App Sandbox would block enumerating other users'/processes' info via `ps`/`lsof` and silently zero the count. The controller swallows all `ps`/`lsof` launch/exit failures and degrades to "no sessions" - never throws or spams.
- `GitController` invokes `/usr/bin/git`. On a machine without Xcode Command Line Tools this shim exits non-zero / empty; `read()` gates on a non-empty `rev-parse --show-toplevel` and returns `nil`, so the widget just hides. It only checks `terminationStatus == 0` per call - no error spam.
- Focus timer notifications use `UNUserNotificationCenter`, which needs a real bundle id (we have `com.notchmate.app`). Authorization is requested lazily on first Start; denial is ignored (countdown still works). For local **unsigned** builds the banner may not appear until the app is signed/trusted - the timer logic is unaffected. No Info.plist key is required for local notifications.
