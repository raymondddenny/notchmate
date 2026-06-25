import SwiftUI

struct MediaPane: View {
    @ObservedObject private var prefs = NotchPreferences.shared

    // Detect if MediaRemote is likely restricted (macOS 15.4+ / macOS 26)
    private var mediaRemoteRestricted: Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return v.majorVersion > 15 || (v.majorVersion == 15 && v.minorVersion >= 4)
    }

    var body: some View {
        Form {
            Section("Source") {
                Picker("Music source", selection: $prefs.mediaSource) {
                    Text("Spotify only").tag(MediaSource.spotify)
                    Text("Now Playing (any app)").tag(MediaSource.nowPlaying)
                }
                .pickerStyle(.radioGroup)

                if prefs.mediaSource == .nowPlaying {
                    if mediaRemoteRestricted {
                        Label {
                            Text("Now Playing uses MediaRemote, a private macOS framework. On macOS 15.4 and later (including macOS 26), Apple restricts it to first-party entitlements — the widget will show \"Nothing playing\" even when media is active. Switch to Spotify for a reliable source on this OS version.")
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

            Section("Layout") {
                Picker("Layout", selection: $prefs.musicLayout) {
                    Text("With artwork thumbnail").tag(MusicLayout.artwork)
                    Text("Compact (text only)").tag(MusicLayout.compact)
                }
                .pickerStyle(.radioGroup)
                // ponytail: lyrics layout is a separate later task — add a third case here
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Media")
    }
}
