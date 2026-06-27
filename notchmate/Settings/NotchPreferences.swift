import Combine
import Foundation
import ServiceManagement

// MARK: - LayoutModule

/// Identifies each expandable panel widget. Order + enabled state are persisted by
/// NotchPreferences so the user can reorder and toggle modules in Settings > Layout.
enum LayoutModule: String, CaseIterable, Identifiable {
    // Lyrics are no longer a standalone module: the current line is folded into the
    // unified Media Player tile (see MediaWidget). The `lyrics` case was removed; saved
    // preferences referencing it are dropped harmlessly by the rawValue compactMap.
    // The mascot is also not a module: it is collapsed-strip-only (see `mascotEnabled`),
    // so a stale "mochi" raw value from older builds is dropped harmlessly too.
    case media, timer, git, claude, stats
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .media:  return "Media Player"
        case .timer:  return "Focus Timer"
        case .git:    return "Git Status"
        case .claude: return "Claude Sessions"
        case .stats:  return "System Stats"
        }
    }

    /// One-line description shown under the module name in Settings > Layout.
    var summary: String {
        switch self {
        case .media:  return "Now playing, transport, and live lyrics"
        case .timer:  return "Pomodoro timer with focus streak heatmap"
        case .git:    return "Branch and status of the focused repo"
        case .claude: return "Live Claude Code sessions (click to manage)"
        case .stats:  return "CPU and memory usage"
        }
    }

    var icon: String {
        switch self {
        case .media:  return "music.note"
        case .timer:  return "timer"
        case .git:    return "arrow.triangle.branch"
        case .claude: return "sparkles"
        case .stats:  return "cpu"
        }
    }
}

// MARK: - Supporting enums

enum MascotCharacter: String, CaseIterable {
    case mochi  = "mochi"
    case ducky2 = "ducky2"
    case ducky3 = "ducky3"

    var displayName: String {
        switch self {
        case .mochi:  return "Mochi"
        case .ducky2: return "Ducky"
        case .ducky3: return "Ducky (Alt)"
        }
    }
}

enum MediaSource: String {
    case spotify    = "spotify"
    case spotifyWeb = "spotifyWeb"
    case nowPlaying = "nowPlaying"
}

enum MusicLayout: String {
    case artwork = "artwork"
    case compact = "compact"
}

// MARK: - NotchPreferences

/// Shared preferences store. All panes bind to this; persist via UserDefaults.
/// Add new fields here as later panes require them.
final class NotchPreferences: ObservableObject {
    static let shared = NotchPreferences()

    // MARK: - Layout module defaults
    static let defaultModuleOrder: [LayoutModule] = [
        .media, .claude, .timer, .git, .stats
    ]
    static let defaultEnabledModules: Set<LayoutModule> = [.media, .claude, .timer]

    /// Hard cap on how many modules render in the panel at once. The grid is sized for
    /// at most this many tiles; the Layout pane blocks enabling more, and rendering
    /// takes only the first N in order as a defensive backstop.
    static let maxVisibleModules = 3

    // MARK: - Mascot

    @Published var mascotCharacter: MascotCharacter {
        didSet { UserDefaults.standard.set(mascotCharacter.rawValue, forKey: "mascotCharacter") }
    }

    /// Whether the mascot shows in the collapsed strip. The mascot is collapsed-only -
    /// it is no longer a `LayoutModule` and never takes an expanded grid tile.
    @Published var mascotEnabled: Bool {
        didSet { UserDefaults.standard.set(mascotEnabled, forKey: "mascotEnabled") }
    }

    // MARK: - General

