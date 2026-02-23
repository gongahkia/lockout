import SwiftUI
import Charts
import LockOutCore

struct StatisticsView: View {
    @State private var range = 7
    private var repo: BreakHistoryRepository { AppDelegate.shared.repository }
    private var stats: [DayStat] { repo.dailyStats(for: range) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Range", selection: $range) {
                Text("7 days").tag(7)
                Text("14 days").tag(14)
                Text("30 days").tag(30)
            }
            .pickerStyle(.segmented)
            Chart {
                ForEach(stats, id: \.date) { s in
                    BarMark(x: .value("Date", s.date, unit: .day),
                            y: .value("Completed", s.completed))
                    .foregroundStyle(.green)
                    BarMark(x: .value("Date", s.date, unit: .day),
                            y: .value("Skipped", s.skipped))
                    .foregroundStyle(.red)
                }
            }
            .frame(height: 200)
            // legend
            HStack(spacing: 12) {
                legendDot(color: .green, label: "Completed")
                legendDot(color: .red, label: "Skipped")
            }
            // summary
            let total = stats.reduce(0) { $0 + $1.completed + $1.skipped }
            let rate = ComplianceCalculator.overallRate(stats: stats)
            let streak = ComplianceCalculator.streakDays(stats: stats)
            HStack(spacing: 24) {
                summaryCell(value: "\(total)", label: "Total")
                summaryCell(value: "\(Int(rate * 100))%", label: "Compliance")
                summaryCell(value: "\(streak)d", label: "Streak")
            }
        }
            Button("Export CSV") { exportCSV() }
        }
        .padding(24)
        .navigationTitle("Statistics")
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "lockout-stats.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var csv = "date,completed,skipped\n"
        let fmt = ISO8601DateFormatter()
        for s in stats { csv += "\(fmt.string(from: s.date)),\(s.completed),\(s.skipped)\n" }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 4).fill(color).frame(width: 14, height: 14)
            Text(label).font(.caption)
        }
    }

    private func summaryCell(value: String, label: String) -> some View {
        VStack { Text(value).font(.title2).bold(); Text(label).font(.caption).foregroundStyle(.secondary) }
    }
}
