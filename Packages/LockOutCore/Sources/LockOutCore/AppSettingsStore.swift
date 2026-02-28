import Foundation

public enum AppSettingsStore {
    private static let key = "local_app_settings"
    private static let activeRoleKey = "local_active_user_role"

    public static func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
        UserDefaults.standard.set(settings.activeRole.rawValue, forKey: activeRoleKey)
    }

    public static func load() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        guard var settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return nil }
        if let roleRaw = UserDefaults.standard.string(forKey: activeRoleKey),
           let role = UserRole(rawValue: roleRaw) {
            settings.activeRole = role
        }
        return settings
    }
}
