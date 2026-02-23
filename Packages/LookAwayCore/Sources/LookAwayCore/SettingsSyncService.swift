import Foundation

public final class SettingsSyncService {
    private let store = NSUbiquitousKeyValueStore.default
    private static let key = "app_settings"
    private var observer: NSObjectProtocol?

    public init() {}

    public func push(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        store.set(data, forKey: Self.key)
        store.synchronize()
    }

    public func pull() -> AppSettings? {
        guard let data = store.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
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
