import Foundation
import CloudKit

public final class CloudKitSyncService {
    private let db: CKDatabase = {
        let id = Bundle.main.object(forInfoDictionaryKey: "CLOUDKIT_CONTAINER_ID") as? String
            ?? "iCloud.com.yourapp.lockout" // fallback for unit test context
        return CKContainer(identifier: id).privateCloudDatabase
    }()
    private static let lastSyncKey = "ck_last_sync_date"
    public var onError: ((String) -> Void)?

    public init() {}

    private var lastSyncDate: Date {
        get { (UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date) ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastSyncKey) }
    }

    public func uploadSession(_ session: BreakSession) async {
        let recordID = CKRecord.ID(recordName: session.id.uuidString)
        let record = CKRecord(recordType: "BreakSession", recordID: recordID)
        record["id"] = session.id.uuidString as CKRecordValue
        record["type"] = session.type.rawValue as CKRecordValue
        record["scheduledAt"] = session.scheduledAt as CKRecordValue
        record["status"] = session.status.rawValue as CKRecordValue
        do {
            try await db.save(record)
        } catch {
            handle(error: error)
        }
    }

    public func fetchSessions(since date: Date) async -> [BreakSession] {
        let predicate = NSPredicate(format: "modificationDate > %@", date as CVarArg)
        let query = CKQuery(recordType: "BreakSession", predicate: predicate)
        do {
            let result = try await db.records(matching: query)
            return result.matchResults.compactMap { _, res in
                guard let r = try? res.get() else { return nil }
                return mapRecord(r)
            }
        } catch {
            handle(error: error)
            return []
        }
    }

    public func sync(repository: BreakHistoryRepository) async {
        let remote = await fetchSessions(since: lastSyncDate)
        for session in remote {
            let local = repository.fetchSession(id: session.id)
            repository.save(resolveConflict(local: local, remote: session))
        }
        let end = Date()
        let local = repository.fetchSessions(from: lastSyncDate, to: end)
        for session in local { await uploadSession(session) }
        lastSyncDate = end
    }

    // prefer completed > snoozed > skipped
    private func resolveConflict(local: BreakSession?, remote: BreakSession) -> BreakSession {
        guard let local = local else { return remote }
        guard local.id == remote.id else { return remote }
        let rank: (BreakStatus) -> Int = { s in
            switch s { case .completed: 2; case .snoozed: 1; case .skipped: 0 }
        }
        return rank(local.status) >= rank(remote.status) ? local : remote
    }

    private func mapRecord(_ r: CKRecord) -> BreakSession? {
        guard let idStr = r["id"] as? String,
              let id = UUID(uuidString: idStr),
              let typeStr = r["type"] as? String,
              let type = BreakType(rawValue: typeStr),
              let scheduledAt = r["scheduledAt"] as? Date,
              let statusStr = r["status"] as? String,
              let status = BreakStatus(rawValue: statusStr) else { return nil }
        return BreakSession(id: id, type: type, scheduledAt: scheduledAt, status: status)
    }

    private func handle(error: Error) {
        guard let ckError = error as? CKError else {
            print("[CloudKit] error: \(error)")
            onError?(error.localizedDescription)
            return
        }
        switch ckError.code {
        case .networkUnavailable:
            print("[CloudKit] non-fatal: \(ckError.code)")
        case .quotaExceeded:
            print("[CloudKit] non-fatal: \(ckError.code)")
            onError?(ckError.localizedDescription)
        case .accountTemporarilyUnavailable:
            NotificationCenter.default.post(name: .cloudKitAccountUnavailable, object: nil)
            onError?(ckError.localizedDescription)
        default:
            print("[CloudKit] error: \(ckError)")
            onError?(ckError.localizedDescription)
        }
    }
}

public extension Notification.Name {
    static let cloudKitAccountUnavailable = Notification.Name("cloudKitAccountUnavailable")
}
