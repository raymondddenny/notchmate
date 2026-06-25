import SwiftUI

/// GitHub-style contribution heatmap + streak/session stats for the Focus timer tile.
///
/// ponytail: history is local focus-session data only. Clean seam to swap in real
/// GitHub contribution data: replace the `history: [String: Int]` param with a
/// GitController-sourced dict keyed by "YYYY-MM-DD" -> commit count.
struct FocusStatsView: View {
    let history: [String: Int]
    let streak: Int
    let today: Int
    let total: Int

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            statsRow
            FocusHeatmapView(history: history)
        }
    }

    private var statsRow: some View {
        HStack(spacing: 5) {
            if streak > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                    Text("\(streak)d")
                }
                .foregroundStyle(Theme.accentTimer)
            } else {
                Image(systemName: "flame")
                    .foregroundStyle(Theme.textDisabled)
            }
            Text("·").foregroundStyle(Theme.textDisabled)
            Text("\(today) today")
                .foregroundStyle(today > 0 ? Theme.textSecondary : Theme.textTertiary)
            Text("·").foregroundStyle(Theme.textDisabled)
            Text("\(total) total")
                .foregroundStyle(Theme.textTertiary)
        }
        .font(Theme.captionFont)
    }
}

// MARK: - Heatmap grid

private struct FocusHeatmapView: View {
    let history: [String: Int]
    private let numWeeks = 12
    private let cellSize: CGFloat = 5
    private let cellGap: CGFloat = 1

    var body: some View {
        HStack(alignment: .top, spacing: cellGap) {
            ForEach(weekColumns.indices, id: \.self) { col in
                VStack(spacing: cellGap) {
                    ForEach(0..<7, id: \.self) { row in
                        cell(for: weekColumns[col][row])
                    }
                }
            }
        }
    }

    private func cell(for date: Date?) -> some View {
        let count: Int
        if let date {
            count = history[NotchPreferences.dateKey(for: date)] ?? 0
        } else {
            count = -1
        }
        return RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(cellColor(count))
            .frame(width: cellSize, height: cellSize)
            .opacity(count < 0 ? 0 : 1)  // future cells: invisible but preserve grid shape
    }

    private func cellColor(_ count: Int) -> Color {
        switch count {
        case 1:        return Theme.accentTimer.opacity(0.35)
        case 2:        return Theme.accentTimer.opacity(0.60)
        case 3...:     return Theme.accentTimer
        default:       return Theme.trackBackground
        }
    }

    /// [column][row], column 0 = oldest week, row 0 = Sunday.
    /// 12 columns of 7 days each; cells after today are nil (invisible).
    private var weekColumns: [[Date?]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)   // 1=Sun
        let thisSunday = cal.date(byAdding: .day, value: -(weekday - 1), to: today)!
        let startSunday = cal.date(byAdding: .weekOfYear, value: -(numWeeks - 1), to: thisSunday)!
        return (0..<numWeeks).map { w in
            let weekStart = cal.date(byAdding: .weekOfYear, value: w, to: startSunday)!
            return (0..<7).map { d -> Date? in
                let date = cal.date(byAdding: .day, value: d, to: weekStart)!
                return date <= today ? date : nil
            }
        }
    }
}

#if DEBUG
struct FocusStatsView_Previews: PreviewProvider {
    static var previews: some View {
        let cal = Calendar.current
        let today = Date()
        var history: [String: Int] = [:]
        for i in 0..<84 where i % 4 != 0 {
            if let d = cal.date(byAdding: .day, value: -i, to: today) {
                history[NotchPreferences.dateKey(for: d)] = (i % 7 == 0) ? 3 : (i % 3 == 0) ? 2 : 1
            }
        }
        return FocusStatsView(history: history, streak: 7, today: 2, total: 47)
            .padding()
            .background(Theme.panelBackground)
            .previewLayout(.sizeThatFits)
    }
}
#endif
