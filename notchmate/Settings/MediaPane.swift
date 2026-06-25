import SwiftUI

struct MediaPane: View {
    @ObservedObject private var prefs = NotchPreferences.shared
    @ObservedObject private var spotifyWeb = SpotifyWebController.shared

    private var mediaRemoteRestricted: Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion > 15 || (v.majorVersion == 15 && v.minorVersion >= 4)
    }

    var body: some View {
        Form {
            Section("Source") {
                Picker("Music source", selection: $prefs.mediaSource) {
                    Text("Spotify (Web API)").tag(MediaSource.spotifyWeb)
                    Text("Spotify (AppleScript - legacy)").tag(MediaSource.spotify)
                    Text("Now Playing (any app)").tag(MediaSource.nowPlaying)
                }
                .pickerStyle(.radioGroup)

                switch prefs.mediaSource {
                case .spotifyWeb:
                    EmptyView()
                case .spotify:
                    Label {
                        Text("Uses the Spotify desktop app via AppleScript. Requires Automation permission under System Settings > Privacy & Security. On macOS 26 this source may be silently blocked unless the app is signed with the hardened runtime entitlement - use Spotify (Web API) for reliable access on macOS 26.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                case .nowPlaying:
                    if mediaRemoteRestricted {
                        Label {
                            Text("Now Playing uses MediaRemote, a private macOS framework. On macOS 15.4 and later (including macOS 26), Apple restricts it to first-party entitlements - the widget will show \"Nothing playing\" even when media is active. Use Spotify (Web API) for a reliable source on this OS version.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    } else {
                        Text("Shows track info from any player (Apple Music, browsers, etc.) via MediaRemote.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if prefs.mediaSource == .spotifyWeb {
                Section("Spotify Connection") {
                    connectionRow
                    if case .disconnected = spotifyWeb.authState {
                        Text("Opens your browser to sign in with Spotify. No Automation permission required. Tokens are stored securely in the macOS Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if case .connected = spotifyWeb.authState {
                        Text("Authorization Code + PKCE OAuth. Tokens stored in macOS Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if case .connected = spotifyWeb.authState, spotifyWeb.premiumRequired {
                        Label("Playback controls require Spotify Premium. Track info still works.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section("Layout") {
                Picker("Layout", selection: $prefs.musicLayout) {
                    Text("With artwork thumbnail").tag(MusicLayout.artwork)
                    Text("Compact (text only)").tag(MusicLayout.compact)
                }
                .pickerStyle(.radioGroup)
            }

            Section("Lyrics") {
                Toggle("Show synced lyrics", isOn: $prefs.showLyrics)
                Text("Fetches time-synced lyrics from LRCLIB (free, no account). Highlights the current line while the song plays. Spotify sources sync lyrics; other sources show lyrics without advancing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Media")
    }

    @ViewBuilder
    private var connectionRow: some View {
        switch spotifyWeb.authState {
        case .disconnected:
            HStack {
                Label("Not connected", systemImage: "link.badge.plus")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Connect Spotify") { spotifyWeb.connect() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for browser\u{2026}")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { spotifyWeb.disconnect() }
                    .controlSize(.small)
            }
        case .connected:
            HStack {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Disconnect") { spotifyWeb.disconnect() }
                    .controlSize(.small)
            }
        case .error(let msg):
            HStack {
                Label(msg, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
                Spacer()
                Button("Retry") { spotifyWeb.connect() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }
}
