import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.lockout", category: "BreakHistoryRepository") // #27

@MainActor
public final class BreakHistoryRepository {
    private let context: ModelContext

    public init(modelContext: ModelContext) {
        self.context = modelContext
    }

    public func fetchSession(id: UUID) -> BreakSession? {
        let descriptor = FetchDescriptor<BreakSessionRecord>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first?.toBreakSession()
    }

    public func save(_ session: BreakSession) {
        if let existing = (try? context.fetch(FetchDescriptor<BreakSessionRecord>(predicate: #Predicate { $0.id == session.id })))?.first {
            existing.status = session.status.rawValue
            existing.endedAt = session.endedAt
            if let name = session.breakTypeName { existing.breakTypeName = name }
            existing.updatedAt = session.updatedAt ?? Date()
        } else {
            context.insert(BreakSessionRecord(from: session))
        }
        do {
            try context.save()
        } catch {
            Observability.emit(category: "BreakHistoryRepository", message: "save failed: \(error)", level: .error)
            logger.error("save failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func fetchSessions(from startDate: Date, to endDate: Date) -> [BreakSession] {
        let descriptor = FetchDescriptor<BreakSessionRecord>(
            predicate: #Predicate { $0.scheduledAt >= startDate && $0.scheduledAt <= endDate }
        )
        return (try? context.fetch(descriptor))?.compactMap { $0.toBreakSession() } ?? []
    }

    public func pruneOldRecords(retentionDays: Int) {
        guard retentionDays > 0 else { return } // 0 = unlimited, keep all
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<BreakSessionRecord>(predicate: #Predicate { $0.scheduledAt < cutoff })
        do {
            let old = try context.fetch(descriptor)
            old.forEach { context.delete($0) }
            try context.save()
        } catch {
            Observability.emit(category: "BreakHistoryRepository", message: "pruneOldRecords failed: \(error)", level: .error)
            logger.error("pruneOldRecords failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func dailyStats(for days: Int) -> [DayStat] {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let end = Date()
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -(days - 1), to: startOfToday)!)
        let sessions = fetchSessions(from: start, to: end)
        var map: [Date: BreakStatusCounts] = [:]
        var typeMap: [Date: [String: BreakStatusCounts]] = [:]
        for s in sessions {
            let day = cal.startOfDay(for: s.scheduledAt)
            var dayCounts = map[day] ?? BreakStatusCounts()
            dayCounts.increment(for: s.status)
            map[day] = dayCounts
            let typeName = s.breakTypeName ?? s.type.rawValue
            var perType = typeMap[day] ?? [:]
            var typeCounts = perType[typeName] ?? BreakStatusCounts()
            typeCounts.increment(for: s.status)
            perType[typeName] = typeCounts
            typeMap[day] = perType
        }
        return map.map { DayStat(date: $0.key, counts: $0.value, perTypeCounts: typeMap[$0.key] ?? [:]) }
                  .sorted { $0.date < $1.date }
    }

    public func recentSessions(for days: Int) -> [BreakSession] {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let end = Date()
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -(days - 1), to: startOfToday)!)
        return fetchSessions(from: start, to: end)
    }

    public func analyticsSnapshot(for days: Int, insightsStore: BreakInsightsStore) -> BreakAnalyticsSnapshot {
        insightsStore.snapshot(for: recentSessions(for: days))
    }
}
