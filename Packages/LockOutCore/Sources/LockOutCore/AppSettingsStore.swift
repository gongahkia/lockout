import Foundation

public enum AppSettingsStore {
    private static let key = "local_app_settings"
    private static let activeRoleKey = "local_active_user_role"

    public static func save(_ settings: AppSettings) {
        do { // #10: log errors instead of silent return
            let data = try JSONEncoder().encode(settings)
            UserDefaults.standard.set(data, forKey: key)
            UserDefaults.standard.set(settings.activeRole.rawValue, forKey: activeRoleKey)
        } catch {
            Observability.emit(category: "AppSettingsStore", message: "save encode failed: \(error)", level: .error)
        }
    }

    public static func load() -> AppSettings? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            var settings = try JSONDecoder().decode(AppSettings.self, from: data)
            if let roleRaw = UserDefaults.standard.string(forKey: activeRoleKey),
               let role = UserRole(rawValue: roleRaw) {
                settings.activeRole = role
            }
            return settings
        } catch { // #10: log decode failures
            Observability.emit(category: "AppSettingsStore", message: "load decode failed: \(error)", level: .error)
            return nil
        }
    }
}
