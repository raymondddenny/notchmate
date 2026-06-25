import SwiftUI

/// Spotify now-playing widget. Renders a compact glance when collapsed and full
/// artwork + transport controls when expanded. Falls back to a clean idle state when
/// nothing is playing.
struct SpotifyWidget: View {
    @ObservedObject var spotify: SpotifyController
    let expanded: Bool

    var body: some View {
        Group {
            if let np = spotify.nowPlaying {
                if expanded {
                    expandedView(np)
                } else {
                    collapsedView(np)
                }
            } else {
                idleView
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Collapsed

    private func collapsedView(_ np: NowPlaying) -> some View {
        HStack(spacing: 8) {
            artworkThumb(size: 24, corner: 5)
            Text("\(np.artist) - \(np.title)")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Image(systemName: np.isPlaying ? "waveform" : "pause.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.green)
        }
    }

    // MARK: - Expanded

    private func expandedView(_ np: NowPlaying) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                artworkThumb(size: 64, corner: 8)
                VStack(alignment: .leading, spacing: 4) {
                    Text(np.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(np.artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Text(np.album)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            controls(np)
        }
    }

    private func controls(_ np: NowPlaying) -> some View {
        HStack(spacing: 28) {
            controlButton("backward.fill") { spotify.previous() }
            controlButton(np.isPlaying ? "pause.fill" : "play.fill", size: 22) { spotify.playPause() }
            controlButton("forward.fill") { spotify.next() }
        }
    }

    private func controlButton(_ name: String, size: CGFloat = 16, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Idle

    private var idleView: some View {
        HStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            Text("Nothing playing")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artworkThumb(size: CGFloat, corner: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if let art = spotify.artwork {
            Image(nsImage: art)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(shape)
        } else {
            shape
                .fill(Color.white.opacity(0.12))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.white.opacity(0.5))
                )
        }
    }
}
