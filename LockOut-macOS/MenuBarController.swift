import AppKit
import Combine
import Sparkle
import LockOutCore

@MainActor
final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var tickTimer: Timer?
    private var midnightTimer: Timer?
    private var manualResumeTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var countdownItem: NSMenuItem!
    private var upcomingItem: NSMenuItem! // #22
    private var tickCount = 0
    private var appSwitchDebounceWork: DispatchWorkItem?
    private var breakSubmenu: NSMenu?
    private var profileSubmenu: NSMenu?
    private var inspectorSubmenu: NSMenu?

    private let scheduler: BreakScheduler
    private let repository: BreakHistoryRepository
    private let cloudSync: CloudKitSyncService
    private let settingsSync: SettingsSyncService
    private let showBreak: (BreakType, Int) -> Void
    private let updater: SPUStandardUpdaterController
    private var appDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }

    init(scheduler: BreakScheduler,
         repository: BreakHistoryRepository,
         cloudSync: CloudKitSyncService,
         settingsSync: SettingsSyncService,
         updater: SPUStandardUpdaterController,
         showBreak: @escaping (BreakType, Int) -> Void) {
        self.scheduler = scheduler
        self.repository = repository
        self.cloudSync = cloudSync
        self.settingsSync = settingsSync
        self.updater = updater
        self.showBreak = showBreak
        setup()
        scheduler.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.updateIcon()
                if let breakSubmenu = self.breakSubmenu {
                    self.rebuildBreakSubmenu(breakSubmenu)
                }
                if let profileSubmenu = self.profileSubmenu {
                    self.rebuildProfileMenu(profileSubmenu)
                }
                if let inspectorSubmenu = self.inspectorSubmenu {
                    self.rebuildInspectorMenu(inspectorSubmenu)
                }
            }
        }.store(in: &cancellables)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appSwitched), name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        startTick()
    }

    @objc private func appSwitched() {
        appSwitchDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateOverdue() }
        appSwitchDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func setup() {
        statusItem.button?.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "LockOut")
        statusItem.button?.image?.isTemplate = true
        buildMenu()
        statusItem.menu = menu
    }

    private func buildMenu() {
        // #18: Open LockOut at the top for discoverability
        let openItem = NSMenuItem(title: "Open LockOut", action: #selector(openApp), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        countdownItem = NSMenuItem(title: "Next break: --:--", action: nil, keyEquivalent: "")
        countdownItem.isEnabled = false
        menu.addItem(countdownItem)
        // #22: upcoming schedule item
        upcomingItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        upcomingItem.isEnabled = false
        upcomingItem.isHidden = true
        menu.addItem(upcomingItem)
        menu.addItem(.separator())
        let pauseItem = NSMenuItem(title: "Pause Breaks", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
        let pause30 = NSMenuItem(title: "Pause 30 min", action: #selector(pauseThirtyMinutes), keyEquivalent: "")
        pause30.target = self
        menu.addItem(pause30)
        let pause60 = NSMenuItem(title: "Pause 60 min", action: #selector(pauseSixtyMinutes), keyEquivalent: "")
        pause60.target = self
        menu.addItem(pause60)
        let pauseTomorrow = NSMenuItem(title: "Pause until tomorrow", action: #selector(pauseUntilTomorrow), keyEquivalent: "")
        pauseTomorrow.target = self
        menu.addItem(pauseTomorrow)
        let nowItem = NSMenuItem(title: "Take Break Now", action: nil, keyEquivalent: "")
        let breakSubmenu = NSMenu()
        self.breakSubmenu = breakSubmenu
        nowItem.submenu = breakSubmenu
        rebuildBreakSubmenu(breakSubmenu)
        menu.addItem(nowItem)
        let snoozeItem = NSMenuItem(title: "Snooze 5 min", action: #selector(snooze), keyEquivalent: "")
        snoozeItem.target = self
        menu.addItem(snoozeItem)
        menu.addItem(.separator())
        let profileMenu = NSMenu()
        self.profileSubmenu = profileMenu
        let profileItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        profileItem.submenu = profileMenu
        menu.addItem(profileItem)
        rebuildProfileMenu(profileMenu)
        let inspectorMenu = NSMenu()
        self.inspectorSubmenu = inspectorMenu
        let inspectorItem = NSMenuItem(title: "Why LockOut?", action: nil, keyEquivalent: "")
        inspectorItem.submenu = inspectorMenu
        menu.addItem(inspectorItem)
        rebuildInspectorMenu(inspectorMenu)
        menu.addItem(.separator())
        let aboutItem = NSMenuItem(title: "About LockOut v\(AppVersion.current)", action: nil, keyEquivalent: "")
        aboutItem.isEnabled = false
        menu.addItem(aboutItem)
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updater
        menu.addItem(updateItem)
        let quitItem = NSMenuItem(title: "Quit LockOut", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    private func startTick() { // #13: adaptive tick rate
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleTick()
            }
        }
    }

    private func handleTick() {
        tickCount += 1
        let menuVisible = statusItem.menu?.highlightedItem != nil
        if menuVisible || tickCount % 5 == 0 { // update countdown every 5s unless menu is open
            updateCountdown()
        }
        if tickCount % 10 == 0 {
            updateOverdue()
        }
        if tickCount % 60 == 0 {
            updateStreak()
        }
    }

    func updateStreak() {
        let streak = ComplianceCalculator.streakDays(stats: repository.dailyStats(for: 30))
        statusItem.button?.title = streak > 0 ? " \(streak)" : ""
        statusItem.button?.imagePosition = streak > 0 ? .imageLeading : .imageOnly
    }

    private func updateCountdown() {
        if let pauseStatus = scheduler.pauseStatusLabel {
            countdownItem.title = pauseStatus
            upcomingItem.title = scheduler.pendingDeferredSummary ?? ""
            upcomingItem.isHidden = scheduler.pendingDeferredSummary == nil
            return
        }
        if let pending = scheduler.pendingDeferredSummary {
            countdownItem.title = pending
        } else if let nb = scheduler.nextBreak {
            let remaining = max(0, nb.fireDate.timeIntervalSinceNow)
            let mins = Int(remaining) / 60
            let secs = Int(remaining) % 60
            let breakName = scheduler.currentCustomBreakType?.name ?? "Break"
            countdownItem.title = "Next \(breakName) in \(String(format: "%d:%02d", mins, secs))"
        } else {
            countdownItem.title = "No breaks scheduled"
        }
        if scheduler.pendingDeferredSummary != nil {
            upcomingItem.isHidden = true
            return
        }
        updateUpcoming() // #22
    }

    private func updateUpcoming() { // #22: show all upcoming breaks
        let upcoming = scheduler.allUpcomingBreaks
        if upcoming.count <= 1 {
            upcomingItem.isHidden = true
            return
        }
        let lines = upcoming.dropFirst().prefix(3).map { b in
            let mins = max(0, Int(b.fireDate.timeIntervalSinceNow) / 60)
            return "\(b.name) in \(mins)m"
        }
        upcomingItem.title = "Then: " + lines.joined(separator: ", ")
        upcomingItem.isHidden = false
    }

    private func iconImageName(paused: Bool) -> String {
        switch scheduler.currentSettings.menuBarIconTheme {
        case .color: return paused ? "eye.slash.fill" : "eye.fill"
        case .minimal: return paused ? "pause.circle" : "timer"
        case .monochrome: return paused ? "eye.slash" : "eye"
        }
    }

    private func updateIcon() {
        let isPaused = scheduler.isPaused
        let name = iconImageName(paused: isPaused)
        let isTemplate = scheduler.currentSettings.menuBarIconTheme != .color
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "LockOut")
        statusItem.button?.image?.isTemplate = isTemplate
        if let item = menu.item(withTitle: "Pause Breaks") ?? menu.item(withTitle: "Resume Breaks") {
            item.title = isPaused ? "Resume Breaks" : "Pause Breaks"
        }
        let n = scheduler.currentSettings.snoozeDurationMinutes
        menu.items.first(where: { $0.title.hasPrefix("Snooze") })?.title = "Snooze \(n) min"
    }

    private func updateOverdue() {
        guard let nb = scheduler.nextBreak else { return }
        let overdue = nb.fireDate.addingTimeInterval(120) < Date()
        statusItem.button?.appearsDisabled = overdue
    }

    @objc private func pauseUntilTomorrow() {
        scheduleManualResume(at: Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime))
    }

    @objc private func pauseThirtyMinutes() {
        scheduleManualResume(after: 30 * 60)
    }

    @objc private func pauseSixtyMinutes() {
        scheduleManualResume(after: 60 * 60)
    }

    private func scheduleManualResume(after interval: TimeInterval) {
        scheduler.pause(reason: .manual)
        manualResumeTimer?.invalidate()
        manualResumeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduler.resume(reason: .manual)
            }
        }
        updateIcon()
    }

    private func scheduleManualResume(at date: Date?) {
        guard let date else { return }
        scheduler.pause(reason: .manual)
        manualResumeTimer?.invalidate()
        manualResumeTimer = Timer.scheduledTimer(withTimeInterval: max(date.timeIntervalSinceNow, 1), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduler.resume(reason: .manual)
            }
        }
        updateIcon()
    }

    @objc private func togglePause() {
        manualResumeTimer?.invalidate()
        if scheduler.isPaused { scheduler.resume(reason: .manual) } else { scheduler.pause(reason: .manual) }
        updateIcon()
    }

    @objc private func takeBreakNow() {
        if let customType = scheduler.currentCustomBreakType {
            scheduler.triggerBreak(customType)
        } else if let customType = scheduler.currentSettings.customBreakTypes.first(where: \.enabled) ?? scheduler.currentSettings.customBreakTypes.first {
            scheduler.triggerBreak(customType)
        } else {
            showBreak(.eye, scheduler.currentSettings.eyeConfig.durationSeconds)
        }
    }

    @objc private func snooze() {
        scheduler.snooze(repository: repository, cloudSync: cloudSync) // uses per-break-type snoozeMinutes
    }

    @objc private func openApp() {
        let priorPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.title == "LockOut" })?.makeKeyAndOrderFront(nil)
        if priorPolicy == .accessory {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func rebuildBreakSubmenu(_ submenu: NSMenu) {
        submenu.removeAllItems()
        for ct in scheduler.currentSettings.customBreakTypes.filter(\.enabled) {
            let item = NSMenuItem(title: ct.name, action: #selector(triggerCustomBreak(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = ct.id.uuidString
            submenu.addItem(item)
        }
        if submenu.items.isEmpty {
            let fallback = NSMenuItem(title: "Take Break", action: #selector(takeBreakNow), keyEquivalent: "")
            fallback.target = self
            submenu.addItem(fallback)
        }
    }

    @objc private func triggerCustomBreak(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let id = UUID(uuidString: idStr),
              let ct = scheduler.currentSettings.customBreakTypes.first(where: { $0.id == id }) else { return }
        scheduler.triggerBreak(ct)
    }

    private func rebuildProfileMenu(_ profileMenu: NSMenu) {
        profileMenu.removeAllItems()
        if scheduler.currentSettings.profileActivationMode == .manualHold {
            let automaticItem = NSMenuItem(title: "Return to Automatic", action: #selector(returnToAutomatic), keyEquivalent: "")
            automaticItem.target = self
            profileMenu.addItem(automaticItem)
            profileMenu.addItem(.separator())
        }
        for profile in scheduler.currentSettings.profiles {
            let item = NSMenuItem(title: profile.name, action: #selector(switchProfile(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id.uuidString
            item.state = scheduler.currentSettings.activeProfileId == profile.id ? .on : .off
            profileMenu.addItem(item)
        }
    }

    @objc private func switchProfile(_ sender: NSMenuItem) {
        guard let idStr = sender.representedObject as? String,
              let id = UUID(uuidString: idStr),
              let profile = scheduler.currentSettings.profiles.first(where: { $0.id == id }) else { return }
        var settings = scheduler.currentSettings
        settings.apply(profile: profile)
        settings.profileActivationMode = .manualHold
        scheduler.reschedule(with: settings)
        appDelegate?.refreshDecisionTrace()
    }

    @objc private func returnToAutomatic() {
        appDelegate?.returnToAutomaticProfileMode()
    }

    private func rebuildInspectorMenu(_ inspectorMenu: NSMenu) {
        inspectorMenu.removeAllItems()
        let trace = scheduler.decisionTrace
        let pauseReasons = trace.activePauseReasons.isEmpty ? "None" : trace.activePauseReasons.map(\.displayName).joined(separator: ", ")
        let rows = [
            "Profile: \(trace.activeProfileName ?? "None")",
            "Mode: \(trace.activationMode.displayName)",
            "Source: \(trace.effectiveSettingsSource.displayName)",
            "Rule: \(trace.matchedRuleSummary ?? "None")",
            "Pause: \(pauseReasons)",
            "Deferred: \(trace.pendingDeferredCondition?.displayName ?? "None")",
            "Last sync writer: \(trace.lastSyncWriter ?? "Unknown")",
        ]
        for row in rows {
            let item = NSMenuItem(title: row, action: nil, keyEquivalent: "")
            item.isEnabled = false
            inspectorMenu.addItem(item)
        }
    }

    func stopObserving() {
        tickTimer?.invalidate()
        tickTimer = nil
        midnightTimer?.invalidate()
        midnightTimer = nil
        manualResumeTimer?.invalidate()
        manualResumeTimer = nil
        cancellables.removeAll()
    }
}
