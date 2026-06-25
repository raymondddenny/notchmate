import SwiftUI

/// Stub - media source/controls settings. Fill in when media preferences land.
struct MediaPane: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Media settings coming soon.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Media")
    }
}
