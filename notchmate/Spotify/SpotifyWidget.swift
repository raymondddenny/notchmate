import SwiftUI

// MARK: - Equalizer animation

/// Four animated bars that bounce when playing, hold still when paused/idle.
/// Pure SwiftUI + TimelineView — zero assets, zero deps.
private struct EqualizerBars: View {
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(paused: !isPlaying)) { ctx in
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    bar(i: i, t: ctx.date.timeIntervalSinceReferenceDate)
                }
            }
            .frame(width: 16, height: 12)
        }
    }

    private func bar(i: Int, t: TimeInterval) -> some View {
        let phase = Double(i) * 0.85
        let h: CGFloat = isPlaying
            ? 0.25 + 0.75 * CGFloat(sin(t * 3.6 + phase) * 0.5 + 0.5)
            : 0.3
        return RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.green)
            .frame(width: 3, height: 12 * h)
            .frame(height: 12, alignment: .bottom)
    }
}

// MARK: - MediaWidget

/// Media now-playing widget backed by MediaController (Spotify or system source).
/// Collapsed: glanceable strip with optional artwork + playing indicator.
/// Expanded: full track info + transport controls; layout determined by NotchPreferences.
struct MediaWidget: View {
    @ObservedObject var media: MediaController
    let expanded: Bool
    @ObservedObject private var prefs = NotchPreferences.shared
    @ObservedObject private var spotifyWeb = SpotifyWebController.shared

    var body: some View {
        Group {
            if let np = media.nowPlaying {
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
            if prefs.musicLayout == .artwork {
                artworkThumb(size: 24, corner: 5)
            }
            Text(np.artist.isEmpty ? np.title : "\(np.artist) - \(np.title)")
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            EqualizerBars(isPlaying: np.isPlaying)
        }
    }

    // MARK: - Expanded

    private func expandedView(_ np: NowPlaying) -> some View {
        VStack(spacing: 12) {
            if prefs.musicLayout == .artwork {
                HStack(spacing: 12) {
                    artworkThumb(size: 64, corner: 8)
                    trackInfo(np)
                    Spacer(minLength: 0)
                }
            } else {
                // Compact: inline animation + text, no artwork block
                HStack(spacing: 8) {
                    EqualizerBars(isPlaying: np.isPlaying)
                    trackInfo(np)
                    Spacer(minLength: 0)
                }
            }
            controls(np)
        }
    }

    private func trackInfo(_ np: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(np.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
            if !np.artist.isEmpty {
                Text(np.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            if !np.album.isEmpty {
                Text(np.album)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
    }

    private func controls(_ np: NowPlaying) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 28) {
                controlButton("backward.fill") { media.previous() }
                controlButton(np.isPlaying ? "pause.fill" : "play.fill", size: 22) { media.playPause() }
                controlButton("forward.fill") { media.next() }
            }
            .disabled(premiumControlsDisabled)
            .opacity(premiumControlsDisabled ? 0.3 : 1)
            if premiumControlsDisabled {
                Text("Spotify Premium required for controls")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var premiumControlsDisabled: Bool {
        prefs.mediaSource == .spotifyWeb && spotifyWeb.premiumRequired
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

    // MARK: - Idle / permission denied / not connected

    @ViewBuilder
    private var idleView: some View {
        if media.permissionDenied && prefs.mediaSource == .spotify {
            Button(action: { media.openSpotifySettings() }) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange.opacity(0.85))
                    Text("Allow Spotify access")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .help("Opens Privacy & Security > Automation so you can grant notchmate access to Spotify")
        } else if prefs.mediaSource == .spotifyWeb, case .disconnected = spotifyWeb.authState {
            Button(action: { spotifyWeb.connect() }) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.system(size: 12))
                        .foregroundStyle(.green.opacity(0.85))
                    Text("Connect Spotify")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .help("Opens the Spotify authorization page in your browser")
        } else if prefs.mediaSource == .spotifyWeb, case .connecting = spotifyWeb.authState {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .colorScheme(.dark)
                Text("Connecting\u{2026}")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        } else {
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
    }

    // MARK: - Artwork

    @ViewBuilder
    private func artworkThumb(size: CGFloat, corner: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if let art = media.artwork {
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
