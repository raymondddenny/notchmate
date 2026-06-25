import SwiftUI

struct HUDsPane: View {
    @ObservedObject private var prefs = NotchPreferences.shared

    private var osdPlistExists: Bool {
        FileManager.default.fileExists(atPath: "/System/Library/LaunchAgents/com.apple.OSDUIHelper.plist")
    }

    var body: some View {
        Form {
            Section {
                Toggle("Replace system volume/brightness HUD", isOn: $prefs.hudSuppressSystem)
                    .disabled(!osdPlistExists)

                if !osdPlistExists {
                    Label {
                        Text("Suppression unavailable: OSDUIHelper plist not found at /System/Library/LaunchAgents/com.apple.OSDUIHelper.plist. This macOS version may have moved or protected the service.")
                            .font(.caption)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                } else {
                    Text("Stops the macOS system overlay via launchctl. The notch HUD appears in a strip below the notch on change and auto-dismisses. Reversed when toggled off or on app quit. macOS 26 note: if the native HUD reappears after an OS update, disable this toggle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if prefs.hudSuppressSystem {
                Section("Which events show the HUD") {
                    Toggle("Volume changes", isOn: $prefs.hudVolumeEnabled)
                    Toggle("Brightness changes", isOn: $prefs.hudBrightnessEnabled)
                    Text("Both default to on when the master toggle is enabled. Turn either off to suppress that event independently.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("HUDs")
    }
}
