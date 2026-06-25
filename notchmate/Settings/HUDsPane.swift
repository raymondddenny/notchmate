import SwiftUI

struct HUDsPane: View {
    @ObservedObject private var prefs = NotchPreferences.shared

    private var osdPlistExists: Bool {
        FileManager.default.fileExists(atPath: "/System/Library/LaunchAgents/com.apple.OSDUIHelper.plist")
    }

    var body: some View {
        Form {
            Section("Volume HUD") {
                Toggle("Show notch volume HUD", isOn: $prefs.hudVolumeEnabled)
                Text("Replaces the collapsed strip briefly when volume changes. Works via CoreAudio property listener - no permission required.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Brightness HUD") {
                Toggle("Show notch brightness HUD", isOn: $prefs.hudBrightnessEnabled)
                Text("Reads display brightness via DisplayServices (private macOS framework, loaded at runtime via dlopen). Works on Intel and Apple Silicon. Polled at 0.1 s; changes smaller than 1% are ignored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System HUD") {
                Toggle("Replace system volume/brightness HUD", isOn: $prefs.hudSuppressSystem)
                    .disabled(!osdPlistExists)
                if osdPlistExists {
                    Text("Stops OSDUIHelper (the macOS system overlay) via launchctl so only the notch HUD appears. Reversed when toggled off or on app quit. macOS 26 note: if the native HUD reappears after an OS update, disable this toggle - the launchctl path may have changed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label {
                        Text("Suppression unavailable: OSDUIHelper plist not found at /System/Library/LaunchAgents/com.apple.OSDUIHelper.plist. This macOS version may have moved or protected the service.")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("HUDs")
    }
}
