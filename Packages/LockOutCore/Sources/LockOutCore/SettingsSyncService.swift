import Foundation

public struct SettingsSyncMetadata: Codable, Equatable, Sendable {
    public var updatedAt: Date
    public var deviceName: String
    public var appVersion: String

    public init(updatedAt: Date = Date(), deviceName: String, appVersion: String) {
        self.updatedAt = updatedAt
        self.deviceName = deviceName
        self.appVersion = appVersion
    }

    public static func currentDevice(now: Date = Date()) -> SettingsSyncMetadata {
        SettingsSyncMetadata(
            updatedAt: now,
            deviceName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            appVersion: AppVersion.current
        )
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

public final class SettingsSyncService {
    private let store = NSUbiquitousKeyValueStore.default
    private static let key = "app_settings"
    private static let pushDebounceSeconds: TimeInterval = 0.4
    private static let lastPushKey = "settings_last_push_date"
    private static let lastPullKey = "settings_last_pull_date"
    private static let lastMetadataKey = "settings_last_sync_metadata"
    private static let lastErrorKey = "settings_last_error"
    private static let kvStoreWarnThreshold = 900_000

    private var observer: NSObjectProtocol?
    private var pendingPushWorkItem: DispatchWorkItem?

    public var onCloudPush: ((AppSettings) -> Void)?
    public var onError: ((String) -> Void)?

    private var isLocalOnlyEnabled: Bool {
        AppSettingsStore.load()?.localOnlyMode ?? false
    }

    public init() {}

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
            return try? JSONDecoder().decode(SettingsSyncMetadata.self, from: data)
        }
        set {
            let data = newValue.flatMap { try? JSONEncoder().encode($0) }
            UserDefaults.standard.set(data, forKey: Self.lastMetadataKey)
        }
    }

    public var lastErrorMessage: String? {
        get { UserDefaults.standard.string(forKey: Self.lastErrorKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastErrorKey) }
    }

    public func push(_ settings: AppSettings) {
        AppSettingsStore.save(settings)
        guard !settings.localOnlyMode else {
            pendingPushWorkItem?.cancel()
            pendingPushWorkItem = nil
            return
        }
        pendingPushWorkItem?.cancel()
        let toPush = settings
        let workItem = DispatchWorkItem { [weak self] in
            self?.commitCloudPush(toPush)
        }
        pendingPushWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pushDebounceSeconds, execute: workItem)
    }

    public func pull() -> AppSettings? {
        guard !isLocalOnlyEnabled else { return nil }
        guard let data = store.data(forKey: Self.key) else { return nil }
        do {
            let envelope = try decodeEnvelope(from: data)
            lastPullDate = Date()
            lastSyncMetadata = envelope.metadata
            lastErrorMessage = nil
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
        return try? decodeEnvelope(from: data)
    }

    public func observeChanges(handler: @escaping (AppSettings) -> Void) {
        guard !isLocalOnlyEnabled else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard let envelope = self.pullEnvelope() else { return }
            self.lastPullDate = Date()
            self.lastSyncMetadata = envelope.metadata
            handler(envelope.settings)
        }
    }

    public func stopObserving() {
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }
    }

    public static func merge(local: AppSettings, remote: AppSettings) -> AppSettings {
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
        store.synchronize()
        lastPushDate = envelope.metadata.updatedAt
        lastSyncMetadata = envelope.metadata
        onCloudPush?(settings)
    }

    private func decodeEnvelope(from data: Data) throws -> SyncedSettingsEnvelope {
        if let envelope = try? JSONDecoder().decode(SyncedSettingsEnvelope.self, from: data) {
            return envelope
        }
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        return SyncedSettingsEnvelope(
            settings: settings,
            metadata: SettingsSyncMetadata(deviceName: "Unknown Device", appVersion: AppVersion.current)
        )
    }

    private static func stricterEnforcementMode(_ lhs: BreakEnforcementMode, _ rhs: BreakEnforcementMode) -> BreakEnforcementMode {
        func rank(_ mode: BreakEnforcementMode) -> Int {
            switch mode {
            case .reminder: return 0
            case .soft_lock: return 1
            case .hard_lock: return 2
            }
        }
        return rank(lhs) >= rank(rhs) ? lhs : rhs
    }
}
