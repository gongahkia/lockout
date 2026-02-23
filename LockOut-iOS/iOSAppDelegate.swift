import UIKit
import SwiftData
import UserNotifications
import BackgroundTasks
import LockOutCore

final class iOSAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let shared = iOSAppDelegate()
    private(set) var modelContainer: ModelContainer!
    private(set) var repository: BreakHistoryRepository!
    private(set) var settingsSync = SettingsSyncService()
    private(set) var cloudSync = CloudKitSyncService()
    var settings: AppSettings = .defaults

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        modelContainer = try! ModelContainer(for: BreakSessionRecord.self)
        repository = BreakHistoryRepository(modelContext: ModelContext(modelContainer))
        settings = settingsSync.pull() ?? .defaults
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor in
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            UserDefaults.standard.set(granted, forKey: "notif_granted")
            registerNotificationCategories()
            if granted { NotificationScheduler.schedule(settings: settings) }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        registerBackgroundTask()
        Task {
            await cloudSync.sync(repository: repository)
            if let remote = settingsSync.pull() { settings = remote }
        }
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler handler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "SNOOZE":
            let snoozeMins = settings.snoozeDurationMinutes
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [response.notification.request.identifier])
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(snoozeMins) * 60, repeats: false)
            let req = UNNotificationRequest(identifier: UUID().uuidString, content: response.notification.request.content, trigger: trigger)
            UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
        case "DONE":
            if let typeStr = response.notification.request.content.userInfo["break_type"] as? String,
               let type = BreakType(rawValue: typeStr) {
                let session = BreakSession(type: type, scheduledAt: Date(), endedAt: Date(), status: .completed)
                repository.save(session)
            }
        default: break
        }
        handler()
    }

    @objc private func appBecameActive() {
        UNUserNotificationCenter.current().setBadgeCount(0, withCompletionHandler: nil)
        let skipped = repository.dailyStats(for: 1).first?.skipped ?? 0
        if skipped > 0 { UNUserNotificationCenter.current().setBadgeCount(skipped, withCompletionHandler: nil) }
    }

    private func registerNotificationCategories() {
        let snooze = UNNotificationAction(identifier: "SNOOZE",
                                          title: "Snooze \(settings.snoozeDurationMinutes) min",
                                          options: [])
        let done = UNNotificationAction(identifier: "DONE", title: "Done", options: .foreground)
        let category = UNNotificationCategory(identifier: "BREAK_CATEGORY",
                                               actions: [snooze, done],
                                               intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Background task
    private static let bgIdentifier = "com.yourapp.lockout.refresh"

    private func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.bgIdentifier, using: nil) { [weak self] task in
            self?.handleBGRefresh(task: task as! BGAppRefreshTask)
        }
        scheduleNextBGRefresh()
    }

    private func handleBGRefresh(task: BGAppRefreshTask) {
        NotificationScheduler.schedule(settings: settings)
        scheduleNextBGRefresh()
        task.setTaskCompleted(success: true)
    }

    private func scheduleNextBGRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: Self.bgIdentifier)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }
}
