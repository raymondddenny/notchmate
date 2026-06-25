import SwiftUI

/// Focus-timer widget. Collapsed: a compact countdown while running/paused, else hidden.
/// Expanded: the time plus start/pause and reset controls (always shown so the user has
/// a place to begin a session).
struct FocusTimerWidget: View {
    @ObservedObject var timer: FocusTimerController
    let expanded: Bool

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
        HStack(spacing: Theme.sp3) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Focus")
                    .font(Theme.labelFont)
                    .foregroundStyle(Theme.textSecondary)
                Text(timer.display)
                    .font(.system(size: 16, weight: .semibold))
                    .monospacedDigit()
                    .opacity(timer.phase == .paused ? 0.55 : 1)
            }
            Spacer(minLength: 0)
            HStack(spacing: Theme.sp2) {
                pill(timer.phase == .running ? "Pause" : "Start",
                     filled: true) { timer.startOrPause() }
                pill("Reset", filled: false) { timer.reset() }
                    .disabled(timer.phase == .idle && timer.remaining == FocusTimerController.workDuration)
            }
        }
    }

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
