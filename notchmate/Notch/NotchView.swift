import SwiftUI

/// Root SwiftUI content for the panel. Draws the black notch/pill background and
/// hosts feature widgets. Hover toggles expanded state and is reported upward so the
/// window controller can resize the panel.
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

    @State private var hovering = false
    @ObservedObject private var prefs = NotchPreferences.shared

    var body: some View {
        ZStack(alignment: .top) {
            background
            // Reserve the physical notch region on notch Macs, then lay out content
            // beneath it. On pill Macs topInset is 0.
            VStack(spacing: 0) {
                Color.clear.frame(height: topInset)
                content
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .padding(.top, hasNotch ? 2 : 8)
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

    // Each widget owns its own collapsed/expanded rendering; the shell only chooses
    // the container. Collapsed: a single strip (Claude count trails the media glance).
    // Expanded: stacked blocks. Widgets render nothing when they have no content.
    @ViewBuilder
    private var content: some View {
        if hovering {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    MochiView(media: media, claude: claude, expanded: true)
                    Spacer(minLength: 0)
                }
                MediaWidget(media: media, expanded: true)
                if prefs.showLyrics {
                    LyricsWidget(lyrics: lyrics, expanded: true)
                }
                divider
                FocusTimerWidget(timer: focus, expanded: true)
                if git.state != nil {
                    divider
                    GitWidget(git: git, expanded: true)
                }
                if claude.count > 0 {
                    divider
                    ClaudeSessionsWidget(sessions: claude, expanded: true)
                }
                divider
                SystemStatsWidget(stats: stats, expanded: true)
            }
        } else {
            // Collapsed strip: media takes the flexible space; the rest are compact
            // chips that each show only when they have something worth surfacing.
            HStack(spacing: 10) {
                MochiView(media: media, claude: claude, expanded: false)
                MediaWidget(media: media, expanded: false)
                FocusTimerWidget(timer: focus, expanded: false)
                ClaudeSessionsWidget(sessions: claude, expanded: false)
                GitWidget(git: git, expanded: false)
                SystemStatsWidget(stats: stats, expanded: false)
            }
        }
    }

    private var divider: some View {
        Divider().overlay(Color.white.opacity(0.1))
    }

    private var background: some View {
        // Bottom corners always rounded. Top corners rounded only on pill Macs;
        // on notch Macs the top edge stays square to merge with the screen edge.
        let topRadius: CGFloat = hasNotch ? 0 : 14
        return UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: 16,
            bottomTrailingRadius: 16,
            topTrailingRadius: topRadius,
            style: .continuous
        )
        .fill(Color.black)
        .overlay(
            UnevenRoundedRectangle(
                topLeadingRadius: topRadius,
                bottomLeadingRadius: 16,
                bottomTrailingRadius: 16,
                topTrailingRadius: topRadius,
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
