import SwiftUI

/// System-load widget. Collapsed: a compact CPU% badge that only appears under heavy
/// load (stays quiet when the machine is idle). Expanded: CPU + memory mini-bars with
/// percentages, always shown.
struct SystemStatsWidget: View {
    @ObservedObject var stats: SystemStatsController
    let expanded: Bool

    private static let cpuColor = Color(red: 0.95, green: 0.55, blue: 0.35) // warm
    private static let memColor = Color(red: 0.55, green: 0.70, blue: 0.95) // cool

    var body: some View {
        Group {
            if expanded {
                expandedView
            } else if stats.cpuHigh {
                collapsedView
            } else {
                EmptyView()
            }
        }
        .foregroundStyle(.white)
    }

    // MARK: - Collapsed (only under load)

    private var collapsedView: some View {
        HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Self.cpuColor)
            Text(pct(stats.sample.cpu))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
        }
    }

    // MARK: - Expanded

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 6) {
            statRow(label: "CPU", icon: "cpu", value: stats.sample.cpu, color: Self.cpuColor)
            statRow(label: "MEM", icon: "memorychip", value: stats.sample.memUsed, color: Self.memColor)
        }
    }

    private func statRow(label: String, icon: String, value: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 30, alignment: .leading)
            bar(value: value, color: color)
            Text(pct(value))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func bar(value: Double, color: Color) -> some View {
        let fraction = min(1, max(0, value))
        return GeometryReader { geo in
            let fullWidth = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(color.opacity(0.9)).frame(width: fullWidth * fraction)
            }
        }
        .frame(height: 5)
    }

    private func pct(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
