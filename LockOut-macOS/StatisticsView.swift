import AppKit
import Charts
import LockOutCore
import SwiftUI

private struct StatisticsSeries: Identifiable {
    let id: String
    let label: String
    let color: Color
    let value: (DayStat) -> Int
}

struct StatisticsView: View {
    let repository: BreakHistoryRepository
    let cloudSync: CloudKitSyncService

    @State private var range = 7

    private var stats: [DayStat] {
        repository.dailyStats(for: range)
    }

    private var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }

    private var insightCards: [InsightCard] {
        appDelegate?.insightCards(range: max(range, 7)) ?? []
    }

    private var totalSessions: Int {
        stats.reduce(0) { $0 + $1.counts.allOutcomesTotal }
    }

    private var complianceRate: Double {
        ComplianceCalculator.overallRate(stats: stats)
    }

    private var streakInfo: (streak: Int, nearMiss: Int) {
        ComplianceCalculator.streakWithNearMiss(stats: repository.dailyStats(for: 30))
    }

    private var previousStats: [DayStat] {
        Array(repository.dailyStats(for: range * 2).prefix(range))
    }

    private var trend: Double {
        ComplianceCalculator.trend(current: stats, previous: previousStats)
    }

    private var chartSeries: [StatisticsSeries] {
        [
            StatisticsSeries(id: "completed", label: "Completed", color: LockOutPalette.mint, value: { $0.completed }),
            StatisticsSeries(id: "skipped", label: "Skipped", color: LockOutPalette.coral, value: { $0.skipped }),
            StatisticsSeries(id: "snoozed", label: "Snoozed", color: LockOutPalette.amber, value: { $0.snoozed }),
            StatisticsSeries(id: "deferred", label: "Deferred", color: LockOutPalette.sky, value: { $0.deferred }),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LockOutScreenHeader(
                    title: "Statistics",
                    subtitle: "Track compliance, identify drift, and export the same history used to power insights and sync.",
                    symbol: "chart.bar.xaxis",
                    accent: LockOutPalette.sky
                )

                LockOutCard(accent: LockOutPalette.sky) {
                    HStack(alignment: .top, spacing: 16) {
                        Picker("Range", selection: $range) {
                            Text("7 days").tag(7)
                            Text("14 days").tag(14)
                            Text("30 days").tag(30)
                        }
                        .pickerStyle(.segmented)

                        Spacer(minLength: 12)

                        Button("Export CSV", action: exportCSV)
                            .buttonStyle(.bordered)
                        Button("Export JSON", action: exportJSON)
                            .buttonStyle(.borderedProminent)
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 14)], spacing: 14) {
                    LockOutMetricTile(
                        value: "\(totalSessions)",
                        label: "Total sessions",
                        detail: "Across the selected range",
                        accent: LockOutPalette.sky
                    )
                    LockOutMetricTile(
                        value: "\(Int(complianceRate * 100))%",
                        label: "Compliance",
                        detail: trendDetail,
                        accent: trend >= 0 ? LockOutPalette.mint : LockOutPalette.coral
                    )
                    LockOutMetricTile(
                        value: "\(streakInfo.streak)d",
                        label: "Current streak",
                        detail: streakInfo.nearMiss > 0 ? "\(streakInfo.nearMiss)d near miss" : "No near misses",
                        accent: LockOutPalette.amber
                    )
                    LockOutMetricTile(
                        value: "\(cloudSync.pendingUploadsCount)",
                        label: "Pending uploads",
                        detail: cloudSync.pendingUploadsCount == 0 ? "Cloud history is current" : "Waiting to sync",
                        accent: cloudSync.pendingUploadsCount == 0 ? LockOutPalette.mint : LockOutPalette.amber
                    )
                }

                LockOutCard(
                    title: "Break Outcomes",
                    subtitle: "Grouped by day and outcome so you can spot where compliance is improving or slipping.",
                    icon: "chart.bar.doc.horizontal",
                    accent: LockOutPalette.sky
                ) {
                    if stats.isEmpty {
                        LockOutEmptyState(
                            symbol: "chart.bar.xaxis.ascending",
                            title: "No history yet",
                            message: "Break statistics will appear here once LockOut records completed, skipped, snoozed, or deferred sessions."
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 16) {
                            Chart {
                                ForEach(stats, id: \.date) { dayStat in
                                    ForEach(chartSeries) { series in
                                        BarMark(
                                            x: .value("Date", dayStat.date, unit: .day),
                                            y: .value(series.label, series.value(dayStat))
                                        )
                                        .position(by: .value("Outcome", series.label))
                                        .foregroundStyle(series.color.gradient)
                                    }
                                }
                            }
                            .frame(height: 260)

                            HStack(spacing: 10) {
                                ForEach(chartSeries) { series in
                                    StatisticsLegendItem(color: series.color, label: series.label)
                                }
                            }
                        }
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        syncCard
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        if !insightCards.isEmpty {
                            insightCard
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        syncCard
                        if !insightCards.isEmpty {
                            insightCard
                        }
                    }
                }
            }
            .padding(28)
        }
        .background(LockOutSceneBackground())
        .navigationTitle("Statistics")
    }

    private var trendDetail: String {
        guard trend != 0 else {
            return "Steady versus the prior period"
        }
        let sign = trend > 0 ? "+" : ""
        return "\(sign)\(Int(trend * 100))pp versus prior period"
    }

    private var syncCard: some View {
        LockOutCard(
            title: "Sync Status",
            subtitle: "Cloud history uploads are tracked independently from the local statistics cache.",
            icon: "icloud",
            accent: LockOutPalette.mint
        ) {
            VStack(alignment: .leading, spacing: 10) {
                LockOutKeyValueRow(
                    label: "Mode",
                    value: cloudSync.pendingUploadsCount == 0 ? "Healthy" : "Needs upload"
                )
                LockOutKeyValueRow(
                    label: "Last sync",
                    value: cloudSync.lastSyncDate == .distantPast
                        ? "Never"
                        : cloudSync.lastSyncDate.formatted(.dateTime.month().day().hour().minute())
                )
                LockOutKeyValueRow(label: "Pending uploads", value: "\(cloudSync.pendingUploadsCount)")
            }
        }
    }

    private var insightCard: some View {
        LockOutCard(
            title: "Insights",
            subtitle: "Recommendations derived from the same statistics shown above.",
            icon: "lightbulb",
            accent: LockOutPalette.amber
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(insightCards) { card in
                    LockOutInsightRow(card: card, accent: LockOutPalette.amber)
                }
            }
        }
    }

    private var allTypeNames: [String] {
        Array(Set(stats.flatMap { $0.perTypeCounts.keys })).sorted()
    }

    private func exportJSON() {
        let formatter = ISO8601DateFormatter()
        let typeNames = allTypeNames
        let rows = stats.map { stat -> [String: Any] in
            var row: [String: Any] = [
                "date": formatter.string(from: stat.date),
                "completed": stat.completed,
                "skipped": stat.skipped,
                "snoozed": stat.snoozed,
                "deferred": stat.deferred,
            ]
            for name in typeNames {
                let counts = stat.perTypeCounts[name] ?? BreakStatusCounts()
                row["\(name)_completed"] = counts.completed
                row["\(name)_skipped"] = counts.skipped
                row["\(name)_snoozed"] = counts.snoozed
                row["\(name)_deferred"] = counts.deferred
            }
            return row
        }

        guard let data = try? JSONSerialization.data(withJSONObject: rows, options: .prettyPrinted) else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "lockout-stats.json"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        try? data.write(to: url)
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "lockout-stats.csv"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        let typeNames = allTypeNames
        let typeHeaders = typeNames.flatMap {
            ["\($0)_completed", "\($0)_skipped", "\($0)_snoozed", "\($0)_deferred"]
        }
        let headers = (["date", "completed", "skipped", "snoozed", "deferred"] + typeHeaders)
            .map(CSVExport.escapedCell)
        var csv = headers.joined(separator: ",") + "\n"
        let formatter = ISO8601DateFormatter()

        for stat in stats {
            var row = [
                formatter.string(from: stat.date),
                "\(stat.completed)",
                "\(stat.skipped)",
                "\(stat.snoozed)",
                "\(stat.deferred)",
            ]
            for name in typeNames {
                let counts = stat.perTypeCounts[name] ?? BreakStatusCounts()
                row += [
                    "\(counts.completed)",
                    "\(counts.skipped)",
                    "\(counts.snoozed)",
                    "\(counts.deferred)",
                ]
            }
            csv += row.map(CSVExport.escapedCell).joined(separator: ",") + "\n"
        }

        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }
}

private struct StatisticsLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(color)
                .frame(width: 14, height: 14)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
