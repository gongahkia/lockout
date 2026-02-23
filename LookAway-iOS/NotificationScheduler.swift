import UserNotifications
import LookAwayCore

enum NotificationScheduler {
    static func schedule(settings: AppSettings) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let configs: [(BreakType, BreakConfig, String, String)] = [
            (.eye, settings.eyeConfig, "Eye Break", "Look at something 20 feet away for 20 seconds"),
            (.micro, settings.microConfig, "Micro Break", "Step away and relax for a moment"),
            (.long, settings.longConfig, "Long Break", "Take a full break and breathe deeply"),
        ]
        for (type, config, title, body) in configs where config.isEnabled {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            content.categoryIdentifier = "BREAK_CATEGORY"
            content.userInfo = ["break_type": type.rawValue]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(config.intervalMinutes) * 60, repeats: true)
            let req = UNNotificationRequest(identifier: "break_\(type.rawValue)", content: content, trigger: trigger)
            center.add(req, withCompletionHandler: nil)
        }
    }
}
