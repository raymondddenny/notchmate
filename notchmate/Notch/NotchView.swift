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
    @ObservedObject var hud: HUDController
    let hasNotch: Bool
    let topInset: CGFloat
    let onHoverChange: (Bool) -> Void

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
        let modules = prefs.orderedEnabledModules
        let rows = chunkedRows(modules, rowCount: prefs.expandedRowCount)
        return VStack(alignment: .leading, spacing: Theme.tileGap) {
            ForEach(rows.indices, id: \.self) { i in
                moduleRow(rows[i])
            }
        }
    }

    private func moduleRow(_ modules: [LayoutModule]) -> some View {
        HStack(alignment: .top, spacing: Theme.tileGap) {
            ForEach(modules) { module in
                moduleTile(module)
            }
        }
    }

    private func moduleTile(_ module: LayoutModule) -> some View {
        tileContent(module)
            .padding(.horizontal, Theme.sp3)
            .padding(.vertical, Theme.sp2 + 2)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                    .fill(Theme.panelSurface)
            )
    }

    @ViewBuilder
    private func tileContent(_ module: LayoutModule) -> some View {
        switch module {
        case .media:
            MediaWidget(media: media, expanded: true)
        case .mochi:
            HStack {
                Spacer(minLength: 0)
                MochiView(media: media, claude: claude, expanded: true)
                Spacer(minLength: 0)
            }
        case .lyrics:
            LyricsWidget(lyrics: lyrics, expanded: true)
        case .timer:
            FocusTimerWidget(timer: focus, expanded: true)
        case .git:
            GitWidget(git: git, expanded: true)
        case .claude:
            ClaudeSessionsWidget(sessions: claude, expanded: true)
        case .stats:
            SystemStatsWidget(stats: stats, expanded: true)
        }
    }

    // MARK: - Collapsed strip

    // HUD event takes priority for ~1.5s; otherwise widget chips from enabled modules.
    private var collapsedStrip: some View {
        Group {
            if let event = hud.currentEvent {
                HUDView(event: event)
                    .transition(.opacity)
            } else {
                collapsedChips
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: hud.currentEvent != nil)
    }

    private var collapsedChips: some View {
        HStack(spacing: Theme.sp2) {
            if prefs.enabledModules.contains(.mochi) {
                MochiView(media: media, claude: claude, expanded: false)
            }
            if prefs.enabledModules.contains(.media) {
                MediaWidget(media: media, expanded: false)
            }
            if prefs.enabledModules.contains(.timer) {
                FocusTimerWidget(timer: focus, expanded: false)
            }
            if prefs.enabledModules.contains(.claude) {
                ClaudeSessionsWidget(sessions: claude, expanded: false)
            }
            if prefs.enabledModules.contains(.git) {
                GitWidget(git: git, expanded: false)
            }
            if prefs.enabledModules.contains(.stats) {
                SystemStatsWidget(stats: stats, expanded: false)
            }
        }
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
