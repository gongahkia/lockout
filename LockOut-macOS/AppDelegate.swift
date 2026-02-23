import AppKit
import Combine
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
    private var cancellables = Set<AnyCancellable>()

    private static let lastFireKey = "last_break_fire_date"

    func applicationDidFinishLaunching(_ notification: Notification) {
        modelContainer = try! ModelContainer(for: BreakSessionRecord.self)
        repository = BreakHistoryRepository(modelContext: ModelContext(modelContainer))
        settingsSync = SettingsSyncService()
        cloudSync = CloudKitSyncService()
        let settings = settingsSync.pull() ?? AppSettingsStore.load() ?? .defaults
        scheduler = BreakScheduler(settings: settings)
        repository.pruneOldRecords(retentionDays: settings.historyRetentionDays) // clean stale on launch
        applyLaunchOffset(settings: settings)
        settingsSync.observeChanges { [weak self] remote in
            self?.scheduler.reschedule(with: remote)
        }
        scheduler.$currentSettings.dropFirst().sink { AppSettingsStore.save($0) }.store(in: &cancellables)
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

    private func applyLaunchOffset(settings: AppSettings) {
        guard let last = UserDefaults.standard.object(forKey: Self.lastFireKey) as? Date else {
            scheduler.start(settings: settings)
            return
        }
        let elapsed = Date().timeIntervalSince(last)
        scheduler.start(settings: settings, offsetSeconds: elapsed)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