    @Published var showMenuBarIcon: Bool {
        didSet { UserDefaults.standard.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }

    // MARK: - Media

    @Published var mediaSource: MediaSource {
        didSet { UserDefaults.standard.set(mediaSource.rawValue, forKey: "mediaSource") }
    }

    @Published var musicLayout: MusicLayout {
        didSet { UserDefaults.standard.set(musicLayout.rawValue, forKey: "musicLayout") }
    }

    @Published var showLyrics: Bool {
        didSet { UserDefaults.standard.set(showLyrics, forKey: "showLyrics") }
    }

    // MARK: - HUDs

    @Published var hudVolumeEnabled: Bool {
        didSet { UserDefaults.standard.set(hudVolumeEnabled, forKey: "hudVolumeEnabled") }
    }

    @Published var hudBrightnessEnabled: Bool {
        didSet { UserDefaults.standard.set(hudBrightnessEnabled, forKey: "hudBrightnessEnabled") }
    }

    @Published var hudSuppressSystem: Bool {
        didSet {
            UserDefaults.standard.set(hudSuppressSystem, forKey: "hudSuppressSystem")
            // Enabling the master defaults both sub-toggles to ON so the first-run
            // experience works without extra taps. The user can then turn either off.
            if hudSuppressSystem {
                hudVolumeEnabled = true
                hudBrightnessEnabled = true
            }
        }
    }

    // MARK: - Focus stats

    /// Per-day session counts keyed by "YYYY-MM-DD". Source of truth for streak, heatmap.
    @Published var focusDailyHistory: [String: Int] {
        didSet {
            if let data = try? JSONEncoder().encode(focusDailyHistory) {
                UserDefaults.standard.set(data, forKey: "focusDailyHistory")
            }
        }
    }

    /// All-time best streak (consecutive days with >=1 session). Persisted separately
    /// so it survives even if history is trimmed in the future.
    @Published var focusBestStreak: Int {
        didSet { UserDefaults.standard.set(focusBestStreak, forKey: "focusBestStreak") }
    }

    var focusSessionsToday: Int { focusDailyHistory[Self.dateKey()] ?? 0 }
    var focusSessionsTotal: Int { focusDailyHistory.values.reduce(0, +) }
    var focusCurrentStreak: Int { Self.computeStreak(history: focusDailyHistory) }

    /// ISO-8601 date key for `date` (defaults to today). Locale-safe, POSIX calendar.
    static func dateKey(for date: Date = Date()) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.calendar = Calendar(identifier: .iso8601)
        return fmt.string(from: date)
    }

