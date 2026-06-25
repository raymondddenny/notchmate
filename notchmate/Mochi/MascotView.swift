import SwiftUI

/// Routes to the currently-selected mascot character.
/// Drop-in replacement for `MochiView` wherever the mascot appears in the UI.
struct MascotView: View {
    @ObservedObject var media: MediaController
    @ObservedObject var claude: ClaudeSessionsController
    let expanded: Bool

    @ObservedObject private var prefs = NotchPreferences.shared

    var body: some View {
        switch prefs.mascotCharacter {
        case .mochi:
            MochiView(media: media, claude: claude, expanded: expanded)
        case .ducky2:
            DuckyView(character: .ducky2, expanded: expanded, media: media, claude: claude)
        case .ducky3:
            DuckyView(character: .ducky3, expanded: expanded, media: media, claude: claude)
        }
    }
}
