import Foundation
import Combine

@MainActor
public final class BreakScheduler: ObservableObject {
    @Published public var nextBreak: (type: BreakType, fireDate: Date)?
    @Published public var currentSettings: AppSettings

    var timers: [BreakType: Timer] = [:] // internal for testability

    public init(settings: AppSettings = .defaults) {
        self.currentSettings = settings
    }

    deinit {
        timers.values.forEach { $0.invalidate() } // stop() can't be called in deinit due to @MainActor isolation
        timers.removeAll()
    }

    public func start(settings: AppSettings, offsetSeconds: TimeInterval = 0) {
        stop()
        currentSettings = settings
        guard !settings.isPaused else { return }
        let now = Date()
        let configs: [(BreakType, BreakConfig)] = [
            (.eye, settings.eyeConfig),
            (.micro, settings.microConfig),
            (.long, settings.longConfig),
        ]
        var soonest: (type: BreakType, fireDate: Date)?
        for (type, config) in configs where config.isEnabled {
            let fireDate = now.addingTimeInterval(Double(config.intervalMinutes) * 60 - offsetSeconds)
            let timer = Timer.scheduledTimer(withTimeInterval: max(0, fireDate.timeIntervalSinceNow), repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.timerFired(type: type) }
            }
            timers[type] = timer
            if soonest == nil || fireDate < soonest!.fireDate { soonest = (type: type, fireDate: fireDate) }
        }
        nextBreak = soonest
    }

    public func stop() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }

    public func snooze(minutes: Int) {
        guard minutes > 0 else { return }
        let clamped = min(minutes, 60)
        stop()
        guard var nb = nextBreak else { return }
        nb.fireDate = Date().addingTimeInterval(Double(clamped) * 60)
        nextBreak = nb
        let snoozeType = nb.type
        let timer = Timer.scheduledTimer(withTimeInterval: nb.fireDate.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.timerFired(type: snoozeType) }
        }
        timers[nb.type] = timer
    }

    public func skip(repository: BreakHistoryRepository) {
        guard let nb = nextBreak else { return }
        let session = BreakSession(type: nb.type, scheduledAt: nb.fireDate, status: .skipped)
        repository.save(session)
        reschedule(with: currentSettings)
    }

    public func markCompleted(repository: BreakHistoryRepository) {
        guard let nb = nextBreak else { return }
        let session = BreakSession(type: nb.type, scheduledAt: nb.fireDate, endedAt: Date(), status: .completed)
        repository.save(session)
        reschedule(with: currentSettings)
    }

    public func pause() {
        stop()
        currentSettings.isPaused = true
        nextBreak = nil
        AppSettingsStore.save(currentSettings)
    }

    public func resume() {
        currentSettings.isPaused = false
        AppSettingsStore.save(currentSettings)
        start(settings: currentSettings)
    }

    public func reschedule(with settings: AppSettings) {
        stop()
        start(settings: settings)
    }

    private func timerFired(type: BreakType) {
        timers[type] = nil
        // update nextBreak to the soonest remaining pending timer
        let pending = timers.compactMap { (t, timer) -> (BreakType, Date)? in
            let remaining = timer.fireDate
            return (t, remaining)
        }.min(by: { $0.1 < $1.1 })
        if let (t, d) = pending {
            nextBreak = (type: t, fireDate: d)
        } else {
            nextBreak = (type: type, fireDate: Date()) // fired type becomes current
        }
        // caller observes nextBreak for overlay
    }
}
