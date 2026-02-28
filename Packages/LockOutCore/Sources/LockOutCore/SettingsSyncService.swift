import Foundation

public final class SettingsSyncService {
    private let store = NSUbiquitousKeyValueStore.default
    private static let key = "app_settings"
    private static let activeRoleKey = "active_user_role"
    private static let pushDebounceSeconds: TimeInterval = 0.4
    private var observer: NSObjectProtocol?
    private var pendingPushWorkItem: DispatchWorkItem?
    var onCloudPush: ((AppSettings) -> Void)?

    private var isLocalOnlyEnabled: Bool {
        AppSettingsStore.load()?.localOnlyMode ?? false
    }

    public init() {}

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

    private func commitCloudPush(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        store.set(data, forKey: Self.key)
        store.set(settings.activeRole.rawValue, forKey: Self.activeRoleKey)
        store.synchronize()
        onCloudPush?(settings)
    }

    public func pull() -> AppSettings? {
        guard !isLocalOnlyEnabled else { return nil }
        guard let data = store.data(forKey: Self.key) else { return nil }
        guard var settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return nil }
        if let roleRaw = store.string(forKey: Self.activeRoleKey),
           let role = UserRole(rawValue: roleRaw) {
            settings.activeRole = role
        }
        return settings
    }

    public func observeChanges(handler: @escaping (AppSettings) -> Void) {
        guard !isLocalOnlyEnabled else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [weak self] _ in
            guard let settings = self?.pull() else { return }
            handler(settings)
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
        merged.localOnlyMode = local.localOnlyMode || remote.localOnlyMode
        merged.isPaused = local.isPaused || remote.isPaused
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
        return merged
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
