import SwiftUI

/// Live Claude Code session indicator. Collapsed: a glyph + session count. Expanded:
/// a short per-project list. Renders nothing when there are no sessions, so the notch
/// stays quiet and the widget claims no space.
struct ClaudeSessionsWidget: View {
    @ObservedObject var sessions: ClaudeSessionsController
    let expanded: Bool

    var body: some View {
        Group {
            if sessions.count > 0 {
                if expanded { expandedView } else { collapsedView }
            } else {
                EmptyView()
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Collapsed

    private var collapsedView: some View {
        HStack(spacing: Theme.sp1 + 1) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accentClaude)
            Text("\(sessions.count)")
                .font(Theme.chipMonoFont)
                .monospacedDigit()
        }
    }

    // MARK: - Expanded

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: Theme.sp1 + 2) {
            HStack(spacing: Theme.sp1 + 2) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentClaude)
                Text("\(sessions.count) Claude session\(sessions.count == 1 ? "" : "s")")
                    .font(Theme.primaryFont)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: Theme.sp1 - 1) {
                ForEach(Array(sessions.sessions.prefix(3))) { session in
                    HStack(spacing: Theme.sp1 + 2) {
                        Circle()
                            .fill(Theme.accentClaude)
                            .frame(width: 4, height: 4)
                        Text(session.project ?? "session")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary.opacity(0.85))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let branch = session.branch {
                            Text(branch)
                                .font(.system(size: 11).monospaced())
                                .foregroundStyle(Theme.accentClaude.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if sessions.count > 3 {
                    Text("+\(sessions.count - 3) more")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, Theme.sp3 - 2)
                }
            }
        }
    }
}
