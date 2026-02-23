import AppKit
import Combine
import LockOutCore

final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var tickTimer: Timer?
    private var midnightTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var countdownItem: NSMenuItem!

    private var scheduler: BreakScheduler { AppDelegate.shared.scheduler }

    init() {
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
        updateOverdue() // re-evaluate fullscreen detection on every app switch
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
        let nowItem = NSMenuItem(title: "Take Break Now", action: #selector(takeBreakNow), keyEquivalent: "")
        nowItem.target = self
        menu.addItem(nowItem)
        let snoozeItem = NSMenuItem(title: "Snooze 5 min", action: #selector(snooze), keyEquivalent: "")
        snoozeItem.target = self
        menu.addItem(snoozeItem)
        menu.addItem(.separator())
        let openItem = NSMenuItem(title: "Open LockOut", action: #selector(openApp), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit LockOut", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    private func startTick() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateCountdown()
            self?.updateOverdue()
        }
    }

    private func updateCountdown() {
        guard let nb = scheduler.nextBreak else {
            countdownItem.title = "Breaks paused"
            return
        }
        let remaining = max(0, nb.fireDate.timeIntervalSinceNow)
        let mins = Int(remaining) / 60
        let secs = Int(remaining) % 60
        countdownItem.title = "\(nb.type.rawValue.capitalized) break in \(String(format: "%02d:%02d", mins, secs))"
    }

    private func updateIcon() {
        let isPaused = scheduler.currentSettings.isPaused
        let name = isPaused ? "eye.slash" : "eye"
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "LockOut")
        statusItem.button?.image?.isTemplate = true
        // update pause menu label
        if let item = menu.item(withTitle: "Pause Breaks") ?? menu.item(withTitle: "Resume Breaks") {
            item.title = isPaused ? "Resume Breaks" : "Pause Breaks"
        }
        // update snooze label
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
        AppDelegate.shared.overlayController?.show(
            breakType: scheduler.nextBreak?.type ?? .eye,
            duration: scheduler.currentSettings.eyeConfig.durationSeconds
        )
    }

    @objc private func snooze() {
        scheduler.snooze(minutes: scheduler.currentSettings.snoozeDurationMinutes)
    }

    @objc private func openApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.title == "LockOut" })?.makeKeyAndOrderFront(nil)
    }
}
