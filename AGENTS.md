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
- **Claude session detection:** enumerate processes via `ps -axww -o pid=,args=`, keep those whose argv[0] basename is `claude`. Subcommand invocations (`claude mcp login`, `claude config`, ...) are excluded by the rule "argv[1] must be a flag (`-`-prefixed) or absent" - their first arg is a bareword. Project name = basename of each pid's cwd, resolved in one `lsof -a -d cwd -p <csv> -Fpn` call. Count-only is the floor; project name is best-effort (unresolved cwd -> generic `session` bucket). Poll interval 3s.
- **Notch detection:** `screen.safeAreaInsets.top > 0` => notch present; notch width = `frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width`. No notch => top-center pill (all corners rounded, small top gap).
- **Premium seam:** each feature is a self-contained widget folder. Future premium widgets (notifications, fleet view, themes) get their own folder and are gated behind a license check at the point they're added to `NotchView` - the notch shell stays feature-agnostic. No paywall exists yet.

## Sharp edges

- AppleScript MUST guard every call with `if application "Spotify" is running` - a bare `tell application "Spotify"` auto-launches Spotify. The guard also keeps a closed Spotify silent (idle state, no error spam).
- `NSAppleScript` runs on a dedicated serial queue (not main); results published back to main. Artwork is fetched from `artwork url` and cached per track id.
- Automation TCC prompt fires on first transport/poll; `NSAppleEventsUsageDescription` is set in Info.plist.
- Claude session detection needs NO TCC permission, but it DOES depend on the app being **un-sandboxed** (no App Sandbox entitlement): enabling App Sandbox would block enumerating other users'/processes' info via `ps`/`lsof` and silently zero the count. The controller swallows all `ps`/`lsof` launch/exit failures and degrades to "no sessions" - never throws or spams.
