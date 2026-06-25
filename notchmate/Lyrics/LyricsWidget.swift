import SwiftUI

/// Shows synced or plain lyrics for the currently playing track.
/// Expanded only — collapsed strip is unaffected.
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
        case .synced(let lines, let currentIndex):
            syncedView(lines: lines, currentIndex: currentIndex)
        case .plain(let text):
            plainView(text: text)
        }
    }

    // MARK: - Status

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

    // MARK: - Synced lyrics

    private func syncedView(lines: [LyricLine], currentIndex: Int) -> some View {
        // Fixed 5-line window: 2 before current, current, 2 after. No scroll needed.
        let window = 2
        let start = max(0, currentIndex - window)
        let end = min(lines.count - 1, currentIndex + window)
        let visible = Array(lines[start...end])
        let relCurrent = currentIndex - start

        return VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(visible.enumerated()), id: \.offset) { i, line in
                lyricLineView(text: line.text, distance: abs(i - relCurrent))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.3), value: currentIndex)
    }

    private func lyricLineView(text: String, distance: Int) -> some View {
        let opacity: Double  = distance == 0 ? 1.0  : distance == 1 ? 0.55 : 0.25
        let weight: Font.Weight = distance == 0 ? .semibold : .regular
        let size: CGFloat   = distance == 0 ? 13   : 12
        let display = text.isEmpty ? "\u{266A}" : text // ♪ placeholder for instrumental
        return Text(display)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(.white.opacity(opacity))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.25), value: opacity)
    }

    // MARK: - Plain lyrics

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
