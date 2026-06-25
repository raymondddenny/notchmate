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
            case .layout:  LayoutPane()
            case .media:   MediaPane()
            case .huds:    HUDsPane()
            case .about:   AboutPane()
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }
}

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general, layout, media, huds, about
    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .layout:  return "Layout"
        case .media:   return "Media"
        case .huds:    return "HUDs"
        case .about:   return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .layout:  return "square.grid.2x2"
        case .media:   return "music.note"
        case .huds:    return "rectangle.stack"
        case .about:   return "info.circle"
        }
    }
}
