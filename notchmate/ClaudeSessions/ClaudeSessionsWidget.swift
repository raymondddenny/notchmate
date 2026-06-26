import SwiftUI

extension SessionStatus {
    var color: Color {
        switch self {
        case .running: return Theme.statusRunning
        case .waiting: return Theme.statusWaiting
        case .idle:    return Theme.statusIdle
        }
    }
    var label: String {
        switch self {
        case .running: return "running"
        case .waiting: return "waiting"
        case .idle:    return "ready"
        }
    }
}

/// A single traffic-light dot, optionally glowing for the active (running/waiting) states.
private struct StatusLight: View {
    let status: SessionStatus
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
            .shadow(color: status.color.opacity(status == .idle ? 0 : 0.7),
                    radius: status == .idle ? 0 : size * 0.45)
    }
}

/// Live Claude Code session indicator, driven by hook-written status files. Collapsed: a
/// row of traffic-light dots (one per session). Expanded: a per-session list with a light,
/// project + branch, and status text. Renders nothing when there are no sessions, so the
/// notch stays quiet and the widget claims no space.
struct ClaudeSessionsWidget: View {
    @ObservedObject var sessions: ClaudeSessionsController
    let expanded: Bool
    /// Expanded tile (and collapsed chip) is clickable: opens the Claude Sessions settings
    /// pane (manage/stop).
    var onTap: (() -> Void)? = nil

    var body: some View {
        Group {
            if sessions.count > 0 {
                if expanded { expandedTile } else { collapsedView }
            } else {
                EmptyView()
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Expanded tile (tappable)

    @ViewBuilder
    private var expandedTile: some View {
        if let onTap {
            Button(action: onTap) { expandedView }
                .buttonStyle(.plain)
                .help("Open Claude Sessions settings to manage or stop a session")
        } else {
            expandedView
        }
    }

    // MARK: - Collapsed (traffic-light dots)

    private var collapsedView: some View {
        // Up to 4 dots; if more sessions, a "+N" follows so the strip stays compact.
        let shown = Array(sessions.sessions.prefix(4))
        let extra = sessions.count - shown.count
        return HStack(spacing: Theme.sp1) {
            ForEach(shown) { session in
                StatusLight(status: session.status, size: 7)
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .help(summary)
    }

    // MARK: - Expanded

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: Theme.sp1 + 2) {
            HStack(spacing: Theme.sp1 + 2) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentClaude)
                Text(summary)
                    .font(Theme.primaryFont)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if onTap != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            VStack(alignment: .leading, spacing: Theme.sp1) {
                ForEach(Array(sessions.sessions.prefix(3))) { session in
                    sessionRow(session)
                }
                if sessions.count > 3 {
                    Text("+\(sessions.count - 3) more")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.leading, Theme.sp3 + 2)
                }
            }
        }
    }

    private func sessionRow(_ session: ClaudeSession) -> some View {
        HStack(spacing: Theme.sp1 + 2) {
            StatusLight(status: session.status, size: 8)
            Text(session.displayName)
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
            Text(session.status.label)
                .font(Theme.captionFont)
                .foregroundStyle(session.status.color)
        }
    }

    /// Glanceable summary: "2 running, 1 waiting" style, only non-zero buckets.
    private var summary: String {
        var parts: [String] = []
        if sessions.runningCount > 0 { parts.append("\(sessions.runningCount) running") }
        if sessions.waitingCount > 0 { parts.append("\(sessions.waitingCount) waiting") }
        if sessions.idleCount > 0 { parts.append("\(sessions.idleCount) ready") }
        if parts.isEmpty { return "\(sessions.count) Claude session\(sessions.count == 1 ? "" : "s")" }
        return parts.joined(separator: ", ")
    }
}
