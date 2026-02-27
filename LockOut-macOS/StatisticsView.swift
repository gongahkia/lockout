import SwiftUI
import Charts
import LockOutCore

struct StatisticsView: View {
    @State private var range = 7
    private var repo: BreakHistoryRepository { AppDelegate.shared.repository }
    private var cloudSync: CloudKitSyncService { AppDelegate.shared.cloudSync }
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
            syncStatusRow
            HStack {
                Button("Export CSV") { exportCSV() }
                Button("Export JSON") { exportJSON() }
            }
        }
        .padding(24)
        .navigationTitle("Statistics")
    }

    @ViewBuilder private var syncStatusRow: some View {
        let pending = cloudSync.pendingUploadsCount
        let lastSync = cloudSync.lastSyncDate
        HStack(spacing: 6) {
            if pending > 0 {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text("\(pending) pending upload\(pending == 1 ? "" : "s")")
            } else {
                Image(systemName: "checkmark.icloud").foregroundStyle(.secondary)
            }
            Spacer()
            if lastSync == .distantPast {
                Text("Never synced").foregroundStyle(.secondary)
            } else {
                Text("Last synced: \(lastSync.formatted(.dateTime.month().day().hour().minute()))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var allTypeNames: [String] {
        Array(Set(stats.flatMap { $0.perTypeCounts.keys })).sorted()
    }

    private func exportJSON() {
        let fmt = ISO8601DateFormatter()
        let typeNames = allTypeNames
        let rows = stats.map { s -> [String: Any] in
            var row: [String: Any] = ["date": fmt.string(from: s.date),
                                       "completed": s.completed, "skipped": s.skipped]
            for name in typeNames {
                let (c, k) = s.perTypeCounts[name] ?? (0, 0)
                row["\(name)_completed"] = c
                row["\(name)_skipped"] = k
            }
            return row
        }
        guard let data = try? JSONSerialization.data(withJSONObject: rows, options: .prettyPrinted) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "lockout-stats.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "lockout-stats.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let typeNames = allTypeNames
        let typeHeaders = typeNames.flatMap { ["\($0)_completed", "\($0)_skipped"] }
        var csv = (["date", "completed", "skipped"] + typeHeaders).joined(separator: ",") + "\n"
        let fmt = ISO8601DateFormatter()
        for s in stats {
            var row = [fmt.string(from: s.date), "\(s.completed)", "\(s.skipped)"]
            for name in typeNames {
                let (c, k) = s.perTypeCounts[name] ?? (0, 0)
                row += ["\(c)", "\(k)"]
            }
            csv += row.joined(separator: ",") + "\n"
        }
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
