import SwiftUI

struct AboutPane: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 52))
                .foregroundStyle(.primary)
            VStack(spacing: 6) {
                Text("notchmate")
                    .font(.title2.bold())
                Text("Version \(version) (\(build))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Your notch, elevated.")
                .foregroundStyle(.secondary)
            Link("github.com/raymondddenny/notchmate",
                 destination: URL(string: "https://github.com/raymondddenny/notchmate")!)
                .font(.caption)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("About")
    }
}
