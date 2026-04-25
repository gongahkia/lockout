import AppKit
import ApplicationServices
import Combine
import EventKit
import LockOutCore
import SwiftData
@preconcurrency import UserNotifications
import os

struct ManualDeferredOption: Identifiable {
    let id: String
    let title: String
    let condition: DeferredBreakCondition
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, ObservableObject {
    nonisolated private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.lockout", category: "AppDelegate")
    private static let lastFireKey = "last_break_fire_date"

    private(set) var scheduler = BreakScheduler()
    private(set) var repository: BreakHistoryRepository?
    private(set) var settingsSync = SettingsSyncService()
    private(set) var cloudSync = CloudKitSyncService()
    private(set) var updaterController = UpdaterController()
    private(set) var insightsStore = BreakInsightsStore()

    @Published var syncError: String?
    @Published private(set) var isReadyForUI = false
    @Published private(set) var managedSettings: ManagedSettingsSnapshot?
    @Published private(set) var matchedAutoProfileRule: AutoProfileRule?

    private var modelContainer: ModelContainer?
    var menuBarController: MenuBarController?
    var overlayController: BreakOverlayWindowController?

    private var cancellables = Set<AnyCancellable>()
    private var idleCheckTimer: Timer?
    private var deferredRetryTimer: Timer?
    private var automationTimer: Timer?
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
    private var currentCalendarEventIDs = Set<String>()
    private var currentCalendarEventTitles: [String] = []
    private var currentEffectiveSettingsSource: EffectiveSettingsSource = .local
    private var isNormalizingSettings = false
    private var isEvaluatingAutomaticProfiles = false
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

        guard let modelContainer = initializePersistence() else { return }

        self.modelContainer = modelContainer
        let repository = BreakHistoryRepository(modelContext: ModelContext(modelContainer))
        self.repository = repository
        settingsSync.onError = { [weak self] msg in
            Task { @MainActor in self?.syncError = msg }
        }
        cloudSync.onError = { [weak self] msg in
            Task { @MainActor in self?.syncError = msg }
        }

        refreshManagedSettings()
        let localSettings = AppSettingsStore.load()
        let remoteSettings = localSettings?.localOnlyMode == true ? nil : settingsSync.pull()
        let resolvedSettings = ManagedSettingsResolver.resolve(local: localSettings, remote: remoteSettings, managed: managedSettings)
        currentEffectiveSettingsSource = effectiveSettingsSource(for: resolvedSettings)

        scheduler = BreakScheduler(settings: resolvedSettings)
        previousSettings = resolvedSettings
        overlayController = BreakOverlayWindowController(scheduler: scheduler, repository: repository, cloudSync: cloudSync)
        scheduler.onSessionRecorded = { [weak self] session, metadata in
            guard let self else { return }
            self.insightsStore.saveMetadata(metadata, for: session.id)
            if session.status == .completed {
                var settings = self.scheduler.currentSettings
                settings.onboardingReviewState.completedSessionCount += 1
                self.scheduler.currentSettings = settings
            }
            if !self.scheduler.currentSettings.localOnlyMode {
                self.settingsSync.noteHistoryUpload()
            }
        }

        let retentionDays = resolvedSettings.historyRetentionDays
        Task { @MainActor in repository.pruneOldRecords(retentionDays: retentionDays) }

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
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
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
        scheduleAutomationTimer()
        refreshDeferredRetryTimer()
        evaluateAutoProfileRules()
        refreshDecisionTrace()
        NotificationCenter.default.post(name: .appDidFinishSetup, object: nil)
        isReadyForUI = true
        FileLogger.shared.log(.info, category: "AppDelegate", "applicationDidFinishLaunching completed")
    }

