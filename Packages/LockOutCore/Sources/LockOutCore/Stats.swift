import Foundation

public struct BreakStatusCounts: Codable, Equatable, Sendable {
    public var completed: Int
    public var skipped: Int
    public var snoozed: Int
    public var deferred: Int

    public init(completed: Int = 0, skipped: Int = 0, snoozed: Int = 0, deferred: Int = 0) {
        self.completed = completed
        self.skipped = skipped
        self.snoozed = snoozed
        self.deferred = deferred
    }

    public var userActionTotal: Int {
        completed + skipped + snoozed
    }

    public var allOutcomesTotal: Int {
        completed + skipped + snoozed + deferred
    }

    public mutating func increment(for status: BreakStatus) {
        switch status {
        case .completed: completed += 1
        case .skipped: skipped += 1
        case .snoozed: snoozed += 1
        case .deferred: deferred += 1
        }
    }
}

public struct DayStat: Sendable {
    public let date: Date
    public var counts: BreakStatusCounts
    public var perTypeCounts: [String: BreakStatusCounts]

    public var completed: Int { counts.completed }
    public var skipped: Int { counts.skipped }
    public var snoozed: Int { counts.snoozed }
    public var deferred: Int { counts.deferred }
    public var complianceRate: Double {
        Double(counts.completed) / Double(max(counts.userActionTotal, 1))
    }

    public init(
        date: Date,
        completed: Int,
        skipped: Int,
        snoozed: Int = 0,
        deferred: Int = 0,
        perTypeCounts: [String: BreakStatusCounts] = [:]
    ) {
        self.date = date
        self.counts = BreakStatusCounts(completed: completed, skipped: skipped, snoozed: snoozed, deferred: deferred)
        self.perTypeCounts = perTypeCounts
    }

    public init(date: Date, counts: BreakStatusCounts, perTypeCounts: [String: BreakStatusCounts] = [:]) {
        self.date = date
        self.counts = counts
        self.perTypeCounts = perTypeCounts
    }
}

public enum ComplianceCalculator {
    public static let streakThreshold: Double = 0.8

    public static func streakDays(stats: [DayStat]) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let sorted = stats.sorted { $0.date > $1.date }
        guard let first = sorted.first,
              cal.startOfDay(for: first.date) == today,
              first.complianceRate >= streakThreshold else { return 0 }
        var streak = 0
        var current = today
        for stat in sorted {
            guard cal.startOfDay(for: stat.date) == current, stat.complianceRate >= streakThreshold else { break }
            streak += 1
            current = cal.date(byAdding: .day, value: -1, to: current)!
        }
        return streak
    }

    public static func overallRate(stats: [DayStat]) -> Double {
        let totalCompleted = stats.reduce(0) { $0 + $1.completed }
        let totalConsidered = stats.reduce(0) { $0 + $1.counts.userActionTotal }
        return Double(totalCompleted) / Double(max(totalConsidered, 1))
    }

    public static func trend(current: [DayStat], previous: [DayStat]) -> Double {
        overallRate(stats: current) - overallRate(stats: previous)
    }

    public static func streakWithNearMiss(stats: [DayStat]) -> (streak: Int, nearMiss: Int) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let sorted = stats.sorted { $0.date > $1.date }

        var streak = 0
        var nearMiss = 0
        var current = today
        var inStreak = true

        for stat in sorted {
            let day = cal.startOfDay(for: stat.date)
            guard day == current else { break }
            if inStreak {
                if stat.complianceRate >= streakThreshold {
                    streak += 1
                } else {
                    inStreak = false
                    if stat.complianceRate >= 0.6 {
                        nearMiss += 1
                    } else {
                        break
                    }
                }
            } else if stat.complianceRate >= 0.6 && stat.complianceRate < streakThreshold {
                nearMiss += 1
            } else {
                break
            }
            current = cal.date(byAdding: .day, value: -1, to: current)!
        }
        return (streak, nearMiss)
    }
}
