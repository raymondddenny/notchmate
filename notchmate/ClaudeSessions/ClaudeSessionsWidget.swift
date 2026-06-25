import SwiftUI

/// Live Claude Code session indicator. Collapsed: a glyph + session count. Expanded:
/// a short per-project list. Renders nothing when there are no sessions, so the notch
/// stays quiet and the widget claims no space.
struct ClaudeSessionsWidget: View {
    @ObservedObject var sessions: ClaudeSessionsController
    let expanded: Bool

    private static let accent = Color(red: 0.85, green: 0.52, blue: 0.30) // Claude warm orange

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
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Self.accent)
            Text("\(sessions.count)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
    }

    // MARK: - Expanded

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.accent)
                Text("\(sessions.count) Claude session\(sessions.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 3) {
                let groups = sessions.groups
                ForEach(groups.prefix(3)) { group in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Self.accent)
                            .frame(width: 5, height: 5)
                        Text(group.name)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if group.count > 1 {
                            Text("×\(group.count)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer(minLength: 0)
                    }
                }
                if groups.count > 3 {
                    Text("+\(groups.count - 3) more")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.leading, 11)
                }
            }
        }
    }
}