    func applicationWillTerminate(_ notification: Notification) {
        FileLogger.shared.log(.info, category: "AppDelegate", "applicationWillTerminate")
        UserDefaults.standard.set(Date(), forKey: Self.lastFireKey)
        settingsSync.stopObserving()
        deferredRetryTimer?.invalidate()
        automationTimer?.invalidate()
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
                        guard let repository = delegate.repository else { return }
                        delegate.scheduler.snooze(repository: repository, cloudSync: delegate.cloudSync)
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
                guard let repository = self.repository else { return }
                self.scheduler.snooze(minutes: mins, repository: repository, cloudSync: self.cloudSync)
            default:
                break
            }
        }
        completion()
    }

    nonisolated static func scheduleNotification(_ request: UNNotificationRequest) {
        let logger = Self.logger
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                DiagnosticsStore.shared.record(
                    level: .warning,
                    category: "Notifications",
                    message: "notification dropped: authorization status \(settings.authorizationStatus.rawValue)"
                )
                return
            }
            UNUserNotificationCenter.current().add(request) { err in
                if let err {
                    logger.error("notification scheduling failed: \(String(describing: err), privacy: .public)")
                    DiagnosticsStore.shared.record(
                        level: .error,
                        category: "Notifications",
                        message: "notification scheduling failed: \(err.localizedDescription)"
                    )
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
        let diagnostics = DiagnosticsStore.shared
        Observability.levelSink = { level, category, message in
            let mapped: FileLogger.Level
            switch level {
            case .debug: mapped = .debug
            case .info: mapped = .info
            case .warn: mapped = .warn
            case .error: mapped = .error
            }
            diagnostics.record(level: DiagnosticsLevel(from: level), category: category, message: message)
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

    private func initializePersistence() -> ModelContainer? {
        do {
            return try LockOutPersistenceController.makeContainer(isUITesting: isUITesting)
        } catch {
            FileLogger.shared.log(.error, category: "AppDelegate", "SwiftData init failed: \(error)")
            let alert = NSAlert()
            alert.messageText = "Database Error"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
            return nil
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
            self.currentEffectiveSettingsSource = self.effectiveSettingsSource(for: merged)
            self.scheduler.reschedule(with: merged)
            if shouldRefreshWeeklyTimer {
                self.scheduleWeeklyComplianceNotification()
            }
            self.scheduleAutomationTimer()
            self.evaluateAutoProfileRules()
            self.refreshDecisionTrace()
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
            self.currentEffectiveSettingsSource = self.effectiveSettingsSource(for: effective)
            self.previousSettings = effective
            self.registerGlobalSnoozeHotkey(effective.globalSnoozeHotkey)
            self.scheduleAutomationTimer()
            self.evaluateAutoProfileRules()
            self.refreshDeferredRetryTimer()
            self.refreshDecisionTrace()
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
            self?.refreshDecisionTrace()
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
                self?.evaluateAutoProfileRules()
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
                self?.evaluateAutoProfileRules()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.retryPendingDeferredBreak()
                self?.evaluateAutoProfileRules()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.retryPendingDeferredBreak()
                self?.evaluateAutoProfileRules()
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.retryPendingDeferredBreak()
                self?.evaluateAutoProfileRules()
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
        guard let repository else { return }
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
                self?.refreshDecisionTrace()
            }
        }
        if let endMins = scheduler.currentSettings.workdayEndMinutes {
            workdayEndTimer = scheduleDailyTimer(minutesFromMidnight: endMins) { [weak self] in
                self?.scheduler.pause(reason: .workday)
                self?.refreshDecisionTrace()
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
                self.checkCalendarEvents()
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
        currentCalendarEventIDs = []
        currentCalendarEventTitles = []
        if calendarPaused {
            calendarPaused = false
            scheduler.resume(reason: .calendar)
        }
        evaluateAutoProfileRules()
        refreshDecisionTrace()
    }

    private func checkCalendarEvents() {
        guard scheduler.currentSettings.pauseDuringCalendarEvents else { return }
        let now = Date()
        let events = matchingCalendarEvents(at: now)
        currentCalendarEventIDs = Set(events.map(\.eventIdentifier))
        currentCalendarEventTitles = events.map(\.title)
        let active = !events.isEmpty
        if active && !calendarPaused {
            calendarPaused = true
            scheduler.pause(reason: .calendar)
        } else if !active && calendarPaused {
            calendarPaused = false
            scheduler.resume(reason: .calendar)
        }
        retryPendingDeferredBreak()
        evaluateAutoProfileRules()
        refreshDecisionTrace()
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
                    delegate.evaluateAutoProfileRules()
                    delegate.refreshDecisionTrace()
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
            refreshDecisionTrace()
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
        refreshDecisionTrace()
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                FileLogger.shared.log(.error, category: "Notifications", "permission request failed: \(error)")
                DiagnosticsStore.shared.record(
                    level: .error,
                    category: "Notifications",
                    message: "permission request failed: \(error.localizedDescription)"
                )
                return
            }
            FileLogger.shared.log(.info, category: "Notifications", "permission status granted=\(granted)")
            DiagnosticsStore.shared.record(
                level: .info,
                category: "Notifications",
                message: "permission status granted=\(granted)"
            )
        }
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
        guard let overlayController, let repository else { return }
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let isFullscreen = SystemStateService.frontmostAppIsFullscreen()
        let enrichedContext = context.withInsightMetadata(
            BreakInsightMetadata(
                activeProfileID: scheduler.currentSettings.activeProfileId,
                activeProfileName: activeProfileName(),
                calendarOverlap: !currentCalendarEventIDs.isEmpty,
                fullscreenOverlap: isFullscreen,
                frontmostBundleID: frontmostBundleID
            )
        )
        let result = overlayController.show(
            breakType: legacyBreakType(customType),
            duration: customType.durationSeconds,
            minDisplaySeconds: customType.minDisplaySeconds,
            scheduledAt: enrichedContext.scheduledAt
        )
        switch result {
        case .shown:
            scheduler.beginBreakPresentation(enrichedContext)
        case let .deferred(condition):
            scheduler.registerDeferredBreak(enrichedContext, condition: condition, repository: repository, cloudSync: cloudSync)
        }
        refreshDeferredRetryTimer()
        refreshDecisionTrace()
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
        guard let pending = scheduler.pendingDeferredBreak,
              let customType = scheduler.currentSettings.customBreakTypes.first(where: { $0.id == pending.customTypeID }),
              overlayController?.isShowingOverlay == false else { return }
        let evaluationContext = DeferredBreakEvaluationContext(
            now: Date(),
            activeMeetingEventIDs: currentCalendarEventIDs,
            isFullscreen: SystemStateService.frontmostAppIsFullscreen(),
            frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        )
        guard pending.isReadyForRetry(evaluationContext: evaluationContext) else {
            refreshDecisionTrace()
            return
        }
        attemptBreakPresentation(customType: customType, context: pending.context)
    }

    func availableDeferredOptions() -> [ManualDeferredOption] {
        var options: [ManualDeferredOption] = [
            ManualDeferredOption(id: "minutes-10", title: "In 10 minutes", condition: .minutes(10)),
        ]
        if let eventID = currentCalendarEventIDs.first {
            options.append(
                ManualDeferredOption(
                    id: "meeting",
                    title: "Until this meeting ends",
                    condition: .untilMeetingEnds(eventID: eventID)
                )
            )
        }
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, !bundleID.isEmpty {
            options.append(
                ManualDeferredOption(
                    id: "app",
                    title: "Until I leave this app",
                    condition: .untilAppChanges(bundleID: bundleID)
                )
            )
        }
        return options
    }

    func deferCurrentBreak(_ condition: DeferredBreakCondition) {
        guard let context = scheduler.breakContextForPresentation(), let repository else { return }
        scheduler.registerDeferredBreak(context, condition: condition, repository: repository, cloudSync: cloudSync)
        overlayController?.dismiss()
        refreshDeferredRetryTimer()
        refreshDecisionTrace()
    }

    func returnToAutomaticProfileMode() {
        var settings = scheduler.currentSettings
        settings.profileActivationMode = .automatic
        scheduler.currentSettings = settings
        evaluateAutoProfileRules()
        refreshDecisionTrace()
    }

    func forcePushSettings() {
        let effective = applyManagedSettings(to: scheduler.currentSettings)
        currentEffectiveSettingsSource = effectiveSettingsSource(for: effective)
        settingsSync.forcePush(effective)
        refreshDecisionTrace()
    }

    func forcePullSettings() {
        refreshManagedSettings()
        guard let pulled = settingsSync.forcePull() else { return }
        let resolved = ManagedSettingsResolver.resolve(local: scheduler.currentSettings, remote: pulled, managed: managedSettings)
        currentEffectiveSettingsSource = effectiveSettingsSource(for: resolved)
        scheduler.reschedule(with: resolved)
        refreshDecisionTrace()
    }

    func insightCards(range: Int) -> [InsightCard] {
        guard let repository else { return [] }
        let dailyStats = repository.dailyStats(for: range)
        let sessions = repository.recentSessions(for: range)
        let analytics = repository.analyticsSnapshot(for: range, insightsStore: insightsStore)
        return InsightsEngine.generateCards(dailyStats: dailyStats, sessions: sessions, analytics: analytics, settings: scheduler.currentSettings)
    }

    func reviewSuggestionCards() -> [InsightCard] {
        guard scheduler.currentSettings.onboardingReviewState.shouldPresent() else { return [] }
        return Array(insightCards(range: 30).prefix(3))
    }

    func dismissReviewSuggestions() {
        var settings = scheduler.currentSettings
        settings.onboardingReviewState.dismissalCount += 1
        settings.onboardingReviewState.lastPresentedAt = Date()
        scheduler.currentSettings = settings
    }

    private func scheduleAutomationTimer() {
        automationTimer?.invalidate()
        automationTimer = nil
        guard !scheduler.currentSettings.autoProfileRules.isEmpty else { return }
        automationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.evaluateAutoProfileRules()
            }
        }
    }

    private func evaluateAutoProfileRules() {
        guard !isEvaluatingAutomaticProfiles else { return }
        currentEffectiveSettingsSource = effectiveSettingsSource(for: scheduler.currentSettings)
        guard scheduler.currentSettings.profileActivationMode == .automatic else {
            matchedAutoProfileRule = nil
            refreshDecisionTrace()
            return
        }
        let rules = scheduler.currentSettings.autoProfileRules
            .filter(\.enabled)
            .sorted {
                if $0.priority == $1.priority {
                    return $0.id.uuidString < $1.id.uuidString
                }
                return $0.priority > $1.priority
            }
        let context = currentAutomationContext()
        let matchedRule = rules.first(where: { $0.matches(context) })
        matchedAutoProfileRule = matchedRule
        refreshDecisionTrace()

        guard let matchedRule,
              let profile = scheduler.currentSettings.profiles.first(where: { $0.id == matchedRule.profileID }),
              scheduler.currentSettings.activeProfileId != profile.id else { return }

        isEvaluatingAutomaticProfiles = true
        defer { isEvaluatingAutomaticProfiles = false }

        var settings = scheduler.currentSettings
        settings.apply(profile: profile)
        settings.profileActivationMode = .automatic
        scheduler.reschedule(with: settings)
        refreshDecisionTrace()
    }

    private func currentAutomationContext() -> ProfileAutomationContext {
        let now = Date()
        let components = Calendar.current.dateComponents([.hour, .minute], from: now)
        let minutesFromMidnight = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let focusEnabled = lastKnownFocusModeEnabled ?? readFocusModeEnabled() ?? false
        let frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return ProfileAutomationContext(
            minutesFromMidnight: minutesFromMidnight,
            hasMatchingCalendarEvent: !currentCalendarEventIDs.isEmpty,
            isFocusModeEnabled: focusEnabled,
            frontmostBundleID: frontmostBundleID,
            externalDisplayConnected: NSScreen.screens.count > 1
        )
    }

    private func matchingCalendarEvents(at now: Date) -> [EKEvent] {
        let filterMode = scheduler.currentSettings.calendarFilterMode
        let filteredIDs = Set(scheduler.currentSettings.filteredCalendarIDs)
        var calendars = ekStore.calendars(for: .event)
        if filterMode == .selected && !filteredIDs.isEmpty {
            calendars = calendars.filter { filteredIDs.contains($0.calendarIdentifier) }
        }
        let predicate = ekStore.predicateForEvents(withStart: now.addingTimeInterval(-1), end: now.addingTimeInterval(1), calendars: calendars)
        let options = scheduler.currentSettings.calendarMatchOptions
        return ekStore.events(matching: predicate).filter { event in
            guard event.startDate <= now && event.endDate >= now else { return false }
            let availability = availabilityMatch(for: event.availability)
            let durationMinutes = max(1, Int(event.endDate.timeIntervalSince(event.startDate) / 60))
            switch filterMode {
            case .busyOnly:
                guard availability == .busy || availability == .unavailable else { return false }
            case .all, .selected:
                break
            }
            return options.matches(
                title: event.title,
                availability: availability,
                isAllDay: event.isAllDay,
                durationMinutes: durationMinutes
            )
        }
    }

    private func availabilityMatch(for availability: EKEventAvailability) -> CalendarAvailabilityMatch {
        switch availability {
        case .free:
            return .free
        case .tentative:
            return .tentative
        case .unavailable:
            return .unavailable
        default:
            return .busy
        }
    }

    private func activeProfileName() -> String? {
        guard let activeProfileID = scheduler.currentSettings.activeProfileId else { return nil }
        return scheduler.currentSettings.profiles.first(where: { $0.id == activeProfileID })?.name
    }

    private func effectiveSettingsSource(for settings: AppSettings) -> EffectiveSettingsSource {
        if managedSettings != nil { return .managed }
        if settings.localOnlyMode { return .local }
        if settingsSync.lastSyncMetadata != nil { return .synced }
        return .local
    }

    func refreshDecisionTrace() {
        scheduler.updateDecisionTrace(
            effectiveSource: currentEffectiveSettingsSource,
            matchedRule: matchedAutoProfileRule,
            lastSyncWriter: settingsSync.lastSyncMetadata?.deviceName
        )
    }

    private func legacyBreakType(_ customType: CustomBreakType) -> BreakType {
        let lower = customType.name.lowercased()
        if lower.contains("micro") { return .micro }
        if lower.contains("long") { return .long }
        return .eye
    }
}
