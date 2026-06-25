import SwiftUI

/// Root SwiftUI content for the panel. Draws the black notch/pill background and
/// hosts feature widgets. Hover toggles expanded state and is reported upward so the
/// window controller can resize the panel.
struct NotchView: View {
    @ObservedObject var spotify: SpotifyController
    @ObservedObject var claude: ClaudeSessionsController
    let hasNotch: Bool
    let topInset: CGFloat
    let onHoverChange: (Bool) -> Void

    @State private var hovering = false

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
    // the container. Collapsed: a single strip (Claude count trails the Spotify
    // glance). Expanded: stacked blocks. Widgets render nothing when they have no
    // content, so neither knows or depends on the other.
    @ViewBuilder
    private var content: some View {
        if hovering {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    MochiView(spotify: spotify, claude: claude, expanded: true)
                    Spacer(minLength: 0)
                }
                SpotifyWidget(spotify: spotify, expanded: true)
                if claude.count > 0 {
                    Divider().overlay(Color.white.opacity(0.1))
                    ClaudeSessionsWidget(sessions: claude, expanded: true)
                }
            }
        } else {
            HStack(spacing: 10) {
                MochiView(spotify: spotify, claude: claude, expanded: false)
                SpotifyWidget(spotify: spotify, expanded: false)
                ClaudeSessionsWidget(sessions: claude, expanded: false)
            }
        }
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
