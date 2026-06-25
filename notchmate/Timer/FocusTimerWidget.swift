import SwiftUI

/// Focus-timer widget. Collapsed: a compact countdown while running/paused, else hidden.
/// Expanded: the time plus start/pause and reset controls (always shown so the user has
/// a place to begin a session).
struct FocusTimerWidget: View {
    @ObservedObject var timer: FocusTimerController
    let expanded: Bool

    private static let accent = Color(red: 0.95, green: 0.45, blue: 0.45) // tomato

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
        HStack(spacing: 5) {
            Image(systemName: "timer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Self.accent)
            Text(timer.display)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .opacity(timer.phase == .paused ? 0.55 : 1)
        }
    }

    // MARK: - Expanded

    private var expandedView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Focus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text(timer.display)
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .opacity(timer.phase == .paused ? 0.55 : 1)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
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
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(filled ? Self.accent : Color.white.opacity(0.12))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
