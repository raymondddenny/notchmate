import SwiftUI

/// Settings pane for choosing the notch mascot character.
/// Each option shows a live animated preview at dancing mood.
struct MascotPane: View {
    @ObservedObject private var prefs = NotchPreferences.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    ForEach(MascotCharacter.allCases, id: \.self) { character in
                        characterCard(character)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Character")
            } footer: {
                Text("The mascot animates in the notch - dancing to music, thinking during Claude sessions, and sleeping when idle.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Mascot")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func characterCard(_ character: MascotCharacter) -> some View {
        let selected = prefs.mascotCharacter == character
        VStack(spacing: 8) {
            characterPreview(character)
                .frame(width: 64, height: 64)
            Text(character.displayName)
                .font(.caption)
                .foregroundStyle(selected ? Color.primary : Color.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { prefs.mascotCharacter = character }
    }

    @ViewBuilder
    private func characterPreview(_ character: MascotCharacter) -> some View {
        switch character {
        case .mochi:
            MochiPreviewView(mood: .dancing, expanded: true)
        case .ducky2:
            DuckyPreviewView(character: .ducky2, mood: .dancing, displaySize: 64)
        case .ducky3:
            DuckyPreviewView(character: .ducky3, mood: .dancing, displaySize: 64)
        }
    }
}

#if DEBUG
#Preview("Mascot picker") {
    MascotPane()
        .frame(width: 400, height: 280)
}
#endif
