import SwiftUI

/// System-load widget. Collapsed: a compact CPU% badge that only appears under heavy
/// load (stays quiet when the machine is idle). Expanded: CPU + memory mini-bars with
/// percentages, always shown.
struct SystemStatsWidget: View {
    @ObservedObject var stats: SystemStatsController
    let expanded: Bool

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
        HStack(spacing: Theme.sp1 + 1) {
            Image(systemName: "flame.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accentCPU)
            Text(pct(stats.sample.cpu))
                .font(Theme.chipMonoFont)
                .monospacedDigit()
        }
    }

    // MARK: - Expanded

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: Theme.sp1 + 1) {
            statRow(label: "CPU", icon: "cpu", value: stats.sample.cpu, color: Theme.accentCPU)
            statRow(label: "MEM", icon: "memorychip", value: stats.sample.memUsed, color: Theme.accentMem)
        }
    }

    private func statRow(label: String, icon: String, value: Double, color: Color) -> some View {
        HStack(spacing: Theme.sp2) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(label)
                .font(Theme.labelFont)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, alignment: .leading)
            bar(value: value, color: color)
            Text(pct(value))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func bar(value: Double, color: Color) -> some View {
        let fraction = min(1, max(0, value))
        return GeometryReader { geo in
            let fullWidth = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.trackBackground)
                Capsule().fill(color.opacity(0.9)).frame(width: fullWidth * fraction)
            }
        }
        .frame(height: 5)
    }

    private func pct(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
