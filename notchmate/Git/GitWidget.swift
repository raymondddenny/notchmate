import SwiftUI

/// Git glance for the focused repo. Collapsed: branch name + a dirty/clean dot.
/// Expanded: repo + branch, clean/modified label, and ahead/behind when set. Renders
/// nothing when there is no repo in context, so the notch stays quiet.
struct GitWidget: View {
    @ObservedObject var git: GitController
    let expanded: Bool

    private static let accent = Color(red: 0.55, green: 0.65, blue: 0.95) // git blue
    private static let dirtyColor = Color(red: 0.95, green: 0.70, blue: 0.30) // amber
    private static let cleanColor = Color(red: 0.40, green: 0.80, blue: 0.50) // green

    var body: some View {
        Group {
            if let state = git.state {
                if expanded { expandedView(state) } else { collapsedView(state) }
            } else {
                EmptyView()
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Collapsed

    private func collapsedView(_ s: GitState) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Self.accent)
            Text(s.branch)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 84, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            Circle()
                .fill(s.dirty ? Self.dirtyColor : Self.cleanColor)
                .frame(width: 6, height: 6)
        }
    }

    // MARK: - Expanded

    private func expandedView(_ s: GitState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.accent)
                Text(s.branch)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Circle()
                    .fill(s.dirty ? Self.dirtyColor : Self.cleanColor)
                    .frame(width: 6, height: 6)
                Spacer(minLength: 0)
                if s.ahead > 0 || s.behind > 0 {
                    aheadBehind(s)
                }
            }
            HStack(spacing: 6) {
                Text(s.repo)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                Text(s.dirty ? "modified" : "clean")
                    .font(.system(size: 11))
                    .foregroundStyle((s.dirty ? Self.dirtyColor : Self.cleanColor).opacity(0.9))
                Spacer(minLength: 0)
            }
        }
    }

    private func aheadBehind(_ s: GitState) -> some View {
        HStack(spacing: 6) {
            if s.ahead > 0 {
                Label("\(s.ahead)", systemImage: "arrow.up")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            if s.behind > 0 {
                Label("\(s.behind)", systemImage: "arrow.down")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}
