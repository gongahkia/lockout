import AppKit
import Combine
import SwiftData
import LockOutCore
import EventKit

// MARK: - Schema migration stubs
enum LockOutSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [BreakSessionRecord.self] }
}

enum LockOutSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LockOutSchemaV1.self] }
    static var stages: [MigrationStage] { [] } // add lightweight/custom stages here for future schema versions
}

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
    private var idleCheckTimer: Timer?
    private var idlePaused = false
    private var activityMonitor: Any?
    private var calendarTimer: Timer?
    private var calendarPaused = false
    private let ekStore = EKEventStore()
    private var workdayStartTimer: Timer?
    private var workdayEndTimer: Timer?

    private static let lastFireKey = "last_break_fire_date"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        if bundleID == "com.yourapp.lockout.macos" {
            let alert = NSAlert()
            alert.messageText = "Configuration Required"
            alert.informativeText = "Configure Config.xcconfig before distributing LockOut."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0 != NSRunningApplication.current })?
                .activate(options: .activateIgnoringOtherApps)
            NSApp.terminate(nil)
            return
        }
        do {
            modelContainer = try ModelContainer(for: BreakSessionRecord.self, migrationPlan: LockOutSchemaMigrationPlan.self)
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
        menuBarController = MenuBarController(
            scheduler: scheduler,
            repository: repository,
            settingsSync: settingsSync,
            updater: updaterController.updater,
            showBreak: { [weak self] type, duration in self?.overlayController?.show(breakType: type, duration: duration) }
        )
        overlayController = BreakOverlayWindowController(scheduler: scheduler, repository: repository)
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.scheduler.pause() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.scheduler.resume() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.overlayController?.dismiss() }
        if !UserDefaults.standard.bool(forKey: "hasOnboarded") {
            OnboardingWindowController.present()
        }
        requestNotificationPermission()
        startIdleDetection()
        observeFocusMode()
        startCalendarPolling()
        scheduleWorkdayTimers()
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

    private func scheduleDailyTimer(hour: Int, action: @escaping () -> Void) -> Timer {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = hour; comps.minute = 0; comps.second = 0
        var fire = cal.date(from: comps) ?? Date()
        if fire <= Date() { fire = cal.date(byAdding: .day, value: 1, to: fire) ?? fire }
        return Timer.scheduledTimer(withTimeInterval: fire.timeIntervalSinceNow, repeats: false) { _ in
            action()
            // reschedule for next day
            _ = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { _ in action() }
        }
    }

    private func scheduleWorkdayTimers() {
        workdayStartTimer?.invalidate()
        workdayEndTimer?.invalidate()
        if let startHour = scheduler.currentSettings.workdayStartHour {
            workdayStartTimer = scheduleDailyTimer(hour: startHour) { [weak self] in self?.scheduler.resume() }
        }
        if let endHour = scheduler.currentSettings.workdayEndHour {
            workdayEndTimer = scheduleDailyTimer(hour: endHour) { [weak self] in self?.scheduler.pause() }
        }
    }

    private func startCalendarPolling() {
        guard scheduler.currentSettings.pauseDuringCalendarEvents else { return }
        ekStore.requestFullAccessToEvents { [weak self] granted, _ in
            guard granted, let self else { return }
            self.calendarTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                self?.checkCalendarEvents()
            }
        }
    }

    private func checkCalendarEvents() {
        guard scheduler.currentSettings.pauseDuringCalendarEvents else { return }
        let now = Date()
        let cals = ekStore.calendars(for: .event)
        let pred = ekStore.predicateForEvents(withStart: now.addingTimeInterval(-1), end: now.addingTimeInterval(1), calendars: cals)
        let active = ekStore.events(matching: pred).contains { $0.startDate <= now && $0.endDate >= now }
        if active && !calendarPaused {
            calendarPaused = true
            scheduler.pause()
        } else if !active && calendarPaused {
            calendarPaused = false
            scheduler.resume()
        }
    }

    private func observeFocusMode() {
        let nc = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(nc, Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let ptr = observer else { return }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
                guard delegate.scheduler.currentSettings.pauseDuringFocus else { return }
                // Toggle pause based on DND; presence of notification means state changed.
                // Re-check current DND state via UserNotifications isn't directly available;
                // use a heuristic: toggle opposite of current pause state.
                if delegate.scheduler.currentSettings.isPaused { delegate.scheduler.resume() }
                else { delegate.scheduler.pause() }
            },
            "com.apple.donotdisturb.state.changed" as CFString, nil, .deliverImmediately)
    }

    private func startIdleDetection() {
        idleCheckTimer?.invalidate()
        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            let threshold = Double(scheduler.currentSettings.idleThresholdMinutes) * 60
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            if idle >= threshold && !idlePaused {
                idlePaused = true
                scheduler.pause()
                activityMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .keyDown]) { [weak self] _ in
                    guard let self, idlePaused else { return }
                    idlePaused = false
                    scheduler.resume()
                    if let m = activityMonitor { NSEvent.removeMonitor(m); activityMonitor = nil }
                }
            }
        }
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
