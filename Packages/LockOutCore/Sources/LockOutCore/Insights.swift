import Foundation

public enum AnalyticsDayType: String, Codable, CaseIterable, Sendable {
    case weekday
    case weekend
}

public struct BreakAnalyticsSnapshot: Equatable, Sendable {
    public var byHour: [Int: BreakStatusCounts]
    public var byDayType: [AnalyticsDayType: BreakStatusCounts]
    public var byProfile: [String: BreakStatusCounts]
    public var calendarOverlap: BreakStatusCounts
    public var fullscreenOverlap: BreakStatusCounts

    public init(
        byHour: [Int: BreakStatusCounts] = [:],
        byDayType: [AnalyticsDayType: BreakStatusCounts] = [:],
        byProfile: [String: BreakStatusCounts] = [:],
        calendarOverlap: BreakStatusCounts = BreakStatusCounts(),
        fullscreenOverlap: BreakStatusCounts = BreakStatusCounts()
    ) {
        self.byHour = byHour
        self.byDayType = byDayType
        self.byProfile = byProfile
        self.calendarOverlap = calendarOverlap
        self.fullscreenOverlap = fullscreenOverlap
    }
}

public final class BreakInsightsStore {
    private static let metadataKey = "lockout_break_insight_metadata"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func saveMetadata(_ metadata: BreakInsightMetadata?, for sessionID: UUID) {
        var stored = loadAll()
        if let metadata {
            stored[sessionID.uuidString] = metadata
        } else {
            stored.removeValue(forKey: sessionID.uuidString)
        }
        persist(stored)
    }

    public func metadata(for sessionID: UUID) -> BreakInsightMetadata? {
        loadAll()[sessionID.uuidString]
    }

    public func snapshot(for sessions: [BreakSession], calendar: Calendar = .current) -> BreakAnalyticsSnapshot {
        var byHour: [Int: BreakStatusCounts] = [:]
        var byDayType: [AnalyticsDayType: BreakStatusCounts] = [:]
        var byProfile: [String: BreakStatusCounts] = [:]
        var calendarOverlap = BreakStatusCounts()
        var fullscreenOverlap = BreakStatusCounts()
        let metadataMap = loadAll()

        for session in sessions {
            let hour = calendar.component(.hour, from: session.scheduledAt)
            var hourCounts = byHour[hour] ?? BreakStatusCounts()
            hourCounts.increment(for: session.status)
            byHour[hour] = hourCounts

            let dayType: AnalyticsDayType = calendar.isDateInWeekend(session.scheduledAt) ? .weekend : .weekday
            var dayCounts = byDayType[dayType] ?? BreakStatusCounts()
            dayCounts.increment(for: session.status)
            byDayType[dayType] = dayCounts

            if let metadata = metadataMap[session.id.uuidString] {
                let profileName = metadata.activeProfileName ?? "Unprofiled"
                var profileCounts = byProfile[profileName] ?? BreakStatusCounts()
                profileCounts.increment(for: session.status)
                byProfile[profileName] = profileCounts

                if metadata.calendarOverlap {
                    calendarOverlap.increment(for: session.status)
                }
                if metadata.fullscreenOverlap {
                    fullscreenOverlap.increment(for: session.status)
                }
            }
        }

        return BreakAnalyticsSnapshot(
            byHour: byHour,
            byDayType: byDayType,
            byProfile: byProfile,
            calendarOverlap: calendarOverlap,
            fullscreenOverlap: fullscreenOverlap
        )
    }

    private func loadAll() -> [String: BreakInsightMetadata] {
        guard let data = defaults.data(forKey: Self.metadataKey),
              let metadata = try? JSONDecoder().decode([String: BreakInsightMetadata].self, from: data) else { return [:] }
        return metadata
    }

    private func persist(_ metadata: [String: BreakInsightMetadata]) {
        defaults.set(try? JSONEncoder().encode(metadata), forKey: Self.metadataKey)
    }
}

