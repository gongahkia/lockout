import AppKit
import Combine
import LookAwayCore

final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var tickTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var countdownItem: NSMenuItem!

    private var scheduler: BreakScheduler { AppDelegate.shared.scheduler }

    init() {
        setup()
        scheduler.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateIcon() }
        }.store(in: &cancellables)
        startTick()
    }

    private func setup() {
        statusItem.button?.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "LookAway")
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
        let nowItem = NSMenuItem(title: "Take Break Now", action: #selector(takeBreakNow), keyEquivalent: "")
        nowItem.target = self
        menu.addItem(nowItem)
        let snoozeItem = NSMenuItem(title: "Snooze 5 min", action: #selector(snooze), keyEquivalent: "")
        snoozeItem.target = self
        menu.addItem(snoozeItem)
        menu.addItem(.separator())
        let openItem = NSMenuItem(title: "Open LookAway", action: #selector(openApp), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit LookAway", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        statusItem.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "LookAway")
        statusItem.button?.image?.isTemplate = true
        // update pause menu label
        if let item = menu.item(withTitle: "Pause Breaks") ?? menu.item(withTitle: "Resume Breaks") {
            item.title = isPaused ? "Resume Breaks" : "Pause Breaks"
        }
        // update snooze label
        if let item = menu.item(withTitle: { menu.items.first(where: { $0.title.hasPrefix("Snooze") })?.title ?? "" }()) {
            let n = scheduler.currentSettings.snoozeDurationMinutes
            item.title = "Snooze \(n) min"
        }
    }

    private func updateOverdue() {
        guard let nb = scheduler.nextBreak else { return }
        let overdue = nb.fireDate.addingTimeInterval(120) < Date()
        statusItem.button?.appearsDisabled = overdue
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
        NSApp.windows.first(where: { $0.title == "LookAway" })?.makeKeyAndOrderFront(nil)
    }
}
