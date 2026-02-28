import Foundation

public final class SettingsSyncService {
    private let store = NSUbiquitousKeyValueStore.default
    private static let key = "app_settings"
    private static let activeRoleKey = "active_user_role"
    private var observer: NSObjectProtocol?

    public init() {}

    public func push(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        store.set(data, forKey: Self.key)
        store.set(settings.activeRole.rawValue, forKey: Self.activeRoleKey)
        store.synchronize()
        AppSettingsStore.save(settings)
    }

    public func pull() -> AppSettings? {
        guard let data = store.data(forKey: Self.key) else { return nil }
        guard var settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return nil }
        if let roleRaw = store.string(forKey: Self.activeRoleKey),
           let role = UserRole(rawValue: roleRaw) {
            settings.activeRole = role
        }
        return settings
    }

    public func observeChanges(handler: @escaping (AppSettings) -> Void) {
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
}
