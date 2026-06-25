import SwiftUI

/// The mascot's emotional state, derived from what the rest of the app is doing.
///
/// Priority when several signals are live: **dancing wins** (music is the most
/// expressive thing the mascot can react to), then thinking, then the two quiet
/// states. See `derive` for the exact rule.
enum MochiMood: Equatable {
    /// Spotify is actively playing - bob/dance to the music.
    case dancing
    /// One or more Claude Code sessions are running - heads-up, working face.
    case thinking
    /// Awake but nothing lively: Spotify is loaded yet paused/stopped. Calm breathing.
    case idle
    /// Truly nothing happening (no music loaded, no sessions). Eyes shut, Zzz.
    case sleeping

    /// Derive the current mood from the existing controllers' published state.
    ///
    /// Kept as a pure function of plain inputs (not the controllers themselves) so it
    /// is trivially unit-testable and has no UI/Combine dependencies.
    ///
    /// - Parameters:
    ///   - spotifyPlaying: a track is loaded *and* the player state is "playing".
    ///   - spotifyPresent: a track is loaded at all (playing or paused).
    ///   - claudeSessions: count of live Claude Code sessions.
    ///
    /// Extension point: today the app only knows the session *count*, not whether any
    /// session is actively working vs. waiting on the user. When a finer signal exists
    /// (e.g. `ClaudeSessionsController` exposing a "working" flag), branch here: a
    /// "working" session could map to a more animated `thinking`, while "waiting" maps
    /// to a calmer attentive pose. Nothing else in the view needs to change.
    static func derive(spotifyPlaying: Bool, spotifyPresent: Bool, claudeSessions: Int) -> MochiMood {
        if spotifyPlaying { return .dancing }
        if claudeSessions > 0 { return .thinking }
        if spotifyPresent { return .idle }
        return .sleeping
    }

#if DEBUG
    /// Truth-table self-check for `derive`. Runnable (called from the SwiftUI preview)
    /// so the priority rule can't silently regress. Asserts, no test framework needed.
    static func runDeriveSelfCheck() {
        assert(derive(spotifyPlaying: true,  spotifyPresent: true,  claudeSessions: 0) == .dancing)
        assert(derive(spotifyPlaying: true,  spotifyPresent: true,  claudeSessions: 3) == .dancing, "dancing wins over thinking")
        assert(derive(spotifyPlaying: false, spotifyPresent: true,  claudeSessions: 2) == .thinking, "sessions beat paused music")
        assert(derive(spotifyPlaying: false, spotifyPresent: true,  claudeSessions: 0) == .idle, "music loaded but paused -> idle")
        assert(derive(spotifyPlaying: false, spotifyPresent: false, claudeSessions: 0) == .sleeping)
        assert(derive(spotifyPlaying: false, spotifyPresent: false, claudeSessions: 1) == .thinking, "sessions alone -> thinking")
    }
#endif

    /// Accent color for the antenna light - the one robot bit that changes hue by mood.
    var accent: Color {
        switch self {
        case .dancing:  return Color(red: 0.30, green: 0.85, blue: 0.45) // Spotify-ish green
        case .thinking: return Color(red: 0.85, green: 0.52, blue: 0.30) // Claude warm orange
        case .idle:     return Color(red: 0.55, green: 0.78, blue: 0.95) // calm cyan
        case .sleeping: return Color(white: 0.55)                        // dim
        }
    }
}
