import AppKit
import Combine
import Sparkle
import LockOutCore

final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var tickTimer: Timer?
    private var midnightTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var countdownItem: NSMenuItem!
    private var tickCount = 0
    private var appSwitchDebounceWork: DispatchWorkItem?

    private let scheduler: BreakScheduler
    private let repository: BreakHistoryRepository
    private let settingsSync: SettingsSyncService
    private let showBreak: (BreakType, Int) -> Void
    private let updater: SPUStandardUpdaterController

    init(scheduler: BreakScheduler,
         repository: BreakHistoryRepository,
         settingsSync: SettingsSyncService,
         updater: SPUStandardUpdaterController,
         showBreak: @escaping (BreakType, Int) -> Void) {
        self.scheduler = scheduler
        self.repository = repository
        self.settingsSync = settingsSync
        self.updater = updater
        self.showBreak = showBreak
        setup()
        scheduler.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateIcon() }
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
        countdownItem = NSMenuItem(title: "Next break: --:--", action: nil, keyEquivalent: "")
        countdownItem.isEnabled = false
        menu.addItem(countdownItem)
        menu.addItem(.separator())
        let pauseItem = NSMenuItem(title: "Pause Breaks", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
        let pauseTomorrow = NSMenuItem(title: "Pause until tomorrow", action: #selector(pauseUntilTomorrow), keyEquivalent: "")
        pauseTomorrow.target = self
        menu.addItem(pauseTomorrow)
        let nowItem = NSMenuItem(title: "Take Break Now", action: nil, keyEquivalent: "")
        let breakSubmenu = NSMenu()
        nowItem.submenu = breakSubmenu
        rebuildBreakSubmenu(breakSubmenu)
        menu.addItem(nowItem)
        let snoozeItem = NSMenuItem(title: "Snooze 5 min", action: #selector(snooze), keyEquivalent: "")
        snoozeItem.target = self
        menu.addItem(snoozeItem)
        menu.addItem(.separator())
        let openItem = NSMenuItem(title: "Open LockOut", action: #selector(openApp), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        let profileMenu = NSMenu()
        let profileItem = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        profileItem.submenu = profileMenu
        menu.addItem(profileItem)
        rebuildProfileMenu(profileMenu)
        menu.addItem(.separator())
        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(SPUUpdater.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updater.updater
        menu.addItem(updateItem)
        let quitItem = NSMenuItem(title: "Quit LockOut", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    private func startTick() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            tickCount += 1
            updateCountdown()
            updateOverdue()
            if tickCount % 60 == 0 { updateStreak() }
        }
    }

    func updateStreak() {
        let streak = ComplianceCalculator.streakDays(stats: repository.dailyStats(for: 30))
        statusItem.button?.title = streak > 0 ? " \(streak)" : ""
        statusItem.button?.imagePosition = streak > 0 ? .imageLeading : .imageOnly
    }

    private func updateCountdown() {
        guard let nb = scheduler.nextBreak else {
            countdownItem.title = "Breaks paused"
            return
        }
        let remaining = max(0, nb.fireDate.timeIntervalSinceNow)
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        countdownItem.title = "Next break in \(String(format: "%d:%02d", mins, secs))"
    }

    private func updateIcon() {
        let isPaused = scheduler.currentSettings.isPaused
        let name = isPaused ? "eye.slash" : "eye"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "LockOut")
        statusItem.button?.image?.isTemplate = true
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
        scheduler.pause()
        midnightTimer?.invalidate()
        let cal = Calendar.current
        guard let midnight = cal.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime) else { return }
        midnightTimer = Timer.scheduledTimer(withTimeInterval: midnight.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            self?.scheduler.resume()
        }
        updateIcon()
    }

    @objc private func togglePause() {
        if scheduler.currentSettings.isPaused { scheduler.resume() } else { scheduler.pause() }
        updateIcon()
    }

    @objc private func takeBreakNow() {
        showBreak(scheduler.nextBreak?.type ?? .eye, scheduler.currentSettings.eyeConfig.durationSeconds)
    }

    @objc private func snooze() {
        scheduler.snooze() // uses per-break-type snoozeMinutes
    }

    @objc private func openApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.title == "LockOut" })?.makeKeyAndOrderFront(nil)
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
        scheduler.currentSettings.activeProfileId = id
        scheduler.currentSettings.customBreakTypes = profile.customBreakTypes
        scheduler.currentSettings.blockedBundleIDs = profile.blockedBundleIDs
        scheduler.currentSettings.idleThresholdMinutes = profile.idleThresholdMinutes
        scheduler.reschedule(with: scheduler.currentSettings)
    }

    func stopObserving() {
        tickTimer?.invalidate()
        tickTimer = nil
        midnightTimer?.invalidate()
        midnightTimer = nil
        cancellables.removeAll()
    }
}
