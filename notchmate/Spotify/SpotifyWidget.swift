import SwiftUI

// MARK: - Equalizer animation

/// Four animated bars that bounce when playing, hold still when paused/idle.
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
/// Collapsed: transport controls only (play/pause/prev/next) - no artwork or text.
/// Expanded: full track info + optional single lyric line + transport controls.
struct MediaWidget: View {
    @ObservedObject var media: MediaController
    let expanded: Bool
    /// Optional lyrics controller. When provided and a synced line is available, a
    /// single crossfading lyric line appears between track info and controls.
    var lyrics: LyricsController? = nil
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
        HStack(spacing: Theme.sp3) {
            // Now-playing animation: equalizer bars bounce while playing, hold still when
            // paused. Sits ahead of the transport controls as a glanceable "live" cue.
            EqualizerBars(isPlaying: np.isPlaying)
            HStack(spacing: 16) {
                controlButton("backward.fill") { media.previous() }
                controlButton(np.isPlaying ? "pause.fill" : "play.fill", size: 18) { media.playPause() }
                controlButton("forward.fill") { media.next() }
            }
            .disabled(premiumControlsDisabled)
            .opacity(premiumControlsDisabled ? 0.35 : 1)
        }
    }

    // MARK: - Expanded

    private func expandedView(_ np: NowPlaying) -> some View {
        // Unified media tile: artwork + track info on the left, the live synced lyric
        // line folded into the empty space on the right (no separate Lyrics module),
        // transport pinned to the bottom.
        VStack(alignment: .leading, spacing: Theme.sp2) {
            HStack(spacing: prefs.musicLayout == .artwork ? Theme.sp3 : Theme.sp2) {
                if prefs.musicLayout == .artwork {
                    artworkThumb(size: 48, corner: 8)
                } else {
                    EqualizerBars(isPlaying: np.isPlaying)
                }
                trackInfo(np)
                    .layoutPriority(1)
                // Lyrics fill the empty space to the right of the track info; when no
                // synced line is available a plain spacer keeps the layout stable.
                if let lc = lyrics, lc.currentLine != nil {
                    LyricLineView(lyrics: lc)
                        .padding(.leading, Theme.sp3)
                } else {
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
            controls(np)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func trackInfo(_ np: NowPlaying) -> some View {
        VStack(alignment: .leading, spacing: Theme.sp1) {
            Text(np.title)
                .font(Theme.primaryFont)
                .lineLimit(1)
            if !np.artist.isEmpty {
                Text(np.artist)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            if !np.album.isEmpty {
                Text(np.album)
                    .font(Theme.secondaryFont)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private func controls(_ np: NowPlaying) -> some View {
        VStack(spacing: Theme.sp1) {
            HStack(spacing: 20) {
                controlButton("backward.fill") { media.previous() }
                controlButton(np.isPlaying ? "pause.fill" : "play.fill", size: 20) { media.playPause() }
                controlButton("forward.fill") { media.next() }
            }
            .disabled(premiumControlsDisabled)
            .opacity(premiumControlsDisabled ? 0.3 : 1)
            if premiumControlsDisabled {
                Text("Spotify Premium required for controls")
                    .font(Theme.captionFont)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var premiumControlsDisabled: Bool {
        prefs.mediaSource == .spotifyWeb && spotifyWeb.premiumRequired
    }

    private func controlButton(_ name: String, size: CGFloat = 15, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .contentShape(Rectangle())
                .frame(width: 32, height: 28)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Idle / permission denied / not connected

    @ViewBuilder
    private var idleView: some View {
        if media.permissionDenied && prefs.mediaSource == .spotify {
            // AppleScript TCC denied - surface a clear action.
            Button(action: { media.openSpotifySettings() }) {
                HStack(spacing: Theme.sp2) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spotify access denied")
                            .font(Theme.chipFont)
                        Text("Tap to open Privacy & Security")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            .help("Opens Privacy & Security > Automation so you can grant notchmate access to Spotify")
        } else if prefs.mediaSource == .spotifyWeb, case .disconnected = spotifyWeb.authState {
            // Web API not yet connected - prominent call-to-action.
            if expanded {
                VStack(spacing: Theme.sp2) {
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(Theme.textTertiary)
                    Text("Connect Spotify to see what's playing")
                        .font(Theme.secondaryFont)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Button(action: { spotifyWeb.connect() }) {
                        Text("Connect Spotify")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, Theme.sp3)
                            .padding(.vertical, Theme.sp1 + 2)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(.plain)
                    .help("Opens the Spotify authorization page in your browser")
                }
                .frame(maxWidth: .infinity)
            } else {
                Button(action: { spotifyWeb.connect() }) {
                    HStack(spacing: Theme.sp2) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                            .foregroundStyle(.green.opacity(0.85))
                        Text("Connect Spotify")
                            .font(Theme.chipFont)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .help("Opens the Spotify authorization page in your browser")
            }
        } else if prefs.mediaSource == .spotifyWeb, case .connecting = spotifyWeb.authState {
            HStack(spacing: Theme.sp2) {
                ProgressView()
                    .controlSize(.small)
                    .colorScheme(.dark)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connecting\u{2026}")
                        .font(Theme.chipFont)
                    if expanded {
                        Text("Waiting for browser sign-in")
                            .font(Theme.captionFont)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.textSecondary)
        } else if prefs.mediaSource == .spotifyWeb, case .error(let msg) = spotifyWeb.authState {
            Button(action: { spotifyWeb.connect() }) {
                HStack(spacing: Theme.sp2) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.85))
                    Text(expanded ? msg : "Connection error - tap to retry")
                        .font(Theme.chipFont)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: Theme.sp2) {
                Image(systemName: "music.note")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                Text("Nothing playing")
                    .font(Theme.chipFont)
                    .foregroundStyle(Theme.textTertiary)
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
                .fill(Theme.trackBackground)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(Theme.textTertiary)
                )
        }
    }
}
