import SwiftUI

// MARK: - Marquee text

/// Single-line text that scrolls horizontally (marquee) when content exceeds container width.
/// Uses a GeometryReader to measure both container and natural text width via a
/// preference key, then animates an x-offset with repeatForever(autoreverses: true)
/// so the text bounces between start and overflow position.
/// Scrolling is suppressed when reduceMotion is true.
struct LyricMarqueeText: View {
    let text: String
    let reduceMotion: Bool
    var font: Font = .system(size: 13, weight: .semibold)
    var color: Color = Theme.textPrimary

    @State private var textWidth: CGFloat = 0
    @State private var animating = false

    var body: some View {
        GeometryReader { geo in
            let containerW = geo.size.width
            let overflow = max(0, textWidth - containerW)
            let needsMarquee = overflow > 1 && !reduceMotion

            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
                .overlay(WidthProbe())
                .offset(x: needsMarquee && animating ? -overflow : 0)
                .animation(
                    needsMarquee
                        ? .linear(duration: Double(overflow) / 50)
                              .delay(1.5)
                              .repeatForever(autoreverses: true)
                        : .none,
                    value: animating
                )
        }
        .clipped()
        .onPreferenceChange(TextNaturalWidthKey.self) { w in
            guard w > 0 else { return }
            textWidth = w
            animating = false
            DispatchQueue.main.async { animating = true }
        }
    }

    // Transparent overlay that publishes the Text's natural (fixedSize) width.
    private struct WidthProbe: View {
        var body: some View {
            GeometryReader { inner in
                Color.clear.preference(key: TextNaturalWidthKey.self, value: inner.size.width)
            }
        }
    }

    private struct TextNaturalWidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
    }
}

// MARK: - Single-line lyric view

/// Shows the current synced lyric as a single line.
/// Transitions with a subtle opacity + vertical drift when the line changes;
/// Reduce Motion degrades to plain opacity.
/// Long lines scroll horizontally via LyricMarqueeText.
/// Used inside MediaWidget (between track info and controls) and as the LyricsWidget tile.
struct LyricLineView: View {
    @ObservedObject var lyrics: LyricsController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            switch lyrics.state {
            case .synced(let lines, let index) where index < lines.count:
                let text = lines[index].text
                if text.isEmpty {
                    // Instrumental gap: subtle musical note placeholder
                    Image(systemName: "music.note")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .id("gap-\(index)")
                        .transition(.opacity)
                } else {
                    LyricMarqueeText(text: text, reduceMotion: reduceMotion)
                        .id(index)
                        .transition(
                            reduceMotion
                                ? AnyTransition.opacity
                                : AnyTransition.asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 5)),
                                    removal: .opacity.combined(with: .offset(y: -5))
                                )
                        )
                }
            default:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: lyricIndex)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 18)
        .clipped()
    }

    private var lyricIndex: Int {
        if case .synced(_, let i) = lyrics.state { return i }
        return -1
    }
}

// MARK: - Below-notch strip overlay

/// Content for the floating lyrics strip panel below the notch.
/// Shown when a synced lyric line is active, hidden when HUD is active or panel is expanded.
/// Mirrors HUDOverlayView's visual style (dark pill + border + shadow).
struct LyricsStripOverlayView: View {
    @ObservedObject var lyrics: LyricsController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var lineInfo: (text: String, index: Int)? {
        guard case .synced(let lines, let index) = lyrics.state,
              index < lines.count else { return nil }
        let t = lines[index].text
        return t.isEmpty ? nil : (t, index)
    }

    var body: some View {
        ZStack {
            if let info = lineInfo {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    ZStack(alignment: .leading) {
                        LyricMarqueeText(
                            text: info.text,
                            reduceMotion: reduceMotion,
                            font: .system(size: 12, weight: .medium)
                        )
                        .id(info.index)
                        .transition(
                            reduceMotion
                                ? AnyTransition.opacity
                                : AnyTransition.asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 5)),
                                    removal: .opacity.combined(with: .offset(y: -5))
                                )
                        )
                    }
                    .animation(.easeInOut(duration: 0.3), value: info.index)
                    .frame(maxWidth: .infinity)
                    .frame(height: 18)
                    .clipped()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.panelBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.panelBorder, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: lineInfo?.index ?? -1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - LyricsWidget tile

/// LyricsWidget module tile (expanded panel only).
/// Synced: single crossfading line via LyricLineView.
/// Plain: scrollable full-text block (unchanged).
/// Loading / no-match: status row.
struct LyricsWidget: View {
    @ObservedObject var lyrics: LyricsController
    let expanded: Bool

    var body: some View {
        if expanded {
            expandedContent
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        switch lyrics.state {
        case .idle:
            EmptyView()
        case .loading:
            statusRow("Loading lyrics\u{2026}", icon: "music.note.list")
        case .noMatch:
            statusRow("No lyrics found", icon: "questionmark.bubble")
        case .synced:
            LyricLineView(lyrics: lyrics)
        case .plain(let text):
            plainView(text: text)
        }
    }

    private func statusRow(_ message: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
            Spacer(minLength: 0)
        }
    }

    private func plainView(text: String) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineSpacing(3)
        }
        .frame(maxHeight: 108)
    }
}
