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
    private(set) var updaterController: UpdaterController!
    @Published var syncError: String?
    private var modelContainer: ModelContainer!
    var menuBarController: MenuBarController?
    var overlayController: BreakOverlayWindowController?
    private var cancellables = Set<AnyCancellable>()

    private static let lastFireKey = "last_break_fire_date"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0 != NSRunningApplication.current })?
                .activate(options: .activateIgnoringOtherApps)
            NSApp.terminate(nil)
            return
        }
        do {
            modelContainer = try ModelContainer(for: BreakSessionRecord.self)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Database Error"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        repository = BreakHistoryRepository(modelContext: ModelContext(modelContainer))
        settingsSync = SettingsSyncService()
        cloudSync = CloudKitSyncService()
        updaterController = UpdaterController()
        cloudSync.onError = { [weak self] msg in DispatchQueue.main.async { self?.syncError = msg } }
        let settings = settingsSync.pull() ?? AppSettingsStore.load() ?? .defaults
        scheduler = BreakScheduler(settings: settings)
        let retentionDays = settings.historyRetentionDays
        let repo = repository!
        Task.detached { repo.pruneOldRecords(retentionDays: retentionDays) }
        applyLaunchOffset(settings: settings)
        settingsSync.observeChanges { [weak self] remote in
            self?.scheduler.reschedule(with: remote)
        }
        scheduler.$currentSettings.dropFirst().sink { AppSettingsStore.save($0) }.store(in: &cancellables)
        menuBarController = MenuBarController()
        overlayController = BreakOverlayWindowController()
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.scheduler.pause() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.scheduler.resume() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.overlayController?.dismiss() }
        if !UserDefaults.standard.bool(forKey: "hasOnboarded") {
            OnboardingWindowController.present()
        }
        requestNotificationPermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.set(Date(), forKey: Self.lastFireKey)
        settingsSync.stopObserving()
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

    static func scheduleNotification(_ request: UNNotificationRequest) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            UNUserNotificationCenter.current().add(request) { err in
                if let err { fputs("[UNNotif] \(err)\n", stderr) }
            }
        }
    }
}
