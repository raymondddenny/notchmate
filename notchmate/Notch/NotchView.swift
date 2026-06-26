import SwiftUI

/// Root SwiftUI content for the panel. Draws the dark charcoal notch/pill background
/// and hosts feature widgets in a configurable horizontal grid. Hover toggles expanded
/// state and is reported upward so the window controller can resize the panel.
struct NotchView: View {
    @ObservedObject var media: MediaController
    @ObservedObject var claude: ClaudeSessionsController
    @ObservedObject var git: GitController
    @ObservedObject var focus: FocusTimerController
    @ObservedObject var stats: SystemStatsController
    @ObservedObject var lyrics: LyricsController
    let hasNotch: Bool
    let topInset: CGFloat
    let onHoverChange: (Bool) -> Void
    /// Opens Settings to the Claude Sessions pane (invoked from the Claude tile).
    var onOpenClaudeSettings: () -> Void = {}

    @State private var hovering = false
    @ObservedObject private var prefs = NotchPreferences.shared

    var body: some View {
        ZStack(alignment: .top) {
            background
            VStack(spacing: 0) {
                Color.clear.frame(height: topInset)
                content
                    .padding(.horizontal, Theme.panelPadH)
                    .padding(.bottom, Theme.panelPadBottom)
                    .padding(.top, hasNotch ? 2 : Theme.sp2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { isHovering in
            hovering = isHovering
            onHoverChange(isHovering)
        }
        .animation(.easeOut(duration: 0.22), value: hovering)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if hovering {
            expandedGrid
        } else {
            collapsedStrip
        }
    }

    // MARK: - Expanded horizontal grid

    private var expandedGrid: some View {
        let modules = prefs.visibleModules
        let rows = chunkedRows(modules, rowCount: prefs.expandedRowCount)
        return VStack(alignment: .leading, spacing: Theme.tileGap) {
            ForEach(rows.indices, id: \.self) { i in
                moduleRow(rows[i])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func moduleRow(_ modules: [LayoutModule]) -> some View {
        HStack(alignment: .top, spacing: Theme.tileGap) {
            ForEach(modules) { module in
                moduleTile(module)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func moduleTile(_ module: LayoutModule) -> some View {
        tileContent(module)
            .padding(.horizontal, Theme.sp3)
            .padding(.vertical, Theme.sp2 + 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                    .fill(Theme.panelSurface)
            )
    }

    @ViewBuilder
    private func tileContent(_ module: LayoutModule) -> some View {
        switch module {
        case .media:
            // Lyrics are folded into the media tile: pass the controller so the current
            // synced line renders beneath the track info when available.
            MediaWidget(media: media, expanded: true, lyrics: lyrics)
        case .mochi:
            HStack {
                Spacer(minLength: 0)
                MascotView(media: media, claude: claude, expanded: true)
                Spacer(minLength: 0)
            }
        case .timer:
            FocusTimerWidget(timer: focus, expanded: true)
        case .git:
            GitWidget(git: git, expanded: true)
        case .claude:
            ClaudeSessionsWidget(sessions: claude, expanded: true, onTap: onOpenClaudeSettings)
        case .stats:
            SystemStatsWidget(stats: stats, expanded: true)
        }
    }

    // MARK: - Collapsed strip

    // HUD events now appear in a separate panel below the notch (see NotchWindowController).
    private var collapsedStrip: some View {
        collapsedChips
    }

    private var collapsedChips: some View {
        // Mascot is pinned to the left edge of the strip; the glanceable chips group to
        // the right. On a notch Mac this flanks the physical notch (mascot left, chips
        // right) instead of crowding everything under the center.
        let visible = Set(prefs.visibleModules)
        return HStack(spacing: Theme.sp2) {
            if visible.contains(.mochi) {
                MascotView(media: media, claude: claude, expanded: false)
            }
            // Equal spacers on both sides keep the chip cluster centered under the notch
            // while the mascot (when present) sits flush against the left edge.
            Spacer(minLength: Theme.sp2)
            HStack(spacing: Theme.sp3) {
                if visible.contains(.media) {
                    MediaWidget(media: media, expanded: false)
                }
                // Claude collapsed = traffic-light dots (glanceable status at a glance).
                if visible.contains(.claude) {
                    ClaudeSessionsWidget(sessions: claude, expanded: false, onTap: onOpenClaudeSettings)
                }
                if visible.contains(.timer) {
                    FocusTimerWidget(timer: focus, expanded: false)
                }
                if visible.contains(.git) {
                    GitWidget(git: git, expanded: false)
                }
                if visible.contains(.stats) {
                    SystemStatsWidget(stats: stats, expanded: false)
                }
            }
            Spacer(minLength: Theme.sp2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Background

    private var background: some View {
        let topRadius: CGFloat = hasNotch ? 0 : 14
        let bg = UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: 16,
            bottomTrailingRadius: 16,
            topTrailingRadius: topRadius,
            style: .continuous
        )
        return bg
            .fill(Theme.panelBackground)
            .overlay(
                bg.strokeBorder(Theme.panelBorder, lineWidth: 1)
            )
    }

    // MARK: - Layout helpers

    /// Split an ordered module list into N sequential chunks for row distribution.
    private func chunkedRows(_ modules: [LayoutModule], rowCount: Int) -> [[LayoutModule]] {
        guard !modules.isEmpty, rowCount > 0 else { return [] }
        let count = modules.count
        let clampedRows = min(rowCount, count)
        let base = count / clampedRows
        let extras = count % clampedRows
        var result: [[LayoutModule]] = []
        var idx = 0
        for i in 0..<clampedRows {
            let size = base + (i < extras ? 1 : 0)
            if size > 0 && idx < count {
                let end = min(idx + size, count)
                result.append(Array(modules[idx..<end]))
                idx = end
            }
        }
        return result
    }
}
