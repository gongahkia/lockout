import Foundation
import Combine

@MainActor
public final class BreakScheduler: ObservableObject {
    @Published public var nextBreak: (customTypeID: UUID, fireDate: Date)?
    @Published public var currentSettings: AppSettings

    var timers: [UUID: Timer] = [:] // internal for testability

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
        var soonest: (customTypeID: UUID, fireDate: Date)?
        for customType in settings.customBreakTypes.filter(\.enabled) {
            let requested = now.addingTimeInterval(Double(customType.intervalMinutes) * 60 - offsetSeconds)
            let fireDate = clampedFireDate(for: customType.id, requestedFireDate: requested)
            let id = customType.id
            scheduleTimer(for: id, fireDate: fireDate)
            if soonest == nil || fireDate < soonest!.fireDate { soonest = (customTypeID: id, fireDate: fireDate) }
        }
        if let soonest {
            nextBreak = (customTypeID: soonest.customTypeID, fireDate: soonest.fireDate)
        } else {
            nextBreak = nil
        }
    }

    // maps custom break type IDs to legacy break groups for backward compatibility.
    private func legacyBreakType(forCustomTypeID id: UUID) -> BreakType {
        guard let idx = currentSettings.customBreakTypes.firstIndex(where: { $0.id == id }) else {
            return .eye
        }
        switch idx {
        case 0: return .eye
        case 1: return .micro
        case 2: return .long
        default: return .eye
        }
    }

    public func breakType(for customType: CustomBreakType) -> BreakType {
        guard currentSettings.customBreakTypes.contains(where: { $0.id == customType.id }) else {
            return .eye
        }
        return legacyBreakType(forCustomTypeID: customType.id)
    }

    public func stop() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }

    public var onBreakTriggered: ((CustomBreakType) -> Void)?

    public func triggerBreak(_ customType: CustomBreakType) {
        onBreakTriggered?(customType)
    }

    public var currentCustomBreakType: CustomBreakType? {
        guard let customTypeID = nextBreak?.customTypeID else { return nil }
        return currentSettings.customBreakTypes.first { $0.id == customTypeID }
    }

    public func snooze(minutes: Int? = nil, repository: BreakHistoryRepository? = nil, cloudSync: CloudKitSyncService? = nil) {
        let breakTypeName = currentCustomBreakType?.name
        let mins = minutes ?? currentCustomBreakType?.snoozeMinutes ?? currentSettings.snoozeDurationMinutes
        guard mins > 0 else { return }
        let clamped = min(mins, 60)
        if let repository, let nb = nextBreak {
            let session = BreakSession(type: legacyBreakType(forCustomTypeID: nb.customTypeID), scheduledAt: nb.fireDate, status: .snoozed, breakTypeName: breakTypeName)
            repository.save(session)
            if !currentSettings.localOnlyMode, let cloudSync {
                Task { await cloudSync.uploadSession(session) }
            }
        }
        stop()
        guard var nb = nextBreak else { return }
        nb.fireDate = Date().addingTimeInterval(Double(clamped) * 60)
        nextBreak = nb
        let customTypeID = nb.customTypeID
        scheduleTimer(for: customTypeID, fireDate: nb.fireDate)
    }

    public func skip(repository: BreakHistoryRepository, cloudSync: CloudKitSyncService? = nil) {
        guard let nb = nextBreak else { return }
        let session = BreakSession(type: legacyBreakType(forCustomTypeID: nb.customTypeID), scheduledAt: nb.fireDate, status: .skipped, breakTypeName: currentCustomBreakType?.name)
        repository.save(session)
        if !currentSettings.localOnlyMode, let cloudSync {
            Task { await cloudSync.uploadSession(session) }
        }
        reschedule(with: currentSettings)
    }

    public func markCompleted(repository: BreakHistoryRepository, cloudSync: CloudKitSyncService? = nil) {
        guard let nb = nextBreak else { return }
        let session = BreakSession(type: legacyBreakType(forCustomTypeID: nb.customTypeID), scheduledAt: nb.fireDate, endedAt: Date(), status: .completed, breakTypeName: currentCustomBreakType?.name)
        repository.save(session)
        if !currentSettings.localOnlyMode, let cloudSync {
            Task { await cloudSync.uploadSession(session) }
        }
        reschedule(with: currentSettings)
    }

    public func markDeferred(repository: BreakHistoryRepository, cloudSync: CloudKitSyncService? = nil) {
        guard let nb = nextBreak else { return }
        let session = BreakSession(type: legacyBreakType(forCustomTypeID: nb.customTypeID), scheduledAt: nb.fireDate, status: .deferred, breakTypeName: currentCustomBreakType?.name)
        repository.save(session)
        if !currentSettings.localOnlyMode, let cloudSync {
            Task { await cloudSync.uploadSession(session) }
        }
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

    func simulateTimerFireForTesting(customTypeID: UUID) {
        timerFired(customTypeID: customTypeID)
    }

    private func scheduleTimer(for customTypeID: UUID, fireDate: Date) {
        let clampedDate = clampedFireDate(for: customTypeID, requestedFireDate: fireDate)
        let timer = Timer.scheduledTimer(withTimeInterval: clampedDate.timeIntervalSinceNow, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.timerFired(customTypeID: customTypeID) }
        }
        timers[customTypeID] = timer
    }

    private func clampedFireDate(for customTypeID: UUID, requestedFireDate: Date) -> Date {
        let now = Date()
        guard let customType = currentSettings.customBreakTypes.first(where: { $0.id == customTypeID }) else {
            return max(requestedFireDate, now.addingTimeInterval(1))
        }
        let intervalSeconds = max(60, Double(customType.intervalMinutes) * 60)
        var delay = requestedFireDate.timeIntervalSince(now)
        if delay < 1 {
            let missedIntervals = floor((-delay) / intervalSeconds) + 1
            delay += missedIntervals * intervalSeconds
        }
        if delay < 1 { delay = 1 }
        return now.addingTimeInterval(delay)
    }

    private func timerFired(customTypeID: UUID) {
        if let customType = currentSettings.customBreakTypes.first(where: { $0.id == customTypeID }) {
            onBreakTriggered?(customType)
            if customType.enabled && !currentSettings.isPaused {
                let nextFireDate = Date().addingTimeInterval(Double(customType.intervalMinutes) * 60)
                scheduleTimer(for: customTypeID, fireDate: nextFireDate)
            }
        }
        let pending = timers.compactMap { (id, timer) -> (UUID, Date)? in
            (id, timer.fireDate)
        }.min(by: { $0.1 < $1.1 })
        if let (id, d) = pending {
            nextBreak = (customTypeID: id, fireDate: d)
        } else {
            nextBreak = (customTypeID: customTypeID, fireDate: Date())
        }
    }
}
