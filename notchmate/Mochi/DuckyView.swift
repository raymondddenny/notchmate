import SwiftUI
import AppKit

// MARK: - Animation config

/// One row of animation in the 6×4 duck spritesheet (32×32 px frames).
/// Frame layout config table - adjust row/frameCount here to correct for actual sheet layout.
enum DuckyAnimation {
    case idleNormal  // row 0, 2 frames  - sleeping mood
    case walkNormal  // row 1, 6 frames  - thinking mood
    case idleBounce  // row 2, 4 frames  - idle mood
    case walkBounce  // row 3, 6 frames  - dancing mood

    var row: Int {
        switch self {
        case .idleNormal: return 0
        case .walkNormal: return 1
        case .idleBounce: return 2
        case .walkBounce: return 3
        }
    }

    var frameCount: Int {
        switch self {
        case .idleNormal: return 2
        case .walkNormal: return 6
        case .idleBounce: return 4
        case .walkBounce: return 6
        }
    }

    /// Map mascot mood to the matching duck animation.
    static func forMood(_ mood: MochiMood) -> DuckyAnimation {
        switch mood {
        case .dancing:  return .walkBounce   // most lively
        case .thinking: return .walkNormal   // attentive walk
        case .idle:     return .idleBounce   // gentle bounce
        case .sleeping: return .idleNormal   // still
        }
    }
}

// MARK: - Live mascot view

/// Pixel-art duck mascot animated from a 6×4 spritesheet (32×32 px frames).
/// Nearest-neighbor scaling keeps pixels crisp at all display sizes.
/// Reuses `MochiMood.derive` for the same state logic as Mochi.
struct DuckyView: View {
    let character: MascotCharacter
    let expanded: Bool
    @ObservedObject var media: MediaController
    @ObservedObject var claude: ClaudeSessionsController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frameIndex = 0
    @State private var mood: MochiMood = .sleeping

    private var liveMood: MochiMood {
        MochiMood.derive(
            spotifyPlaying: media.nowPlaying?.isPlaying == true,
            spotifyPresent: media.nowPlaying != nil,
            claudeSessions: claude.count
        )
    }

    /// Integer multiples of 32 for pixel-perfect rendering.
    var displaySize: CGFloat { expanded ? 64 : 32 }

    var body: some View {
        let anim = DuckyAnimation.forMood(mood)
        DuckySpriteView(
            character: character,
            col: reduceMotion ? 0 : (frameIndex % anim.frameCount),
            row: anim.row,
            displaySize: displaySize
        )
        .onAppear { mood = liveMood }
        .onChange(of: liveMood) { _, newValue in
            mood = newValue
            frameIndex = 0
        }
        .onReceive(
            Timer.publish(every: 1.0 / 10.0, on: .main, in: .common).autoconnect()
        ) { _ in
            guard !reduceMotion else { return }
            frameIndex = (frameIndex + 1) % DuckyAnimation.forMood(mood).frameCount
        }
    }
}

// MARK: - Sprite renderer

/// Renders one 32×32 frame from the spritesheet, pixel-scaled to `displaySize`.
///
/// Technique: render the full sheet at scale, offset to the target frame's position,
/// then clip to displaySize×displaySize. Nearest-neighbor interpolation keeps pixels sharp.
struct DuckySpriteView: View {
    let character: MascotCharacter
    let col: Int
    let row: Int
    let displaySize: CGFloat

    // ponytail: static cache - one NSImage per character, loaded once from bundle
    private static var sheetCache: [MascotCharacter: NSImage] = [:]

    private var sheet: NSImage? {
        if let cached = Self.sheetCache[character] { return cached }
        let name = character == .ducky2 ? "ducky_2_spritesheet" : "ducky_3_spritesheet"
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        Self.sheetCache[character] = img
        return img
    }

    var body: some View {
        if let sheet {
            // Sheet is 192×128 (6 cols × 4 rows of 32×32 frames).
            // Scale the full sheet, offset to bring target frame to top-left, clip.
            let scale = displaySize / 32
            Image(nsImage: sheet)
                .interpolation(.none)
                .resizable()
                .frame(width: 192 * scale, height: 128 * scale)
                .offset(x: -CGFloat(col) * displaySize, y: -CGFloat(row) * displaySize)
                .frame(width: displaySize, height: displaySize, alignment: .topLeading)
                .clipped()
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.yellow.opacity(0.4))
                .frame(width: displaySize, height: displaySize)
        }
    }
}

// MARK: - Preview helper (no live controllers needed)

/// Standalone animated duck preview for use in Settings without live media/claude controllers.
struct DuckyPreviewView: View {
    let character: MascotCharacter
    var mood: MochiMood = .dancing
    var displaySize: CGFloat = 64

    @State private var frameIndex = 0

    var body: some View {
        DuckySpriteView(
            character: character,
            col: frameIndex,
            row: DuckyAnimation.forMood(mood).row,
            displaySize: displaySize
        )
        .onReceive(
            Timer.publish(every: 1.0 / 10.0, on: .main, in: .common).autoconnect()
        ) { _ in
            frameIndex = (frameIndex + 1) % DuckyAnimation.forMood(mood).frameCount
        }
    }
}

// MARK: - Debug preview

#if DEBUG
#Preview("Duck animations") {
    HStack(spacing: 24) {
        ForEach([MochiMood.sleeping, .idle, .thinking, .dancing], id: \.self) { mood in
            VStack(spacing: 8) {
                Text("\(mood)").font(.caption2).foregroundStyle(.white)
                DuckyPreviewView(character: .ducky2, mood: mood, displaySize: 64)
                DuckyPreviewView(character: .ducky3, mood: mood, displaySize: 64)
            }
        }
    }
    .padding(32)
    .background(Color.black)
}
#endif
