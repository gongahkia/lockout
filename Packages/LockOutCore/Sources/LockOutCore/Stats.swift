import Foundation

public struct DayStat: Sendable {
    public let date: Date
    public let completed: Int
    public let skipped: Int
    public var perTypeCounts: [String: (completed: Int, skipped: Int)]
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
    public static let streakThreshold: Double = 0.8

    public static func streakDays(stats: [DayStat]) -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let sorted = stats.sorted { $0.date > $1.date }
        guard let first = sorted.first, cal.startOfDay(for: first.date) == today, first.complianceRate >= streakThreshold else { return 0 }
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
        let total = stats.reduce(0) { $0 + $1.completed }
        let all = stats.reduce(0) { $0 + $1.completed + $1.skipped }
        return Double(total) / Double(max(all, 1))
    }

    // #21 trend: percentage-point change compared to prior period of same length
    public static func trend(current: [DayStat], previous: [DayStat]) -> Double {
        overallRate(stats: current) - overallRate(stats: previous)
    }

    // #21 "almost" streak: days until last break below threshold; returns (streakDays, nearMissDays)
    // nearMissDays = consecutive days at >= 60% but < 80% following the streak
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
                    if stat.complianceRate >= 0.6 { nearMiss += 1 }
                    else { break }
                }
            } else {
                if stat.complianceRate >= 0.6 && stat.complianceRate < streakThreshold {
                    nearMiss += 1
                } else {
                    break
                }
            }
            current = cal.date(byAdding: .day, value: -1, to: current)!
        }
        return (streak, nearMiss)
    }
}
