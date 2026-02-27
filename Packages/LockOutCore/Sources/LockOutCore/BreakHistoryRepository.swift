import Foundation
import SwiftData

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
        } else {
            context.insert(BreakSessionRecord(from: session))
        }
        do { try context.save() } catch { fputs("[SwiftData] \(error)\n", stderr) }
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
            fputs("[SwiftData] pruneOldRecords: \(error)\n", stderr)
        }
    }

    public func dailyStats(for days: Int) -> [DayStat] {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: Date())
        let end = Date()
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -(days - 1), to: startOfToday)!)
        let sessions = fetchSessions(from: start, to: end)
        var map: [Date: (Int, Int)] = [:]
        var typeMap: [Date: [String: (Int, Int)]] = [:]
        for s in sessions {
            let day = cal.startOfDay(for: s.scheduledAt)
            var (c, k) = map[day] ?? (0, 0)
            if s.status == .completed { c += 1 } else if s.status == .skipped { k += 1 }
            map[day] = (c, k)
            let typeName = s.breakTypeName ?? s.type.rawValue
            var perType = typeMap[day] ?? [:]
            var (tc, tk) = perType[typeName] ?? (0, 0)
            if s.status == .completed { tc += 1 } else if s.status == .skipped { tk += 1 }
            perType[typeName] = (tc, tk)
            typeMap[day] = perType
        }
        return map.map { DayStat(date: $0.key, completed: $0.value.0, skipped: $0.value.1,
                                 perTypeCounts: typeMap[$0.key] ?? [:]) }
                  .sorted { $0.date < $1.date }
    }
}
