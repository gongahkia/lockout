import Foundation

public struct SettingsSyncMetadata: Codable, Equatable, Sendable {
    public var deviceID: String
    public var updatedAt: Date
    public var deviceName: String
    public var appVersion: String

    public init(deviceID: String = SettingsSyncService.currentDeviceID(), updatedAt: Date = Date(), deviceName: String, appVersion: String) {
        self.deviceID = deviceID
        self.updatedAt = updatedAt
        self.deviceName = deviceName
        self.appVersion = appVersion
    }

    public static func currentDevice(now: Date = Date()) -> SettingsSyncMetadata {
        SettingsSyncMetadata(
            deviceID: SettingsSyncService.currentDeviceID(),
            updatedAt: now,
            deviceName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            appVersion: AppVersion.current
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? SettingsSyncService.currentDeviceID()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
            ?? Host.current().localizedName
            ?? ProcessInfo.processInfo.hostName
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? AppVersion.current
    }

    private enum CodingKeys: String, CodingKey {
        case deviceID
        case updatedAt
        case deviceName
        case appVersion
    }
}

public struct SyncedSettingsEnvelope: Codable, Equatable, Sendable {
    public var settings: AppSettings
    public var metadata: SettingsSyncMetadata

    public init(settings: AppSettings, metadata: SettingsSyncMetadata) {
        self.settings = settings
        self.metadata = metadata
    }
}

@MainActor
public final class SettingsSyncService {
    private let store = NSUbiquitousKeyValueStore.default
    nonisolated private static let key = "app_settings"
    nonisolated private static let pushDebounceDuration: Duration = .milliseconds(400)
    nonisolated private static let lastPushKey = "settings_last_push_date"
    nonisolated private static let lastPullKey = "settings_last_pull_date"
    nonisolated private static let lastMetadataKey = "settings_last_sync_metadata"
    nonisolated private static let lastErrorKey = "settings_last_error"
    nonisolated private static let deviceRegistryKey = "settings_sync_device_registry"
    nonisolated private static let deviceIDKey = "settings_sync_current_device_id"
    nonisolated private static let kvStoreWarnThreshold = 900_000

    private var observer: NSObjectProtocol?
    private var pendingPushTask: Task<Void, Never>?
    private var externalChangeHandler: ((AppSettings) -> Void)?

    public var onCloudPush: ((AppSettings) -> Void)?
    public var onError: ((String) -> Void)?

    private var isLocalOnlyEnabled: Bool {
        AppSettingsStore.load()?.localOnlyMode ?? false
    }

    public init() {}

    nonisolated public static func currentDeviceID() -> String {
        if let existing = UserDefaults.standard.string(forKey: Self.deviceIDKey) {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: Self.deviceIDKey)
        return created
    }

