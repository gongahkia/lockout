import Foundation

public struct DayStat: Sendable {
    public let date: Date
    public let completed: Int
    public let skipped: Int
    public var perTypeCounts: [String: (completed: Int, skipped: Int)]  // breakTypeName -> counts
    public var complianceRate: Double {
        Double(completed) / Double(max(completed + skipped, 1))
    }

    public init(date: Date, completed: Int, skipped: Int,
                perTypeCounts: [String: (completed: Int, skipped: Int)] = [:]) {
        self.date = date
        self.completed = completed
        self.skipped = skipped
        self.perTypeCounts = perTypeCounts
    }
}

// MARK: - ComplianceCalculator
public enum ComplianceCalculator {
    public static func streakDays(stats: [DayStat]) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let sorted = stats.sorted { $0.date > $1.date }
        guard let first = sorted.first, cal.startOfDay(for: first.date) == today, first.complianceRate >= 0.8 else { return 0 }
        var streak = 0
        var current = today
        for stat in sorted {
            guard cal.startOfDay(for: stat.date) == current, stat.complianceRate >= 0.8 else { break }
            streak += 1
            current = cal.date(byAdding: .day, value: -1, to: current)!
        }
        return streak
    }

    public static func overallRate(stats: [DayStat]) -> Double {
        let total = stats.reduce(0) { $0 + $1.completed }
        let all = stats.reduce(0) { $0 + $1.completed + $1.skipped }
        return Double(total) / Double(max(all, 1))
    }
}
