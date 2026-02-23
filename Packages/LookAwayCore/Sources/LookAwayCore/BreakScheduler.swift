import Foundation
import Combine

@MainActor
public final class BreakScheduler: ObservableObject {
    @Published public var nextBreak: (type: BreakType, fireDate: Date)?
    @Published public var currentSettings: AppSettings

    private var timers: [BreakType: Timer] = [:]

    public init(settings: AppSettings = .defaults) {
        self.currentSettings = settings
    }

    public func start(settings: AppSettings) {
        stop()
        currentSettings = settings
        guard !settings.isPaused else { return }
        let now = Date()
        var candidates: [(type: BreakType, fireDate: Date)] = []
        let configs: [(BreakType, BreakConfig)] = [
            (.eye, settings.eyeConfig),
            (.micro, settings.microConfig),
            (.long, settings.longConfig),
        ]
        for (type, config) in configs where config.isEnabled {
            let fireDate = now.addingTimeInterval(Double(config.intervalMinutes) * 60)
            candidates.append((type: type, fireDate: fireDate))
        }
        guard let earliest = candidates.min(by: { $0.fireDate < $1.fireDate }) else { return }
        nextBreak = earliest
        let timer = Timer.scheduledTimer(withTimeInterval: earliest.fireDate.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.timerFired() }
        }
        timers[earliest.type] = timer
    }

    public func stop() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }

    public func snooze(minutes: Int) {
        stop()
        guard var nb = nextBreak else { return }
        nb.fireDate = Date().addingTimeInterval(Double(minutes) * 60)
        nextBreak = nb
        let timer = Timer.scheduledTimer(withTimeInterval: nb.fireDate.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.timerFired() }
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
    }

    public func resume() {
        currentSettings.isPaused = false
        start(settings: currentSettings)
    }

    public func reschedule(with settings: AppSettings) {
        stop()
        start(settings: settings)
    }

    private func timerFired() {
        // caller (AppDelegate / iOS App) observes nextBreak and fires overlay
    }
}