    public var lastPushDate: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastPushKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastPushKey) }
    }

    public var lastPullDate: Date? {
        get { UserDefaults.standard.object(forKey: Self.lastPullKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastPullKey) }
    }

    public var lastSyncMetadata: SettingsSyncMetadata? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.lastMetadataKey) else { return nil }
            return decode(SettingsSyncMetadata.self, from: data, context: "lastSyncMetadata")
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: Self.lastMetadataKey)
                return
            }
            let data = encode(newValue, context: "lastSyncMetadata")
            UserDefaults.standard.set(data, forKey: Self.lastMetadataKey)
        }
    }

    public var lastErrorMessage: String? {
        get { UserDefaults.standard.string(forKey: Self.lastErrorKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastErrorKey) }
    }

    public var deviceRegistry: [SyncDeviceRecord] {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.deviceRegistryKey),
                  let records = decode([SyncDeviceRecord].self, from: data, context: "deviceRegistry") else { return [] }
            return records.sorted { $0.lastSeenAt > $1.lastSeenAt }
        }
        set {
            let sorted = newValue.sorted { $0.lastSeenAt > $1.lastSeenAt }
            guard let encoded = encode(sorted, context: "deviceRegistry") else { return }
            UserDefaults.standard.set(encoded, forKey: Self.deviceRegistryKey)
        }
    }

    public var currentDeviceRecord: SyncDeviceRecord {
        deviceRegistry.first(where: { $0.deviceID == Self.currentDeviceID() })
            ?? SyncDeviceRecord(
                deviceID: Self.currentDeviceID(),
                deviceName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
                appVersion: AppVersion.current
            )
    }

    public func push(_ settings: AppSettings) {
        AppSettingsStore.save(settings)
        guard !settings.localOnlyMode else {
            pendingPushTask?.cancel()
            pendingPushTask = nil
            return
        }
        pendingPushTask?.cancel()
        let toPush = settings
        pendingPushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.pushDebounceDuration)
            guard !Task.isCancelled else { return }
            self?.commitCloudPush(toPush)
        }
    }

    public func pull() -> AppSettings? {
        guard !isLocalOnlyEnabled else { return nil }
        guard let data = store.data(forKey: Self.key) else { return nil }
        do {
            let envelope = try decodeEnvelope(from: data)
            lastPullDate = Date()
            lastSyncMetadata = envelope.metadata
            lastErrorMessage = nil
            updateDeviceRegistry(from: envelope.metadata, wroteSettings: true)
            return envelope.settings
        } catch {
            Observability.emit(category: "SettingsSyncService", message: "pull decode failed: \(error)", level: .error)
            lastErrorMessage = error.localizedDescription
            onError?(error.localizedDescription)
            return nil
        }
    }

    public func pullEnvelope() -> SyncedSettingsEnvelope? {
        guard !isLocalOnlyEnabled else { return nil }
        guard let data = store.data(forKey: Self.key) else { return nil }
        do {
            let envelope = try decodeEnvelope(from: data)
            updateDeviceRegistry(from: envelope.metadata, wroteSettings: true)
            return envelope
        } catch {
            Observability.emit(category: "SettingsSyncService", message: "pullEnvelope decode failed: \(error)", level: .error)
            return nil
        }
    }

    public func observeChanges(handler: @escaping (AppSettings) -> Void) {
        guard !isLocalOnlyEnabled else { return }
        externalChangeHandler = handler
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleExternalStoreChange()
            }
        }
    }

    public func stopObserving() {
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }
        externalChangeHandler = nil
    }

    nonisolated public static func merge(local: AppSettings, remote: AppSettings) -> AppSettings {
        var merged = remote
        merged.localOnlyMode = local.localOnlyMode
        merged.isPaused = local.isPaused
        merged.pauseDuringFocus = local.pauseDuringFocus || remote.pauseDuringFocus
        merged.pauseDuringCalendarEvents = local.pauseDuringCalendarEvents || remote.pauseDuringCalendarEvents
        merged.breakEnforcementMode = stricterEnforcementMode(local.breakEnforcementMode, remote.breakEnforcementMode)
        merged.blockedBundleIDs = Array(Set(local.blockedBundleIDs).union(remote.blockedBundleIDs)).sorted()
        if merged.customBreakTypes.isEmpty {
            merged.customBreakTypes = local.customBreakTypes
        }
        if merged.rolePolicies.isEmpty {
            merged.rolePolicies = local.rolePolicies
        }
        if merged.profiles.isEmpty {
            merged.profiles = local.profiles
        }
        return merged
    }

    public func forcePush(_ settings: AppSettings) {
        guard !settings.localOnlyMode else { return }
        AppSettingsStore.save(settings)
        commitCloudPush(settings)
    }

    public func forcePull() -> AppSettings? {
        guard let envelope = pullEnvelope() else { return nil }
        AppSettingsStore.save(envelope.settings)
        lastPullDate = Date()
        lastSyncMetadata = envelope.metadata
        updateDeviceRegistry(from: envelope.metadata, wroteSettings: true)
        return envelope.settings
    }

    public func noteHistoryUpload(at date: Date = Date()) {
        updateCurrentDeviceRecord { record in
            record.lastSeenAt = date
            record.lastHistoryUploadAt = date
        }
    }

    private func commitCloudPush(_ settings: AppSettings) {
        let envelope = SyncedSettingsEnvelope(settings: settings, metadata: .currentDevice())
        let data: Data
        do {
            data = try JSONEncoder().encode(envelope)
        } catch {
            Observability.emit(category: "SettingsSyncService", message: "encode failed: \(error)", level: .error)
            lastErrorMessage = error.localizedDescription
            onError?(error.localizedDescription)
            return
        }
        if data.count > Self.kvStoreWarnThreshold {
            let message = "iCloud KVStore payload \(data.count) bytes approaching 1MB limit"
            Observability.emit(category: "SettingsSyncService", message: message, level: .warn)
            lastErrorMessage = message
        } else {
            lastErrorMessage = nil
        }
        store.set(data, forKey: Self.key)
        if !store.synchronize() {
            Observability.emit(category: "SettingsSyncService", message: "iCloud key-value synchronize returned false", level: .warn)
        }
        lastPushDate = envelope.metadata.updatedAt
        lastSyncMetadata = envelope.metadata
        updateDeviceRegistry(from: envelope.metadata, wroteSettings: true)
        onCloudPush?(settings)
    }

    private func decodeEnvelope(from data: Data) throws -> SyncedSettingsEnvelope {
        do {
            let envelope = try JSONDecoder().decode(SyncedSettingsEnvelope.self, from: data)
            return envelope
        } catch {
            Observability.emit(category: "SettingsSyncService", message: "envelope decode failed, attempting legacy format: \(error)", level: .warn)
        }
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        return SyncedSettingsEnvelope(
            settings: settings,
            metadata: SettingsSyncMetadata(deviceName: "Unknown Device", appVersion: AppVersion.current)
        )
    }

    private func handleExternalStoreChange() {
        guard let envelope = pullEnvelope() else { return }
        lastPullDate = Date()
        lastSyncMetadata = envelope.metadata
        updateDeviceRegistry(from: envelope.metadata, wroteSettings: true)
        externalChangeHandler?(envelope.settings)
    }

    private func updateDeviceRegistry(from metadata: SettingsSyncMetadata, wroteSettings: Bool) {
        let now = Date()
        if metadata.deviceID == Self.currentDeviceID() {
            updateCurrentDeviceRecord { record in
                record.deviceName = metadata.deviceName
                record.appVersion = metadata.appVersion
                record.lastSeenAt = now
                if wroteSettings {
                    record.lastSettingsWriteAt = metadata.updatedAt
                }
            }
            return
        }
        var registry = deviceRegistry
        if let index = registry.firstIndex(where: { $0.deviceID == metadata.deviceID }) {
            registry[index].deviceName = metadata.deviceName
            registry[index].appVersion = metadata.appVersion
            registry[index].lastSeenAt = now
            if wroteSettings {
                registry[index].lastSettingsWriteAt = metadata.updatedAt
            }
        } else {
            registry.append(
                SyncDeviceRecord(
                    deviceID: metadata.deviceID,
                    deviceName: metadata.deviceName,
                    lastSeenAt: now,
                    lastSettingsWriteAt: wroteSettings ? metadata.updatedAt : nil,
                    appVersion: metadata.appVersion
                )
            )
        }
        deviceRegistry = registry
    }

    private func updateCurrentDeviceRecord(_ mutate: (inout SyncDeviceRecord) -> Void) {
        var registry = deviceRegistry
        if let index = registry.firstIndex(where: { $0.deviceID == Self.currentDeviceID() }) {
            var record = registry[index]
            mutate(&record)
            registry[index] = record
        } else {
            var record = SyncDeviceRecord(
                deviceID: Self.currentDeviceID(),
                deviceName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
                appVersion: AppVersion.current
            )
            mutate(&record)
            registry.append(record)
        }
        deviceRegistry = registry
    }

    nonisolated private static func stricterEnforcementMode(_ lhs: BreakEnforcementMode, _ rhs: BreakEnforcementMode) -> BreakEnforcementMode {
        func rank(_ mode: BreakEnforcementMode) -> Int {
            switch mode {
            case .reminder: return 0
            case .softLock: return 1
            case .hardLock: return 2
            }
        }
        return rank(lhs) >= rank(rhs) ? lhs : rhs
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data, context: String) -> Value? {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Observability.emit(category: "SettingsSyncService", message: "\(context) decode failed: \(error)", level: .error)
            return nil
        }
    }

    private func encode<Value: Encodable>(_ value: Value, context: String) -> Data? {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            Observability.emit(category: "SettingsSyncService", message: "\(context) encode failed: \(error)", level: .error)
            return nil
        }
    }
}
