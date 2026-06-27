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
    /// Signals the desired expanded state to the window controller so it can resize
    /// the panel. Driven by the explicit expand button (true) and mouse-exit (false),
    /// no longer by raw hover.
    let onExpandChange: (Bool) -> Void
    /// Opens Settings to the Claude Sessions pane (invoked from the Claude tile).
    var onOpenClaudeSettings: () -> Void = {}

    @State private var hovering = false
    @State private var expanded = false
    /// Deferred collapse, mirroring NotchWindowController's grace window: absorbs the
    /// spurious mouseExited AppKit fires while the panel animates through intermediate
    /// sizes on expand. A real re-enter cancels it; a real exit collapses after the delay.
    @State private var collapseTask: DispatchWorkItem?
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
            // Hover only reveals the expand button now; it never auto-expands.
            if isHovering {
                // Real re-enter (or the re-enter that immediately follows a transient
                // exit during the expand animation) cancels a pending collapse.
                collapseTask?.cancel()
                collapseTask = nil
            } else {
                // Defer the collapse so a spurious mouseExited fired mid-expand-animation
                // does not snap the panel shut right after the expand button is clicked.
                let task = DispatchWorkItem {
                    expanded = false
                    onExpandChange(false)
                }
                collapseTask = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
            }
        }
        .animation(.easeOut(duration: 0.22), value: expanded)
        .animation(.easeOut(duration: 0.15), value: hovering)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if expanded {
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

    // HUD events appear in a separate panel below the notch (see NotchWindowController).
    // The current synced lyric line is folded into a second row beneath the chips; the
    // window controller grows the collapsed panel to fit it (see refitCollapsedForLyric).
    private var collapsedStrip: some View {
        VStack(spacing: Theme.sp1) {
            collapsedChips
            if prefs.visibleModules.contains(.media), lyrics.currentLine != nil {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    LyricLineView(lyrics: lyrics)
                }
                .padding(.horizontal, Theme.sp3)
                .padding(.bottom, Theme.sp1)
            }
        }
    }

    private var collapsedChips: some View {
        // Mascot is pinned to the left edge of the strip; the glanceable chips group to
        // the right. On a notch Mac this flanks the physical notch (mascot left, chips
        // right) instead of crowding everything under the center.
        let visible = Set(prefs.visibleModules)
        return HStack(spacing: Theme.sp2) {
            if prefs.mascotEnabled {
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
            expandButton
        }
        .frame(maxWidth: .infinity)
    }

    /// Trailing affordance that expands the panel. Only visible while hovering -
    /// expansion is now click-driven (hover no longer auto-expands).
    private var expandButton: some View {
        Button {
            collapseTask?.cancel()
            collapseTask = nil
            expanded = true
            onExpandChange(true)
        } label: {
            Image(systemName: "chevron.down")
                .font(Theme.chipFont)
                .foregroundColor(Theme.textSecondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(hovering ? 1 : 0)
        .allowsHitTesting(hovering)
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
