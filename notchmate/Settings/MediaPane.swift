import SwiftUI

struct MediaPane: View {
    @ObservedObject private var prefs = NotchPreferences.shared
    @ObservedObject private var spotifyWeb = SpotifyWebController.shared

    var body: some View {
        Form {
            Section {
                sourceRow(
                    icon: "waveform",
                    name: "Spotify",
                    detail: "Spotify Web API - OAuth, no Automation permission needed",
                    active: true,
                    comingSoon: false
                )
                sourceRow(
                    icon: "music.note",
                    name: "Apple Music",
                    detail: nil,
                    active: false,
                    comingSoon: true
                )
                sourceRow(
                    icon: "play.rectangle",
                    name: "YouTube Music",
                    detail: nil,
                    active: false,
                    comingSoon: true
                )
            } header: {
                Text("Source")
            }

            Section("Spotify Connection") {
                connectionRow
                switch spotifyWeb.authState {
                case .disconnected:
                    Text("Opens your browser to sign in with Spotify. Tokens are stored securely in the macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .connected:
                    Text("Authorization Code + PKCE OAuth. Tokens stored in macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
                if case .connected = spotifyWeb.authState, spotifyWeb.premiumRequired {
                    Label("Playback controls require Spotify Premium. Track info still works.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Layout") {
                Picker("Layout", selection: $prefs.musicLayout) {
                    Text("With artwork thumbnail").tag(MusicLayout.artwork)
                    Text("Compact (text only)").tag(MusicLayout.compact)
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Media")
    }

    // MARK: - Source row

    private func sourceRow(
        icon: String,
        name: String,
        detail: String?,
        active: Bool,
        comingSoon: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(active ? Color.primary : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .foregroundStyle(active ? Color.primary : Color.secondary)
                    if comingSoon {
                        Text("Coming soon")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if active {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .disabled(comingSoon)
    }

    // MARK: - Connection row

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
