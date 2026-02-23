import AppKit
import SwiftData
import LockOutCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()
    private(set) var scheduler: BreakScheduler!
    private(set) var repository: BreakHistoryRepository!
    private(set) var settingsSync: SettingsSyncService!
    private(set) var cloudSync: CloudKitSyncService!
    private var modelContainer: ModelContainer!
    var menuBarController: MenuBarController?
    var overlayController: BreakOverlayWindowController?

    private static let lastFireKey = "last_break_fire_date"

    func applicationDidFinishLaunching(_ notification: Notification) {
        modelContainer = try! ModelContainer(for: BreakSessionRecord.self)
        repository = BreakHistoryRepository(modelContext: ModelContext(modelContainer))
        settingsSync = SettingsSyncService()
        cloudSync = CloudKitSyncService()
        let settings = settingsSync.pull() ?? .defaults
        scheduler = BreakScheduler(settings: settings)
        repository.pruneOldRecords(retentionDays: settings.historyRetentionDays) // clean stale on launch
        let offsetSettings = applyLaunchOffset(settings: settings)
        scheduler.start(settings: offsetSettings)
        settingsSync.observeChanges { [weak self] remote in
            self?.scheduler.reschedule(with: remote)
        }
        menuBarController = MenuBarController()
        overlayController = BreakOverlayWindowController()
        if !UserDefaults.standard.bool(forKey: "hasOnboarded") {
            OnboardingWindowController.present()
        }
        requestNotificationPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.set(Date(), forKey: Self.lastFireKey)
    }

    private func applyLaunchOffset(settings: AppSettings) -> AppSettings {
        guard let last = UserDefaults.standard.object(forKey: Self.lastFireKey) as? Date else { return settings }
        let elapsed = Date().timeIntervalSince(last)
        var adjusted = settings
        let configs: [(BreakType, BreakConfig)] = [
            (.eye, settings.eyeConfig), (.micro, settings.microConfig), (.long, settings.longConfig)
        ]
        for (_, config) in configs where config.isEnabled {
            let interval = Double(config.intervalMinutes) * 60
            if elapsed < interval { return adjusted } // at least one break not yet due — keep as-is
        }
        return adjusted
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
