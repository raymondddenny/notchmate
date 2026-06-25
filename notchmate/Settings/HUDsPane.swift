import SwiftUI

/// Stub - HUD overlay settings. Fill in when HUD preferences land.
struct HUDsPane: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("HUD settings coming soon.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("HUDs")
    }
}
