import SwiftUI

struct GeneralPane: View {
    @ObservedObject private var prefs = NotchPreferences.shared

    var body: some View {
        Form {
            Section {
                Toggle("Show menu-bar icon", isOn: $prefs.showMenuBarIcon)
                Toggle("Launch at login", isOn: Binding(
                    get: { prefs.launchAtLogin },
                    set: { prefs.launchAtLogin = $0 }
                ))
                if prefs.launchAtLoginError != nil {
                    Text("Couldn't enable launch at login. Move notchmate to your Applications folder and launch it from there, then try again.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text("If the menu-bar icon is hidden, hover over the notch to access Settings.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
