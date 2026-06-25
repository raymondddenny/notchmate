import Combine
import SwiftUI

/// Shared selection state for the settings window. Lets code outside the view tree
/// (e.g. a click on the Claude module in the panel) deep-link to a specific pane.
final class SettingsNavigator: ObservableObject {
    static let shared = SettingsNavigator()
    @Published var selection: SettingsPane = .general
    private init() {}
}

/// Root of the settings window. NavigationSplitView sidebar lists panes; detail
/// renders the selected one. Add a new SettingsPane case + view to extend.
struct SettingsView: View {
    @ObservedObject private var nav = SettingsNavigator.shared

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $nav.selection) { pane in
                Label(pane.label, systemImage: pane.icon)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 168, max: 190)
        } detail: {
            switch nav.selection {
            case .general: GeneralPane()
            case .layout:  LayoutPane()
            case .media:   MediaPane()
            case .huds:    HUDsPane()
            case .claude:  ClaudeSessionsPane()
            case .mascot:  MascotPane()
            case .about:   AboutPane()
            }
        }
        .frame(minWidth: 580, minHeight: 440)
    }
}

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general, layout, media, huds, claude, mascot, about
    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .layout:  return "Layout"
        case .media:   return "Media"
        case .huds:    return "HUDs"
        case .claude:  return "Claude Sessions"
        case .mascot:  return "Mascot"
        case .about:   return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .layout:  return "square.grid.2x2"
        case .media:   return "music.note"
        case .huds:    return "rectangle.stack"
        case .claude:  return "sparkles"
        case .mascot:  return "pawprint"
        case .about:   return "info.circle"
        }
    }
}
