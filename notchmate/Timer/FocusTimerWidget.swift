import SwiftUI

/// Focus-timer widget. Collapsed: a compact countdown while running/paused, else hidden.
/// Expanded: timer controls on the left, contribution heatmap + streak stats on the right.
/// Completion triggers a 2-second celebration overlay (respects Reduce Motion).
struct FocusTimerWidget: View {
    @ObservedObject var timer: FocusTimerController
    let expanded: Bool

    @ObservedObject private var prefs = NotchPreferences.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if expanded {
                expandedView
            } else if timer.isActive {
                collapsedView
            } else {
                EmptyView()
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Collapsed

    private var collapsedView: some View {
        HStack(spacing: Theme.sp1 + 1) {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accentTimer)
            Text(timer.display)
                .font(Theme.chipMonoFont)
                .monospacedDigit()
                .opacity(timer.phase == .paused ? 0.55 : 1)
        }
    }

    // MARK: - Expanded

    private var expandedView: some View {
        ZStack {
            if timer.showingCelebration {
                CelebrationView(streak: timer.celebrationStreak)
                    .transition(.opacity)
            } else {
                mainExpandedView
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: timer.showingCelebration)
    }

    private var mainExpandedView: some View {
        HStack(alignment: .top, spacing: Theme.sp3) {
            // Left: timer label + countdown + controls
            VStack(alignment: .leading, spacing: 2) {
                Text("Focus")
                    .font(Theme.labelFont)
                    .foregroundStyle(Theme.textSecondary)
                Text(timer.display)
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .opacity(timer.phase == .paused ? 0.55 : 1)
                Spacer(minLength: 0)
                HStack(spacing: Theme.sp2) {
                    pill(timer.phase == .running ? "Pause" : "Start", filled: true) {
                        timer.startOrPause()
                    }
                    pill("Reset", filled: false) { timer.reset() }
                        .disabled(
                            timer.phase == .idle &&
                            timer.remaining == FocusTimerController.workDuration
                        )
                }
            }

            Spacer(minLength: 0)

            // Right: heatmap + streak stats
            FocusStatsView(
                history: prefs.focusDailyHistory,
                streak: prefs.focusCurrentStreak,
                today: prefs.focusSessionsToday,
                total: prefs.focusSessionsTotal
            )
        }
    }

    // MARK: - Button pill

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(filled ? Color.black : .white)
                .padding(.horizontal, Theme.sp3)
                .padding(.vertical, Theme.sp1 + 1)
                .background(
                    Capsule().fill(filled ? Theme.accentTimer : Theme.trackBackground)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Celebration overlay

/// Brief (~2s) reward shown when a session completes. Fades in/out (opacity transition
/// on the parent ZStack). Reduce Motion: static display, no scale animation.
private struct CelebrationView: View {
    let streak: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var checkmarkScale: CGFloat = 0.4

    var body: some View {
        HStack(spacing: Theme.sp3) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.accentTimer)
                .scaleEffect(reduceMotion ? 1.0 : checkmarkScale)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.55),
                    value: checkmarkScale
                )
                .onAppear {
                    if !reduceMotion { checkmarkScale = 1.0 }
                }

            VStack(alignment: .leading, spacing: 3) {
                Text("+1 session")
                    .font(Theme.labelFont)
                    .foregroundStyle(Theme.accentTimer)
                Text("Complete!")
                    .font(Theme.primaryFont)
                if streak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accentTimer)
                        Text("\(streak) day streak")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .font(Theme.labelFont)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}
