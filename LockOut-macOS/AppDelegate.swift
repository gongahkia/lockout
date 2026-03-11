import AppKit
import ApplicationServices
import Combine
import EventKit
import LockOutCore
import SwiftData
@preconcurrency import UserNotifications
import os

enum LockOutSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [BreakSessionRecord.self] }
}

enum LockOutSchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LockOutSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.lockout", category: "AppDelegate")
    private static let lastFireKey = "last_break_fire_date"

    private(set) var scheduler: BreakScheduler!
    private(set) var repository: BreakHistoryRepository!
    private(set) var settingsSync: SettingsSyncService!
    private(set) var cloudSync: CloudKitSyncService!
    private(set) var updaterController: UpdaterController!

    @Published var syncError: String?
    @Published private(set) var managedSettings: ManagedSettingsSnapshot?

    private var modelContainer: ModelContainer!
    var menuBarController: MenuBarController?
    var overlayController: BreakOverlayWindowController?

    private var cancellables = Set<AnyCancellable>()
    private var idleCheckTimer: Timer?
    private var deferredRetryTimer: Timer?
    private var idlePaused = false
    private var activityMonitor: Any?
    private var calendarTimer: Timer?
    private var calendarPaused = false
    private let ekStore = EKEventStore()
    private var workdayStartTimer: Timer?
    private var workdayEndTimer: Timer?
    private var weeklyNotifTimer: Timer?
    private var eventTap: CFMachPort?
    private var previousSettings: AppSettings?
    private var lastKnownFocusModeEnabled: Bool?
    private var isNormalizingSettings = false
    private var isUITesting: Bool { CommandLine.arguments.contains("--uitesting") }
    private var shouldResetOnboardingForUITests: Bool { CommandLine.arguments.contains("--reset-onboarding") }

    func applicationDidFinishLaunching(_ notification: Notification) {
        CrashReporter.install()
        configureLogging()
        configureUITestingDefaultsIfNeeded()

        let bundleID = Bundle.main.bundleIdentifier ?? ""
        if bundleID == "com.yourapp.lockout.macos" {
            terminateForConfigurationIssue(message: "Configure Config.xcconfig before distributing LockOut.")
            return
        }
        if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).count > 1 {
            FileLogger.shared.log(.warn, category: "AppDelegate", "terminated: another instance already running")
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0 != NSRunningApplication.current })?
                .activate(options: [])
            NSApp.terminate(nil)
            return
        }

        guard initializePersistence() else { return }

        repository = BreakHistoryRepository(modelContext: ModelContext(modelContainer))
        settingsSync = SettingsSyncService()
        cloudSync = CloudKitSyncService()
        updaterController = UpdaterController()
        settingsSync.onError = { [weak self] msg in DispatchQueue.main.async { self?.syncError = msg } }
        cloudSync.onError = { [weak self] msg in DispatchQueue.main.async { self?.syncError = msg } }

        refreshManagedSettings()
        let localSettings = AppSettingsStore.load()
        let remoteSettings = localSettings?.localOnlyMode == true ? nil : settingsSync.pull()
        let resolvedSettings = ManagedSettingsResolver.resolve(local: localSettings, remote: remoteSettings, managed: managedSettings)

        scheduler = BreakScheduler(settings: resolvedSettings)
        previousSettings = resolvedSettings
        overlayController = BreakOverlayWindowController(scheduler: scheduler, repository: repository, cloudSync: cloudSync)

        let retentionDays = resolvedSettings.historyRetentionDays
        let repo = repository!
        Task { @MainActor in repo.pruneOldRecords(retentionDays: retentionDays) }

        applyLaunchOffset(settings: resolvedSettings)
        configureSettingsObservation(for: resolvedSettings)
        registerSchedulerBindings()
        registerWorkspaceObservers()
        registerGlobalSnoozeHotkey(resolvedSettings.globalSnoozeHotkey)

        menuBarController = MenuBarController(
            scheduler: scheduler,
            repository: repository,
            cloudSync: cloudSync,
            settingsSync: settingsSync,
            updater: updaterController.updater,
            showBreak: { [weak self] type, duration in
                self?.presentAdHocBreak(type: type, duration: duration)
            }
        )

        scheduler.onBreakTriggered = { [weak self] customType, context in
            self?.attemptBreakPresentation(customType: customType, context: context)
        }

        if !UserDefaults.standard.bool(forKey: "hasOnboarded") {
            OnboardingWindowController.present(scheduler: scheduler)
        } else if !UserDefaults.standard.bool(forKey: "hasSeenMainWindow") {
            UserDefaults.standard.set(true, forKey: "hasSeenMainWindow")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        if !isUITesting {
            requestNotificationPermission()
        }
        startIdleDetection()
        observeFocusMode()
        if resolvedSettings.pauseDuringCalendarEvents { startCalendarPolling() }
        scheduleWorkdayTimers()
        scheduleWeeklyComplianceNotification()
        refreshDeferredRetryTimer()
        NotificationCenter.default.post(name: .appDidFinishSetup, object: nil)
        FileLogger.shared.log(.info, category: "AppDelegate", "applicationDidFinishLaunching completed")
    }

    func applicationWillTerminate(_ notification: Notification) {
        FileLogger.shared.log(.info, category: "AppDelegate", "applicationWillTerminate")
        UserDefaults.standard.set(Date(), forKey: Self.lastFireKey)
        settingsSync.stopObserving()
        deferredRetryTimer?.invalidate()
    }

    func refreshManagedSettings() {
        managedSettings = ManagedSettingsResolver.load()
    }

    func applyManagedSettings(to settings: AppSettings) -> AppSettings {
        ManagedSettingsResolver.apply(managedSettings, to: settings)
    }

    func registerGlobalSnoozeHotkey(_ hotkey: HotkeyDescriptor?) {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        guard hotkey != nil else { return }
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
            FileLogger.shared.log(.warn, category: "AppDelegate", "Accessibility permission not granted; global hotkey disabled")
            return
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, _, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                guard let hotkey = delegate.scheduler.currentSettings.globalSnoozeHotkey else {
                    return Unmanaged.passUnretained(event)
                }
                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = Int(event.flags.rawValue) & 0x00FF0000
                if keyCode == hotkey.keyCode && flags == (hotkey.modifierFlags & 0x00FF0000) {
                    Task { @MainActor in
                        delegate.scheduler.snooze(repository: delegate.repository, cloudSync: delegate.cloudSync)
                    }
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        if let tap {
            let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            eventTap = tap
        }
    }

    func scheduleWeeklyComplianceNotification() {
        weeklyNotifTimer?.invalidate()
        weeklyNotifTimer = nil
        guard scheduler.currentSettings.weeklyNotificationEnabled else { return }
        let cal = Calendar.current
        var comps = DateComponents()
        comps.weekday = 2
        comps.hour = 9
        comps.minute = 0
        comps.second = 0
        guard let nextMonday = cal.nextDate(after: Date(), matching: comps, matchingPolicy: .nextTime) else { return }
        let interval = nextMonday.timeIntervalSinceNow
        weeklyNotifTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.fireWeeklyComplianceNotification()
                _ = Timer.scheduledTimer(withTimeInterval: 7 * 86400, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.fireWeeklyComplianceNotification()
                    }
                }
            }
        }
    }

    func scheduleBreakReminderNotification(leadSeconds: Double) {
        guard leadSeconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Break coming up"
        content.body = "Your next break starts in \(Int(leadSeconds / 60)) min"
        content.sound = .default
        content.categoryIdentifier = "BREAK_REMINDER"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: leadSeconds, repeats: false)
        let request = UNNotificationRequest(identifier: "break_reminder", content: content, trigger: trigger)
        Self.scheduleNotification(request)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completion: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch response.actionIdentifier {
            case "START_BREAK":
                if let customType = self.scheduler.currentCustomBreakType {
                    self.scheduler.triggerBreak(customType)
                }
            case "SNOOZE_BREAK":
                let mins = self.scheduler.currentCustomBreakType?.snoozeMinutes ?? self.scheduler.currentSettings.snoozeDurationMinutes
                self.scheduler.snooze(minutes: mins, repository: self.repository, cloudSync: self.cloudSync)
            default:
                break
            }
        }
        completion()
    }

    nonisolated static func scheduleNotification(_ request: UNNotificationRequest) {
        let logger = Self.logger
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else { return }
            UNUserNotificationCenter.current().add(request) { err in
                if let err {
                    logger.error("notification scheduling failed: \(String(describing: err), privacy: .public)")
                }
            }
        }
    }

    static func didWorkdaySettingsChange(previous: AppSettings?, current: AppSettings) -> Bool {
        SettingsChangeDetector.workdayTimersNeedRefresh(previous: previous, current: current)
    }

    static func didCalendarPollingPreferenceChange(previous: AppSettings?, current: AppSettings) -> Bool {
        SettingsChangeDetector.calendarPollingPreferenceChanged(previous: previous, current: current)
    }

    private func configureLogging() {
        let log = FileLogger.shared
        Observability.levelSink = { level, category, message in
            let mapped: FileLogger.Level
            switch level {
            case .debug: mapped = .debug
            case .info: mapped = .info
            case .warn: mapped = .warn
            case .error: mapped = .error
            }
            log.log(mapped, category: category, message)
        }
        log.log(.info, category: "AppDelegate", "applicationDidFinishLaunching started")
        log.log(.info, category: "AppDelegate", "bundle=\(Bundle.main.bundleIdentifier ?? "nil") version=\(AppVersion.current)")
            log.log(.info, category: "AppDelegate", "logFile=\(log.logURL.path)")
    }

    private func configureUITestingDefaultsIfNeeded() {
        guard isUITesting else { return }
        var settings = AppSettings.defaults
        settings.localOnlyMode = true
        AppSettingsStore.save(settings)
        UserDefaults.standard.removeObject(forKey: Self.lastFireKey)
        UserDefaults.standard.set(!shouldResetOnboardingForUITests, forKey: "hasOnboarded")
        UserDefaults.standard.set(false, forKey: "hasSeenMainWindow")
    }

    private func terminateForConfigurationIssue(message: String) {
        let alert = NSAlert()
        alert.messageText = "Configuration Required"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        FileLogger.shared.log(.error, category: "AppDelegate", "terminated: \(message)")
        NSApp.terminate(nil)
    }

    private func initializePersistence() -> Bool {
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        do {
            let config = isUITesting ? ModelConfiguration(isStoredInMemoryOnly: true) : ModelConfiguration()
            modelContainer = try ModelContainer(
                for: BreakSessionRecord.self,
                migrationPlan: LockOutSchemaMigrationPlan.self,
                configurations: config
            )
            return true
        } catch {
            FileLogger.shared.log(.error, category: "AppDelegate", "SwiftData init failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Database Error"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
            return false
        }
    }

    private func configureSettingsObservation(for settings: AppSettings) {
        settingsSync.stopObserving()
        guard !settings.localOnlyMode else { return }
        settingsSync.observeChanges { [weak self] remote in
            guard let self else { return }
            self.refreshManagedSettings()
            let merged = ManagedSettingsResolver.resolve(local: self.scheduler.currentSettings, remote: remote, managed: self.managedSettings)
            let shouldRefreshWeeklyTimer = SettingsChangeDetector.weeklyNotificationPreferenceChanged(previous: self.scheduler.currentSettings, current: merged)
            self.scheduler.reschedule(with: merged)
            if shouldRefreshWeeklyTimer {
                self.scheduleWeeklyComplianceNotification()
            }
            self.syncError = self.settingsSync.lastErrorMessage
        }
    }

    private func registerSchedulerBindings() {
        scheduler.$currentSettings.dropFirst().sink { [weak self] settings in
            guard let self else { return }
            self.refreshManagedSettings()
            if self.isNormalizingSettings {
                self.isNormalizingSettings = false
            }
            let effective = self.applyManagedSettings(to: settings)
            if effective != settings {
                self.isNormalizingSettings = true
                self.scheduler.currentSettings = effective
                return
            }

            self.settingsSync.push(effective)
            if Self.didWorkdaySettingsChange(previous: self.previousSettings, current: effective) {
                self.scheduleWorkdayTimers()
            }
            if Self.didCalendarPollingPreferenceChange(previous: self.previousSettings, current: effective) {
                if effective.pauseDuringCalendarEvents {
                    self.startCalendarPolling()
                } else {
                    self.stopCalendarPolling()
                }
            }
            if self.previousSettings?.localOnlyMode != effective.localOnlyMode {
                self.configureSettingsObservation(for: effective)
            }
            self.previousSettings = effective
            self.registerGlobalSnoozeHotkey(effective.globalSnoozeHotkey)
            self.refreshDeferredRetryTimer()
            self.syncError = self.settingsSync.lastErrorMessage ?? self.syncError
        }.store(in: &cancellables)

        scheduler.$nextBreak.dropFirst().sink { [weak self] nextBreak in
            guard let self else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["break_reminder"])
            guard let nextBreak else { return }
            let lead = Double(self.scheduler.currentSettings.notificationLeadMinutes) * 60
            let interval = nextBreak.fireDate.timeIntervalSinceNow - lead
            if interval > 0 {
                self.scheduleBreakReminderNotification(leadSeconds: interval)
            }
        }.store(in: &cancellables)

        scheduler.$pendingDeferredBreak.dropFirst().sink { [weak self] _ in
            self?.refreshDeferredRetryTimer()
        }.store(in: &cancellables)
    }

    private func registerWorkspaceObservers() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduler.pause(reason: .manual)
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduler.resume(reason: .manual)
                self?.retryPendingDeferredBreak()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.overlayController?.dismiss()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.retryPendingDeferredBreak()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.retryPendingDeferredBreak()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.retryPendingDeferredBreak()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.retryPendingDeferredBreak()
            }
        }
        NotificationCenter.default.addObserver(forName: .streakDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.menuBarController?.updateStreak()
            }
        }
    }

    private func applyLaunchOffset(settings: AppSettings) {
        guard let last = UserDefaults.standard.object(forKey: Self.lastFireKey) as? Date else {
            scheduler.start(settings: settings)
            return
        }
        let elapsed = Date().timeIntervalSince(last)
        scheduler.start(settings: settings, offsetSeconds: elapsed)
    }

    private func scheduleDailyTimer(minutesFromMidnight: Int, action: @escaping @MainActor () -> Void) -> Timer {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: Date())
        comps.hour = minutesFromMidnight / 60
        comps.minute = minutesFromMidnight % 60
        comps.second = 0
        var fire = cal.date(from: comps) ?? Date()
        if fire <= Date() { fire = cal.date(byAdding: .day, value: 1, to: fire) ?? fire }
        return Timer.scheduledTimer(withTimeInterval: fire.timeIntervalSinceNow, repeats: false) { _ in
            Task { @MainActor in
                action()
                _ = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { _ in
                    Task { @MainActor in action() }
                }
            }
        }
    }

    private func fireWeeklyComplianceNotification() {
        let stats = repository.dailyStats(for: 7)
        let rate = Int(ComplianceCalculator.overallRate(stats: stats) * 100)
        let content = UNMutableNotificationContent()
        content.title = "Weekly Compliance Summary"
        content.body = "Last 7 days: \(rate)% compliance"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "weekly_compliance", content: content, trigger: trigger)
        Self.scheduleNotification(request)
    }

    private func scheduleWorkdayTimers() {
        workdayStartTimer?.invalidate()
        workdayEndTimer?.invalidate()
        if let startMins = scheduler.currentSettings.workdayStartMinutes {
            workdayStartTimer = scheduleDailyTimer(minutesFromMidnight: startMins) { [weak self] in
                self?.scheduler.resume(reason: .workday)
            }
        }
        if let endMins = scheduler.currentSettings.workdayEndMinutes {
            workdayEndTimer = scheduleDailyTimer(minutesFromMidnight: endMins) { [weak self] in
                self?.scheduler.pause(reason: .workday)
            }
        }
    }

    private func startCalendarPolling() {
        calendarTimer?.invalidate()
        calendarTimer = nil
        guard scheduler.currentSettings.pauseDuringCalendarEvents else { return }
        ekStore.requestFullAccessToEvents { [weak self] granted, _ in
            guard granted else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.calendarTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.checkCalendarEvents()
                    }
                }
            }
        }
    }

    private func stopCalendarPolling() {
        calendarTimer?.invalidate()
        calendarTimer = nil
        if calendarPaused {
            calendarPaused = false
            scheduler.resume(reason: .calendar)
        }
    }

    private func checkCalendarEvents() {
        guard scheduler.currentSettings.pauseDuringCalendarEvents else { return }
        let now = Date()
        let filterMode = scheduler.currentSettings.calendarFilterMode
        let filteredIDs = Set(scheduler.currentSettings.filteredCalendarIDs)
        var calendars = ekStore.calendars(for: .event)
        if filterMode == .selected && !filteredIDs.isEmpty {
            calendars = calendars.filter { filteredIDs.contains($0.calendarIdentifier) }
        }
        let predicate = ekStore.predicateForEvents(withStart: now.addingTimeInterval(-1), end: now.addingTimeInterval(1), calendars: calendars)
        let events = ekStore.events(matching: predicate).filter { $0.startDate <= now && $0.endDate >= now }
        let active: Bool
        switch filterMode {
        case .busyOnly:
            active = events.contains { $0.availability == .busy || $0.availability == .unavailable }
        case .all, .selected:
            active = !events.isEmpty
        }
        if active && !calendarPaused {
            calendarPaused = true
            scheduler.pause(reason: .calendar)
        } else if !active && calendarPaused {
            calendarPaused = false
            scheduler.resume(reason: .calendar)
        }
    }

    private func observeFocusMode() {
        let nc = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            nc,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let ptr = observer else { return }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(ptr).takeUnretainedValue()
                Task { @MainActor in
                    guard delegate.scheduler.currentSettings.pauseDuringFocus else { return }
                    guard let isEnabled = delegate.readFocusModeEnabled() else { return }
                    let action = SettingsChangeDetector.focusPauseAction(
                        previousFocusEnabled: delegate.lastKnownFocusModeEnabled,
                        currentFocusEnabled: isEnabled,
                        isPaused: delegate.scheduler.isPaused
                    )
                    delegate.lastKnownFocusModeEnabled = isEnabled
                    switch action {
                    case .pause:
                        delegate.scheduler.pause(reason: .focus)
                    case .resume:
                        delegate.scheduler.resume(reason: .focus)
                    case .none:
                        break
                    }
                }
            },
            "com.apple.donotdisturb.state.changed" as CFString,
            nil,
            .deliverImmediately
        )
    }

    private func readFocusModeEnabled() -> Bool? {
        do {
            guard let defaults = UserDefaults(suiteName: "com.apple.ncprefs"),
                  let data = defaults.data(forKey: "dnd_prefs") else {
                return nil
            }
            guard let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let userPref = plist["userPref"] as? [String: Any],
                  let enabled = userPref["enabled"] as? Bool else {
                return nil
            }
            return enabled
        } catch {
            FileLogger.shared.log(.warn, category: "AppDelegate", "Focus Mode detection failed: \(error)")
            return nil
        }
    }

    private func startIdleDetection() {
        idleCheckTimer?.invalidate()
        idleCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleIdleDetectionTick()
            }
        }
    }

    private func handleIdleDetectionTick() {
        let threshold = Double(scheduler.currentSettings.idleThresholdMinutes) * 60
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle >= threshold && !idlePaused {
            idlePaused = true
            scheduler.pause(reason: .idle)
            activityMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .keyDown]) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleIdleActivity()
                }
            }
        }
    }

    private func handleIdleActivity() {
        guard idlePaused else { return }
        idlePaused = false
        scheduler.resume(reason: .idle)
        if let monitor = activityMonitor {
            NSEvent.removeMonitor(monitor)
            activityMonitor = nil
        }
    }

    private func requestNotificationPermission() {
        let startAction = UNNotificationAction(identifier: "START_BREAK", title: "Start Break Now", options: .foreground)
        let snoozeAction = UNNotificationAction(identifier: "SNOOZE_BREAK", title: "Snooze", options: [])
        let category = UNNotificationCategory(identifier: "BREAK_REMINDER", actions: [startAction, snoozeAction], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func presentAdHocBreak(type: BreakType, duration: Int) {
        let context: ScheduledBreakContext
        if let customType = scheduler.currentCustomBreakType {
            context = ScheduledBreakContext(customTypeID: customType.id, scheduledAt: Date())
            attemptBreakPresentation(customType: customType, context: context)
            return
        }
        let fallback = scheduler.currentSettings.customBreakTypes.first(where: \.enabled)
            ?? scheduler.currentSettings.customBreakTypes.first
            ?? AppSettings.defaultCustomBreakTypes[0]
        context = ScheduledBreakContext(customTypeID: fallback.id, scheduledAt: Date())
        attemptBreakPresentation(customType: fallback, context: context)
        _ = type
        _ = duration
    }

    private func attemptBreakPresentation(customType: CustomBreakType, context: ScheduledBreakContext) {
        guard let overlayController else { return }
        let shown = overlayController.show(
            breakType: legacyBreakType(customType),
            duration: customType.durationSeconds,
            minDisplaySeconds: customType.minDisplaySeconds,
            scheduledAt: context.scheduledAt
        )
        if shown {
            scheduler.beginBreakPresentation(context)
        } else {
            scheduler.registerDeferredBreak(context, repository: repository, cloudSync: cloudSync)
        }
        refreshDeferredRetryTimer()
    }

    private func refreshDeferredRetryTimer() {
        deferredRetryTimer?.invalidate()
        deferredRetryTimer = nil
        guard scheduler.pendingDeferredBreak != nil else { return }
        deferredRetryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.retryPendingDeferredBreak()
            }
        }
    }

    @objc private func retryPendingDeferredBreak() {
        guard let context = scheduler.pendingDeferredBreak,
              let customType = scheduler.currentSettings.customBreakTypes.first(where: { $0.id == context.customTypeID }),
              overlayController?.isShowingOverlay == false else { return }
        attemptBreakPresentation(customType: customType, context: context)
    }

    private func legacyBreakType(_ customType: CustomBreakType) -> BreakType {
        let lower = customType.name.lowercased()
        if lower.contains("micro") { return .micro }
        if lower.contains("long") { return .long }
        return .eye
    }
}
