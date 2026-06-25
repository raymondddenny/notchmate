import SwiftUI

/// Compact icon + level-bar + percentage row shown in the collapsed notch strip
/// while a volume or brightness HUD event is active (~1.5 s).
struct HUDView: View {
    let event: HUDEvent

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(barColor)
                .frame(width: 20)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(barColor)
                        .frame(width: geo.size.width * CGFloat(clampedLevel))
                }
                .animation(.easeOut(duration: 0.1), value: clampedLevel)
            }
            .frame(height: 5)
            Text(pctString)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 36, alignment: .trailing)
        }
    }

    private var clampedLevel: Float {
        switch event {
        case .volume(let v): return max(0, min(1, v))
        case .brightness(let b): return max(0, min(1, b))
        }
    }

    private var iconName: String {
        switch event {
        case .volume(let v):
            if v <= 0 { return "speaker.slash.fill" }
            if v < 0.34 { return "speaker.wave.1.fill" }
            if v < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return "sun.max.fill"
        }
    }

    private var barColor: Color {
        switch event {
        case .volume: return Color(red: 0.55, green: 0.80, blue: 0.95)
        case .brightness: return Color(red: 1.00, green: 0.85, blue: 0.40)
        }
    }

    private var pctString: String {
        "\(Int((clampedLevel * 100).rounded()))%"
    }
}
