import SwiftUI

/// Git glance for the focused repo. Collapsed: branch name + a dirty/clean dot.
/// Expanded: repo + branch, clean/modified label, and ahead/behind when set. Renders
/// nothing when there is no repo in context, so the notch stays quiet.
struct GitWidget: View {
    @ObservedObject var git: GitController
    let expanded: Bool

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
        HStack(spacing: Theme.sp1 + 1) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accentGit)
            Text(s.branch)
                .font(Theme.chipFont)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 84, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
            Circle()
                .fill(s.dirty ? Self.dirtyColor : Self.cleanColor)
                .frame(width: 5, height: 5)
        }
    }

    // MARK: - Expanded

    private func expandedView(_ s: GitState) -> some View {
        VStack(alignment: .leading, spacing: Theme.sp1) {
            HStack(spacing: Theme.sp1 + 2) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentGit)
                Text(s.branch)
                    .font(Theme.primaryFont)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Circle()
                    .fill(s.dirty ? Self.dirtyColor : Self.cleanColor)
                    .frame(width: 5, height: 5)
                Spacer(minLength: 0)
                if s.ahead > 0 || s.behind > 0 {
                    aheadBehind(s)
                }
            }
            HStack(spacing: Theme.sp1 + 2) {
                Text(s.repo)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("·")
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textDisabled)
                Text(s.dirty ? "modified" : "clean")
                    .font(Theme.secondaryFont)
                    .foregroundStyle((s.dirty ? Self.dirtyColor : Self.cleanColor).opacity(0.85))
                Spacer(minLength: 0)
            }
        }
    }

    private func aheadBehind(_ s: GitState) -> some View {
        HStack(spacing: Theme.sp1 + 2) {
            if s.ahead > 0 {
                Label("\(s.ahead)", systemImage: "arrow.up")
                    .labelStyle(.titleAndIcon)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }
            if s.behind > 0 {
                Label("\(s.behind)", systemImage: "arrow.down")
                    .labelStyle(.titleAndIcon)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
