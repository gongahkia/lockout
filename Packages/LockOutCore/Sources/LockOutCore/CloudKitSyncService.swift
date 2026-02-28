import Foundation
import CloudKit
import Combine
import os

private let logger = Logger(subsystem: "com.yourapp.lockout", category: "CloudKitSyncService")

public final class CloudKitSyncService {
    private lazy var db: CKDatabase = {
        let id = Bundle.main.object(forInfoDictionaryKey: "CLOUDKIT_CONTAINER_ID") as? String
            ?? "iCloud.com.yourapp.lockout" // fallback for unit test context
        return CKContainer(identifier: id).privateCloudDatabase
    }()
    private static let lastSyncKey = "ck_last_sync_date"
    private static let pendingKey = "ckPendingUploads"
    private static let maxPendingUploads = 100
    public var onError: ((String) -> Void)?

    private var pendingUploads: [BreakSession] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.pendingKey),
                  let sessions = try? JSONDecoder().decode([BreakSession].self, from: data) else { return [] }
            return sessions
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: Self.pendingKey)
        }
    }

    private var cancellables = Set<AnyCancellable>()

    private var isLocalOnlyEnabled: Bool {
        AppSettingsStore.load()?.localOnlyMode ?? false
    }

    public init() {
        // flush pending queue when network becomes available
        NetworkMonitor.shared.$isConnected
            .filter { $0 }
            .sink { [weak self] _ in Task { await self?.flushPending() } }
            .store(in: &cancellables)
    }

    public var lastSyncDate: Date {
        get { (UserDefaults.standard.object(forKey: Self.lastSyncKey) as? Date) ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastSyncKey) }
    }
    public var pendingUploadsCount: Int { pendingUploads.count }

    public func uploadSession(_ session: BreakSession) async {
        guard !isLocalOnlyEnabled else { return }
        guard NetworkMonitor.shared.isConnected else {
            enqueuePendingUpload(session)
            return
        }
        await uploadWithBackoff(session, attempt: 0)
    }

    private func uploadWithBackoff(_ session: BreakSession, attempt: Int) async {
        let recordID = CKRecord.ID(recordName: session.id.uuidString)
        let record = CKRecord(recordType: "BreakSession", recordID: recordID)
        record["id"] = session.id.uuidString as CKRecordValue
        record["type"] = session.type.rawValue as CKRecordValue
        record["scheduledAt"] = session.scheduledAt as CKRecordValue
        if let endedAt = session.endedAt {
            record["endedAt"] = endedAt as CKRecordValue
        } else {
            record["endedAt"] = nil
        }
        record["breakTypeName"] = (session.breakTypeName ?? session.type.rawValue) as CKRecordValue
        record["updatedAt"] = (session.updatedAt ?? Date()) as CKRecordValue
        record["status"] = session.status.rawValue as CKRecordValue
        do {
            try await db.save(record)
        } catch let error as CKError where shouldRetry(error) && attempt < 3 {
            let delay: UInt64 = UInt64(pow(2.0, Double(attempt))) * 1_000_000_000
            try? await Task.sleep(nanoseconds: delay)
            await uploadWithBackoff(session, attempt: attempt + 1)
        } catch {
            handle(error: error)
            enqueuePendingUpload(session)
        }
    }

    private func shouldRetry(_ error: CKError) -> Bool {
        switch error.code {
        case .serverRecordChanged, .networkUnavailable, .networkFailure, .serviceUnavailable: return true
        default: return false
        }
    }

    private func flushPending() async {
        guard !isLocalOnlyEnabled else { return }
        let queue = pendingUploads
        guard !queue.isEmpty else { return }
        pendingUploads = []
        for session in queue { await uploadWithBackoff(session, attempt: 0) }
    }

    private func enqueuePendingUpload(_ session: BreakSession) {
        var queue = pendingUploads
        queue.removeAll { $0.id == session.id }
        queue.append(session)
        if queue.count > Self.maxPendingUploads {
            queue.removeFirst(queue.count - Self.maxPendingUploads)
        }
        pendingUploads = queue
    }

    public func fetchSessions(since date: Date) async -> [BreakSession] {
        guard !isLocalOnlyEnabled else { return [] }
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
        guard !isLocalOnlyEnabled else { return }
        let remote = await fetchSessions(since: lastSyncDate)
        for session in remote {
            await MainActor.run {
                let local = repository.fetchSession(id: session.id)
                repository.save(resolveConflict(local: local, remote: session))
            }
        }
        let end = Date()
        let local = await MainActor.run {
            repository.fetchSessions(from: lastSyncDate, to: end)
        }
        for session in local { await uploadSession(session) }
        lastSyncDate = end
    }

    public func resolveConflict(local: BreakSession?, remote: BreakSession) -> BreakSession {
        guard let local = local else { return remote }
        guard local.id == remote.id else { return remote }
        let localUpdatedAt = local.updatedAt ?? local.scheduledAt
        let remoteUpdatedAt = remote.updatedAt ?? remote.scheduledAt
        if localUpdatedAt > remoteUpdatedAt { return local }
        if remoteUpdatedAt > localUpdatedAt { return remote }
        let rank: (BreakStatus) -> Int = { s in
            switch s {
            case .completed: return 2
            case .snoozed: return 1
            case .skipped, .deferred: return 0
            }
        }
        return rank(local.status) >= rank(remote.status) ? local : remote
    }

    func mapRecord(_ r: CKRecord) -> BreakSession? {
        guard let idStr = r["id"] as? String,
              let id = UUID(uuidString: idStr),
              let typeStr = r["type"] as? String,
              let type = BreakType(rawValue: typeStr),
              let scheduledAt = r["scheduledAt"] as? Date,
              let statusStr = r["status"] as? String,
              let status = BreakStatus(rawValue: statusStr) else { return nil }
        let endedAt = r["endedAt"] as? Date
        let breakTypeName = r["breakTypeName"] as? String
        let updatedAt = r["updatedAt"] as? Date
        return BreakSession(id: id, type: type, scheduledAt: scheduledAt, endedAt: endedAt, status: status, breakTypeName: breakTypeName, updatedAt: updatedAt)
    }

    func handle(error: Error) {
        guard let ckError = error as? CKError else {
            Observability.emit(category: "CloudKitSyncService", message: "error: \(error)")
            logger.error("error: \(String(describing: error), privacy: .public)")
            onError?(error.localizedDescription)
            return
        }
        switch ckError.code {
        case .networkUnavailable:
            Observability.emit(category: "CloudKitSyncService", message: "non-fatal: \(ckError.code)")
            logger.notice("non-fatal: \(String(describing: ckError.code), privacy: .public)")
        case .quotaExceeded:
            Observability.emit(category: "CloudKitSyncService", message: "non-fatal: \(ckError.code)")
            logger.notice("non-fatal: \(String(describing: ckError.code), privacy: .public)")
            onError?(ckError.localizedDescription)
        case .accountTemporarilyUnavailable:
            Observability.emit(category: "CloudKitSyncService", message: "account unavailable: \(ckError.code)")
            NotificationCenter.default.post(name: .cloudKitAccountUnavailable, object: nil)
            onError?(ckError.localizedDescription)
        default:
            Observability.emit(category: "CloudKitSyncService", message: "error: \(ckError)")
            logger.error("error: \(String(describing: ckError), privacy: .public)")
            onError?(ckError.localizedDescription)
        }
    }
}

public extension Notification.Name {
    static let cloudKitAccountUnavailable = Notification.Name("cloudKitAccountUnavailable")
}
