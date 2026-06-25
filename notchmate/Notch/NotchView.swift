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

    // Collapsed: a single glanceable strip. Expanded: stacked widget blocks.
    // Widgets render nothing when they have no content, so absent state is free.
    @ViewBuilder
    private var content: some View {
        if hovering {
            VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
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
            // Collapsed strip: HUD event takes priority for ~1.5s; otherwise widget chips.
            Group {
                if let event = hud.currentEvent {
                    HUDView(event: event)
                        .transition(.opacity)
                } else {
                    HStack(spacing: Theme.sp2) {
                        MochiView(media: media, claude: claude, expanded: false)
                        MediaWidget(media: media, expanded: false)
                        FocusTimerWidget(timer: focus, expanded: false)
                        ClaudeSessionsWidget(sessions: claude, expanded: false)
                        GitWidget(git: git, expanded: false)
                        SystemStatsWidget(stats: stats, expanded: false)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: hud.currentEvent != nil)
        }
    }

    private var divider: some View {
        Divider().overlay(Theme.dividerColor)
    }

    private var background: some View {
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
