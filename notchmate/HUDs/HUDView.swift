import SwiftUI

/// Standalone overlay panel content rendered in the HUD panel below the notch.
/// Observes HUDController directly and animates in/out as events arrive.
struct HUDOverlayView: View {
    @ObservedObject var hud: HUDController

    var body: some View {
        ZStack {
            if let event = hud.currentEvent {
                HUDView(event: event)
                    .padding(.horizontal, Theme.sp3)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.panelBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Theme.panelBorder, lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: hud.currentEvent != nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Compact icon + level-bar + percentage row.
/// Used inside HUDOverlayView (the below-notch overlay) and anywhere else a
/// single-event HUD row is needed.
struct HUDView: View {
    let event: HUDEvent

    var body: some View {
        HStack(spacing: Theme.sp2) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(barColor)
                .frame(width: 20)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.trackBackground)
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
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
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
