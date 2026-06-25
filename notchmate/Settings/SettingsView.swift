import SwiftUI

/// Root of the settings window. NavigationSplitView sidebar lists panes; detail
/// renders the selected one. Add a new SettingsPane case + view to extend.
struct SettingsView: View {
    @State private var selection: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.label, systemImage: pane.icon)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 140, ideal: 160, max: 180)
        } detail: {
            switch selection {
            case .general: GeneralPane()
            case .media:   MediaPane()
            case .huds:    HUDsPane()
            case .about:   AboutPane()
            }
        }
        .frame(minWidth: 560, minHeight: 380)
    }
}

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general, media, huds, about
    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: "General"
        case .media:   "Media"
        case .huds:    "HUDs"
        case .about:   "About"
        }
    }

    var icon: String {
        switch self {
        case .general: "gear"
        case .media:   "music.note"
        case .huds:    "rectangle.stack"
        case .about:   "info.circle"
        }
    }
}
