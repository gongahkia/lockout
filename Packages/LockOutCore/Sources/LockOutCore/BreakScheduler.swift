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
        var soonest: (type: BreakType, fireDate: Date)?
        for customType in settings.customBreakTypes.filter(\.enabled) {
            let fireDate = now.addingTimeInterval(Double(customType.intervalMinutes) * 60 - offsetSeconds)
            let id = customType.id
            let legacyType = legacyBreakType(for: customType)
            let timer = Timer.scheduledTimer(withTimeInterval: max(0, fireDate.timeIntervalSinceNow), repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.timerFired(type: legacyType, customTypeID: id) }
            }
            timers[legacyType] = timer
            if soonest == nil || fireDate < soonest!.fireDate { soonest = (type: legacyType, fireDate: fireDate) }
        }
        nextBreak = soonest
    }

    // maps customBreakType to nearest legacy BreakType for backward compat; uses name heuristic
    private func legacyBreakType(for t: CustomBreakType) -> BreakType {
        let lower = t.name.lowercased()
        if lower.contains("micro") { return .micro }
        if lower.contains("long") { return .long }
        return .eye
    }

    public func stop() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }

    public var currentCustomBreakType: CustomBreakType? {
        guard let nb = nextBreak else { return nil }
        return currentSettings.customBreakTypes.first { legacyBreakType(for: $0) == nb.type }
    }

    public func snooze(minutes: Int? = nil) {
        let mins = minutes ?? currentCustomBreakType?.snoozeMinutes ?? currentSettings.snoozeDurationMinutes
        guard mins > 0 else { return }
        let clamped = min(mins, 60)
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

    private func timerFired(type: BreakType, customTypeID: UUID? = nil) {
        timers[type] = nil
        let pending = timers.compactMap { (t, timer) -> (BreakType, Date)? in
            (t, timer.fireDate)
        }.min(by: { $0.1 < $1.1 })
        if let (t, d) = pending {
            nextBreak = (type: t, fireDate: d)
        } else {
            nextBreak = (type: type, fireDate: Date())
        }
    }
}