    /// Consecutive days ending today (inclusive) that have >=1 completed session.
    static func computeStreak(history: [String: Int]) -> Int {
        let cal = Calendar(identifier: .iso8601)
        var streak = 0
        var day = cal.startOfDay(for: Date())
        while true {
            let key = dateKey(for: day)
            guard (history[key] ?? 0) >= 1 else { break }
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    /// Call this when a focus work interval reaches zero. Increments today's count,
    /// updates best streak. A completed session = work interval reaches 0; resets/
    /// abandoned timers must NOT call this.
    func recordCompletedSession() {
        focusDailyHistory[Self.dateKey(), default: 0] += 1
        let s = focusCurrentStreak
        if s > focusBestStreak { focusBestStreak = s }
    }

    // MARK: - Layout

    @Published var moduleOrder: [LayoutModule] {
        didSet {
            UserDefaults.standard.set(moduleOrder.map(\.rawValue), forKey: "moduleOrder")
        }
    }

    @Published var enabledModules: Set<LayoutModule> {
        didSet {
            UserDefaults.standard.set(Array(enabledModules.map(\.rawValue)), forKey: "enabledModules")
        }
    }

    /// 1, 2, or 3 rows in the expanded panel grid.
    @Published var expandedRowCount: Int {
        didSet { UserDefaults.standard.set(expandedRowCount, forKey: "expandedRowCount") }
    }

    /// Modules in display order, filtered to only the enabled ones.
    var orderedEnabledModules: [LayoutModule] {
        moduleOrder.filter { enabledModules.contains($0) }
    }

    /// Modules actually rendered in the panel: ordered, enabled, capped at the max.
    var visibleModules: [LayoutModule] {
        Array(orderedEnabledModules.prefix(Self.maxVisibleModules))
    }

    /// Whether another module can still be enabled (cap not yet reached).
    var canEnableMoreModules: Bool {
        enabledModules.count < Self.maxVisibleModules
    }

    // MARK: - Init

    private init() {
        // Phase 1: initialize all backing stores directly so self is fully formed
        // before any property accessor (didSet) can reference self.
        let ud = UserDefaults.standard

        let mascotRaw = ud.string(forKey: "mascotCharacter") ?? "mochi"
        let mascot = MascotCharacter(rawValue: mascotRaw) ?? .mochi
        _mascotCharacter = Published(wrappedValue: mascot)

        // Mascot shows in the collapsed strip by default (it is no longer a layout module).
        let mascotOn = ud.object(forKey: "mascotEnabled") != nil
            ? ud.bool(forKey: "mascotEnabled") : true
        _mascotEnabled = Published(wrappedValue: mascotOn)

        let menuIcon = ud.object(forKey: "showMenuBarIcon") != nil
            ? ud.bool(forKey: "showMenuBarIcon") : true
        _showMenuBarIcon = Published(wrappedValue: menuIcon)

        _mediaSource = Published(wrappedValue: .spotifyWeb)

        let layout: MusicLayout
        if let raw = ud.string(forKey: "musicLayout"), let l = MusicLayout(rawValue: raw) {
            layout = l
        } else {
            layout = .artwork
        }
        _musicLayout = Published(wrappedValue: layout)

        let hudVol = ud.object(forKey: "hudVolumeEnabled") != nil
            ? ud.bool(forKey: "hudVolumeEnabled") : false
        _hudVolumeEnabled = Published(wrappedValue: hudVol)

        let hudBright = ud.object(forKey: "hudBrightnessEnabled") != nil
            ? ud.bool(forKey: "hudBrightnessEnabled") : false
        _hudBrightnessEnabled = Published(wrappedValue: hudBright)

        let hudSuppress = ud.object(forKey: "hudSuppressSystem") != nil
            ? ud.bool(forKey: "hudSuppressSystem") : false
        _hudSuppressSystem = Published(wrappedValue: hudSuppress)

        // Module order: merge saved with defaults so new modules appear at the end.
        let order: [LayoutModule]
        if let arr = ud.array(forKey: "moduleOrder") as? [String] {
            let saved = arr.compactMap { LayoutModule(rawValue: $0) }
            let savedSet = Set(saved)
            let appended = NotchPreferences.defaultModuleOrder.filter { !savedSet.contains($0) }
            order = saved + appended
        } else {
            order = NotchPreferences.defaultModuleOrder
        }
        _moduleOrder = Published(wrappedValue: order)

        // Enabled modules.
        let enabled: Set<LayoutModule>
        if let arr = ud.array(forKey: "enabledModules") as? [String] {
            enabled = Set(arr.compactMap { LayoutModule(rawValue: $0) })
        } else {
            enabled = NotchPreferences.defaultEnabledModules
        }
        _enabledModules = Published(wrappedValue: enabled)

        // Row count.
        let rowCount: Int
        if ud.object(forKey: "expandedRowCount") != nil {
            rowCount = max(1, min(3, ud.integer(forKey: "expandedRowCount")))
        } else {
            rowCount = 2
        }
        _expandedRowCount = Published(wrappedValue: rowCount)

        // showLyrics: lyrics are folded into the Media tile, so they show whenever the
        // Media module is enabled. Gates the LyricsController fetch/poll lifecycle.
        _showLyrics = Published(wrappedValue: enabled.contains(.media))

        // Focus stats.
        let focusHistory = ud.data(forKey: "focusDailyHistory")
            .flatMap { try? JSONDecoder().decode([String: Int].self, from: $0) } ?? [:]
        _focusDailyHistory = Published(wrappedValue: focusHistory)

        let bestStreak = ud.integer(forKey: "focusBestStreak")
        _focusBestStreak = Published(wrappedValue: bestStreak)
    }

    // MARK: - Launch at login

    /// Reads the real SMAppService registration state; setter registers/unregisters.
    /// Reflects actual state so the toggle never lies, even in unsigned builds where
    /// register() will fail (SMAppService.mainApp.status stays .notRegistered).
    /// Non-nil when the last register/unregister threw. Drives a hint in GeneralPane;
    /// the common cause is launching a translocated/Downloads copy - SMAppService can
    /// only persist a login item for an app run from /Applications.
    @Published var launchAtLoginError: String?

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLoginError = nil
            } catch {
                NSLog("[NotchPreferences] SMAppService error: %@", error.localizedDescription)
                launchAtLoginError = error.localizedDescription
            }
            objectWillChange.send()
        }
    }

    // MARK: - Layout helpers

    /// Toggle a module's enabled state, enforcing the visible-module cap, and keep
    /// showLyrics in sync (lyrics live inside the Media tile). Enabling beyond the cap
    /// is a no-op; the Layout pane disables those toggles so this is just a backstop.
    func toggleModule(_ module: LayoutModule) {
        if enabledModules.contains(module) {
            enabledModules.remove(module)
        } else if canEnableMoreModules {
            enabledModules.insert(module)
        }
        if module == .media {
            showLyrics = enabledModules.contains(.media)
        }
    }

    func resetLayoutToDefaults() {
        moduleOrder = NotchPreferences.defaultModuleOrder
        enabledModules = NotchPreferences.defaultEnabledModules
        expandedRowCount = 2
        showLyrics = enabledModules.contains(.media)
    }
}