public enum InsightsEngine {
    public static func generateCards(
        dailyStats: [DayStat],
        sessions: [BreakSession],
        analytics: BreakAnalyticsSnapshot,
        settings: AppSettings
    ) -> [InsightCard] {
        var cards: [InsightCard] = []

        if let hour = analytics.byHour.max(by: { lhs, rhs in
            (lhs.value.skipped + lhs.value.snoozed) < (rhs.value.skipped + rhs.value.snoozed)
        }), hour.value.skipped + hour.value.snoozed >= 2 {
            cards.append(
                InsightCard(
                    type: .skipHotspot,
                    title: "Avoidance hotspot",
                    summary: "Breaks are most often skipped or snoozed around \(format(hour: hour.key)).",
                    recommendation: "Adjust the active profile or defer strategy for that window.",
                    destination: "profiles"
                )
            )
        }

        if let hour = analytics.byHour.max(by: { $0.value.deferred < $1.value.deferred }), hour.value.deferred >= 2 {
            cards.append(
                InsightCard(
                    type: .deferHotspot,
                    title: "Deferred break cluster",
                    summary: "Deferred breaks stack up most often around \(format(hour: hour.key)).",
                    recommendation: "Try task-boundary deferrals or a lighter profile in that period.",
                    destination: "dashboard"
                )
            )
        }

        let profileRates = analytics.byProfile.compactMapValues { counts -> Double? in
            guard counts.userActionTotal > 0 else { return nil }
            return Double(counts.completed) / Double(counts.userActionTotal)
        }
        if let best = profileRates.max(by: { $0.value < $1.value }),
           let worst = profileRates.min(by: { $0.value < $1.value }),
           best.key != worst.key,
           best.value - worst.value >= 0.15 {
            cards.append(
                InsightCard(
                    type: .profileComparison,
                    title: "Profile gap detected",
                    summary: "\"\(best.key)\" is outperforming \"\(worst.key)\" by \(Int((best.value - worst.value) * 100)) points.",
                    recommendation: "Reuse the stronger profile's rules or enforcement in the weaker context.",
                    destination: "profiles"
                )
            )
        }

        if analytics.calendarOverlap.allOutcomesTotal >= 2,
           analytics.calendarOverlap.skipped + analytics.calendarOverlap.snoozed + analytics.calendarOverlap.deferred >= 2 {
            cards.append(
                InsightCard(
                    type: .meetingCollision,
                    title: "Meetings are colliding with breaks",
                    summary: "A notable share of skipped or deferred breaks happened during active calendar events.",
                    recommendation: "Tune calendar matching or add a manager-style profile for meeting-heavy blocks.",
                    destination: "settings:auto-pause"
                )
            )
        }

        let recentCounts = dailyStats.suffix(3).reduce(into: BreakStatusCounts()) { result, stat in
            result.completed += stat.completed
            result.skipped += stat.skipped
            result.snoozed += stat.snoozed
            result.deferred += stat.deferred
        }
        if settings.recoveryModeConfig.shouldSuggest(skipCount: recentCounts.skipped, snoozeCount: recentCounts.snoozed) {
            cards.append(
                InsightCard(
                    type: .streakRisk,
                    title: settings.recoveryModeConfig.isEnabled ? "Recovery mode is active" : "Recovery mode suggested",
                    summary: settings.recoveryModeConfig.coachingCopy,
                    recommendation: settings.recoveryModeConfig.isEnabled ? "Keep the stricter mode until avoidance drops." : "Opt in to recovery mode if the pattern continues.",
                    destination: "settings:recovery"
                )
            )
        }

        let daypartBuckets = groupByDaypart(sessions)
        if let best = daypartBuckets.max(by: { lhs, rhs in lhs.value < rhs.value }), best.value > 0 {
            cards.append(
                InsightCard(
                    type: .bestDaypart,
                    title: "Best compliance window",
                    summary: "You are most consistent during the \(best.key) period.",
                    recommendation: "Use that period as the template for future automatic profile rules.",
                    destination: "profiles"
                )
            )
        }

        return Array(cards.prefix(3))
    }

    private static func format(hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    private static func groupByDaypart(_ sessions: [BreakSession], calendar: Calendar = .current) -> [String: Double] {
        var buckets: [String: BreakStatusCounts] = [:]
        for session in sessions {
            let hour = calendar.component(.hour, from: session.scheduledAt)
            let key: String
            switch hour {
            case 6..<12: key = "morning"
            case 12..<17: key = "afternoon"
            case 17..<22: key = "evening"
            default: key = "late"
            }
            var counts = buckets[key] ?? BreakStatusCounts()
            counts.increment(for: session.status)
            buckets[key] = counts
        }

        return buckets.compactMapValues { counts in
            guard counts.userActionTotal > 0 else { return nil }
            return Double(counts.completed) / Double(counts.userActionTotal)
        }
    }
}
