import SwiftUI

struct MediaPane: View {
    @ObservedObject private var prefs = NotchPreferences.shared
    @ObservedObject private var spotifyWeb = SpotifyWebController.shared

    // Detect if MediaRemote is likely restricted (macOS 15.4+ / macOS 26)
    private var mediaRemoteRestricted: Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion > 15 || (v.majorVersion == 15 && v.minorVersion >= 4)
    }

    var body: some View {
        Form {
            Section("Source") {
                Picker("Music source", selection: $prefs.mediaSource) {
                    Text("Spotify (Web API) - Recommended").tag(MediaSource.spotifyWeb)
                    Text("Spotify (AppleScript)").tag(MediaSource.spotify)
                    Text("Now Playing (any app)").tag(MediaSource.nowPlaying)
                }
                .pickerStyle(.radioGroup)

                if prefs.mediaSource == .spotify {
                    Text("Reads from the Spotify desktop app via AppleScript. Requires Automation permission. May be blocked on macOS 26 without the correct code signature.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if prefs.mediaSource == .nowPlaying {
                    if mediaRemoteRestricted {
                        Label {
                            Text("Now Playing uses MediaRemote, a private macOS framework. On macOS 15.4 and later (including macOS 26), Apple restricts it to first-party entitlements — the widget will show \"Nothing playing\" even when media is active. Switch to Spotify (Web API) for a reliable source on this OS version.")
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
                    Text("Uses Spotify Web API with Authorization Code + PKCE OAuth. No Automation permission required. Tokens stored in macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if case .connected = spotifyWeb.authState, spotifyWeb.premiumRequired {
                        Label("Controls require Spotify Premium. Reading track info still works.", systemImage: "info.circle")
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
                Text("Fetches time-synced lyrics from LRCLIB (lrclib.net) - free, no account needed. Highlights the current line while the song plays. Spotify sources sync lyrics; other sources show lyrics without advancing.")
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
            }
        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for browser login\u{2026}")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        case .connected:
            HStack {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Disconnect") { spotifyWeb.disconnect() }
            }
        case .error(let msg):
            HStack {
                Label(msg, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Spacer()
                Button("Reconnect") { spotifyWeb.connect() }
            }
        }
    }
}
