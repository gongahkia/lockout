import SwiftUI
import Charts
import LookAwayCore

struct iOSStatisticsView: View {
    @State private var range = 7
    private var delegate: iOSAppDelegate { .shared }
    private var stats: [DayStat] { delegate.repository.dailyStats(for: range) }

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Range", selection: $range) {
                    Text("7d").tag(7); Text("14d").tag(14); Text("30d").tag(30)
                }.pickerStyle(.segmented).padding(.horizontal)
                Chart {
                    ForEach(stats, id: \.date) { s in
                        BarMark(x: .value("Date", s.date, unit: .day), y: .value("Done", s.completed)).foregroundStyle(.green)
                        BarMark(x: .value("Date", s.date, unit: .day), y: .value("Skip", s.skipped)).foregroundStyle(.red)
                    }
                }.frame(height: 180).padding(.horizontal)
                let total = stats.reduce(0) { $0 + $1.completed + $1.skipped }
                let rate = ComplianceCalculator.overallRate(stats: stats)
                let streak = ComplianceCalculator.streakDays(stats: stats)
                HStack(spacing: 24) {
                    summaryCell("\(total)", "Total")
                    summaryCell("\(Int(rate * 100))%", "Rate")
                    summaryCell("\(streak)d", "Streak")
                }.padding(.horizontal)
                Spacer()
            }
            .navigationTitle("Statistics")
        }
    }

    private func summaryCell(_ val: String, _ label: String) -> some View {
        VStack { Text(val).font(.title2).bold(); Text(label).font(.caption).foregroundStyle(.secondary) }
    }
}
