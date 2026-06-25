import Combine
import Foundation
import UserNotifications

/// A classic Pomodoro-style focus timer (default 25 min). Pure Combine/Timer, no deps.
/// Drives start/pause/reset from the expanded notch and fires a local notification when
/// an interval completes. Notification authorization is requested lazily on first start
/// and degrades quietly if denied (the countdown still works).
final class FocusTimerController: ObservableObject {
    enum Phase: Equatable { case idle, running, paused }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var remaining: Int = FocusTimerController.workDuration
    /// True for ~2s after a work interval reaches zero. Drives the in-tile celebration overlay.
    @Published private(set) var showingCelebration = false
    /// Streak value captured at the moment of completion (used by the celebration overlay).
    @Published private(set) var celebrationStreak: Int = 0

    static let workDuration = 25 * 60   // seconds

    private var timer: Timer?
    private var authRequested = false

    /// True whenever the timer should be shown collapsed (running or paused mid-session).
    var isActive: Bool { phase != .idle }

    /// "MM:SS" for display.
    var display: String { FocusTimerController.format(remaining) }

    static func format(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: - Controls

    func startOrPause() {
        if phase == .running { pause() } else { start() }
    }

    func start() {
        requestAuthIfNeeded()
        showingCelebration = false
        if remaining <= 0 { remaining = Self.workDuration }
        phase = .running
        restartTicker()
    }

    func pause() {
        guard phase == .running else { return }
        phase = .paused
        timer?.invalidate(); timer = nil
    }

    func reset() {
        timer?.invalidate(); timer = nil
        phase = .idle
        remaining = Self.workDuration
    }

    // MARK: - Internals

    private func restartTicker() {
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard remaining > 1 else { complete(); return }
        remaining -= 1
    }

    private func complete() {
        timer?.invalidate(); timer = nil
        phase = .idle
        remaining = Self.workDuration

        let prefs = NotchPreferences.shared
        prefs.recordCompletedSession()
        celebrationStreak = prefs.focusCurrentStreak
        showingCelebration = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.showingCelebration = false
        }

        notify()
    }

    private func requestAuthIfNeeded() {
        guard !authRequested else { return }
        authRequested = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify() {
        let content = UNMutableNotificationContent()
        let streak = celebrationStreak
        content.title = streak > 1 ? "Focus complete \u{1F525}" : "Focus complete"
        content.body = streak > 1
            ? "Session done. \(streak)-day streak - keep it up!"
            : "25-minute session done. Take a break."
        content.sound = .default
        let req = UNNotificationRequest(identifier: "notchmate.focus.\(UUID().uuidString)",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

#if DEBUG
    /// Self-check for formatting + reset state. Runnable (called from the widget preview).
    static func runSelfCheck() {
        assert(format(0) == "00:00")
        assert(format(25 * 60) == "25:00")
        assert(format(83) == "01:23")
        let c = FocusTimerController()
        assert(c.phase == .idle && c.remaining == workDuration)
        c.reset()
        assert(c.phase == .idle && c.remaining == workDuration)
    }
#endif
}
