import Foundation
import SwiftData

public final class BreakHistoryRepository {
    private let context: ModelContext

    public init(modelContext: ModelContext) {
        self.context = modelContext
    }

    public func save(_ session: BreakSession) {
        let record = BreakSessionRecord(from: session)
        context.insert(record)
        try? context.save()
    }

    public func fetchSessions(from startDate: Date, to endDate: Date) -> [BreakSession] {
        let descriptor = FetchDescriptor<BreakSessionRecord>(
            predicate: #Predicate { $0.scheduledAt >= startDate && $0.scheduledAt <= endDate }
        )
        return (try? context.fetch(descriptor))?.compactMap { $0.toBreakSession() } ?? []
    }

    public func pruneOldRecords(retentionDays: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<BreakSessionRecord>(
            predicate: #Predicate { $0.scheduledAt < cutoff }
        )
        guard let old = try? context.fetch(descriptor) else { return }
        old.forEach { context.delete($0) }
        try? context.save()
    }

    public func dailyStats(for days: Int) -> [DayStat] {
        let cal = Calendar.current
        let end = Date()
        let start = cal.date(byAdding: .day, value: -days, to: end) ?? end
        let sessions = fetchSessions(from: start, to: end)
        var map: [Date: (Int, Int)] = [:]
        for s in sessions {
            let day = cal.startOfDay(for: s.scheduledAt)
            var (c, k) = map[day] ?? (0, 0)
            if s.status == .completed { c += 1 } else if s.status == .skipped { k += 1 }
            map[day] = (c, k)
        }
        return map.map { DayStat(date: $0.key, completed: $0.value.0, skipped: $0.value.1) }
                  .sorted { $0.date < $1.date }
    }
}
