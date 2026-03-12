import Combine
import Foundation

public struct ScheduledBreakContext: Equatable, Sendable {
    public let customTypeID: UUID
    public let scheduledAt: Date
    public let insightMetadata: BreakInsightMetadata?

    public init(customTypeID: UUID, scheduledAt: Date, insightMetadata: BreakInsightMetadata? = nil) {
        self.customTypeID = customTypeID
        self.scheduledAt = scheduledAt
        self.insightMetadata = insightMetadata
    }

    public func withInsightMetadata(_ metadata: BreakInsightMetadata?) -> ScheduledBreakContext {
        ScheduledBreakContext(customTypeID: customTypeID, scheduledAt: scheduledAt, insightMetadata: metadata)
    }
}

public struct DeferredBreakState: Equatable, Sendable {
    public let context: ScheduledBreakContext
    public let condition: DeferredBreakCondition?
    public let deferredAt: Date

    public init(context: ScheduledBreakContext, condition: DeferredBreakCondition? = nil, deferredAt: Date = Date()) {
        self.context = context
        self.condition = condition
        self.deferredAt = deferredAt
    }

    public var customTypeID: UUID { context.customTypeID }
    public var scheduledAt: Date { context.scheduledAt }

    public func isReadyForRetry(evaluationContext: DeferredBreakEvaluationContext) -> Bool {
        guard let condition else { return true }
        switch condition {
        case let .minutes(minutes):
            return evaluationContext.now >= deferredAt.addingTimeInterval(Double(minutes) * 60)
        case let .untilMeetingEnds(eventID):
            if let eventID {
                return !evaluationContext.activeMeetingEventIDs.contains(eventID)
            }
            return evaluationContext.activeMeetingEventIDs.isEmpty
        case .untilFullscreenEnds:
            return !evaluationContext.isFullscreen
        case let .untilAppChanges(bundleID):
            return evaluationContext.frontmostBundleID != bundleID
        }
    }
}

@MainActor
public final class BreakScheduler: ObservableObject {
    @Published public var nextBreak: (customTypeID: UUID, fireDate: Date)?
    @Published public var currentSettings: AppSettings
    @Published public private(set) var activePauseReasons: Set<PauseReason>
    @Published public private(set) var pendingDeferredBreak: DeferredBreakState?
    @Published public private(set) var decisionTrace: DecisionTrace

    public var onBreakTriggered: ((CustomBreakType, ScheduledBreakContext) -> Void)?
    public var onSessionRecorded: ((BreakSession, BreakInsightMetadata?) -> Void)?

    var timers: [UUID: Timer] = [:]

    private var activeBreakContext: ScheduledBreakContext?
    private static let persistedFireDatesKey = "lockout_persisted_fire_dates"

    public init(settings: AppSettings = .defaults) {
        self.currentSettings = settings
        self.activePauseReasons = settings.isPaused ? [.manual] : []
        self.decisionTrace = DecisionTrace()
        syncDecisionTrace()
    }

    deinit {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }

    public var isPaused: Bool {
        !activePauseReasons.isEmpty
    }

    public var primaryPauseReason: PauseReason? {
        let ordered = PauseReason.allCases.filter { activePauseReasons.contains($0) }
        return ordered.first
    }

    public var pauseStatusLabel: String? {
        primaryPauseReason.map { "Paused: \($0.displayName)" }
    }

    public var pendingDeferredSummary: String? {
        guard let pendingDeferredBreak,
              let customType = currentSettings.customBreakTypes.first(where: { $0.id == pendingDeferredBreak.customTypeID }) else { return nil }
        if let condition = pendingDeferredBreak.condition {
            return "Pending deferred: \(customType.name) until \(condition.displayName)"
        }
        return "Pending deferred: \(customType.name)"
    }

    public var currentCustomBreakType: CustomBreakType? {
        if let context = activeBreakContext {
            return currentSettings.customBreakTypes.first { $0.id == context.customTypeID }
        }
        if let pendingDeferredBreak {
            return currentSettings.customBreakTypes.first { $0.id == pendingDeferredBreak.customTypeID }
        }
        guard let customTypeID = nextBreak?.customTypeID else { return nil }
        return currentSettings.customBreakTypes.first { $0.id == customTypeID }
    }

    public var allUpcomingBreaks: [(customTypeID: UUID, name: String, fireDate: Date)] {
        timers.compactMap { (id, timer) in
            guard let ct = currentSettings.customBreakTypes.first(where: { $0.id == id }) else { return nil }
            return (customTypeID: id, name: ct.name, fireDate: timer.fireDate)
        }.sorted { $0.fireDate < $1.fireDate }
    }

    public func breakContextForPresentation() -> ScheduledBreakContext? {
        activeBreakContext ?? pendingDeferredBreak?.context ?? nextBreak.map { ScheduledBreakContext(customTypeID: $0.customTypeID, scheduledAt: $0.fireDate) }
    }

    public func start(settings: AppSettings, offsetSeconds: TimeInterval = 0) {
        stop()
        currentSettings = settings
        if settings.isPaused && activePauseReasons.isEmpty {
            activePauseReasons = [.manual]
        }
        currentSettings.isPaused = isPaused || settings.isPaused
        guard !currentSettings.isPaused else {
            nextBreak = nil
            Observability.emit(category: "BreakScheduler", message: "start skipped: paused")
            return
        }
        Observability.emit(category: "BreakScheduler", message: "starting with offset=\(offsetSeconds)s, \(settings.customBreakTypes.filter(\.enabled).count) types")
        let now = Date()
        let persisted = Self.loadPersistedFireDates()
        var soonest: (customTypeID: UUID, fireDate: Date)?
        for customType in settings.customBreakTypes.filter(\.enabled) {
            let id = customType.id
            if pendingDeferredBreak?.customTypeID == id { continue }
            let fireDate: Date
            if let saved = persisted[id.uuidString], saved > now {
                fireDate = saved
            } else {
                let requested = now.addingTimeInterval(Double(customType.intervalMinutes) * 60 - offsetSeconds)
                fireDate = clampedFireDate(for: id, requestedFireDate: requested)
            }
            scheduleTimer(for: id, fireDate: fireDate)
            if soonest == nil || fireDate < soonest!.fireDate { soonest = (customTypeID: id, fireDate: fireDate) }
        }
        nextBreak = soonest
        persistFireDates()
    }

    public func stop() {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        nextBreak = nil
    }

    public func triggerBreak(_ customType: CustomBreakType) {
        let context = ScheduledBreakContext(customTypeID: customType.id, scheduledAt: Date())
        onBreakTriggered?(customType, context)
    }

    public func breakType(for customType: CustomBreakType) -> BreakType {
        guard currentSettings.customBreakTypes.contains(where: { $0.id == customType.id }) else {
            return .eye
        }
        return legacyBreakType(forCustomTypeID: customType.id)
    }

    public func beginBreakPresentation(_ context: ScheduledBreakContext) {
        activeBreakContext = context
        if pendingDeferredBreak?.context == context {
            pendingDeferredBreak = nil
        }
        if timers[context.customTypeID] == nil,
           let customType = currentSettings.customBreakTypes.first(where: { $0.id == context.customTypeID }),
           customType.enabled,
           !isPaused {
            let nextFireDate = Date().addingTimeInterval(Double(customType.intervalMinutes) * 60)
            scheduleTimer(for: context.customTypeID, fireDate: nextFireDate)
        }
        refreshNextBreak()
        persistFireDates()
        syncDecisionTrace()
    }

    public func registerDeferredBreak(
        _ context: ScheduledBreakContext,
        condition: DeferredBreakCondition? = nil,
        repository: BreakHistoryRepository,
        cloudSync: CloudKitSyncService? = nil
    ) {
        Observability.emit(category: "BreakScheduler", message: "deferred break=\(customTypeName(for: context.customTypeID) ?? "unknown")")
        if pendingDeferredBreak?.context != context || pendingDeferredBreak?.condition != condition {
            let session = BreakSession(
                type: legacyBreakType(forCustomTypeID: context.customTypeID),
                scheduledAt: context.scheduledAt,
                status: .deferred,
                breakTypeName: customTypeName(for: context.customTypeID)
            )
            repository.save(session)
            onSessionRecorded?(session, context.insightMetadata)
            if !currentSettings.localOnlyMode, let cloudSync {
                Task { await cloudSync.uploadSession(session) }
            }
        }
        activeBreakContext = nil
        pendingDeferredBreak = DeferredBreakState(context: context, condition: condition)
        refreshNextBreak()
        persistFireDates()
        syncDecisionTrace()
    }

    public func clearPendingDeferredBreak() {
        pendingDeferredBreak = nil
        syncDecisionTrace()
    }

    public func updateDecisionTrace(
        effectiveSource: EffectiveSettingsSource,
        matchedRule: AutoProfileRule? = nil,
        lastSyncWriter: String? = nil
    ) {
        decisionTrace = DecisionTrace(
            activeProfileID: currentSettings.activeProfileId,
            activeProfileName: currentSettings.profiles.first(where: { $0.id == currentSettings.activeProfileId })?.name,
            activationMode: currentSettings.profileActivationMode,
            matchedRuleID: matchedRule?.id,
            matchedRuleSummary: matchedRule?.summary,
            activePauseReasons: PauseReason.allCases.filter(activePauseReasons.contains),
            pendingDeferredCondition: pendingDeferredBreak?.condition,
            effectiveSettingsSource: effectiveSource,
            lastSyncWriter: lastSyncWriter
        )
    }

    private func syncDecisionTrace() {
        decisionTrace = DecisionTrace(
            activeProfileID: currentSettings.activeProfileId,
            activeProfileName: currentSettings.profiles.first(where: { $0.id == currentSettings.activeProfileId })?.name,
            activationMode: currentSettings.profileActivationMode,
            matchedRuleID: decisionTrace.matchedRuleID,
            matchedRuleSummary: decisionTrace.matchedRuleSummary,
            activePauseReasons: PauseReason.allCases.filter(activePauseReasons.contains),
            pendingDeferredCondition: pendingDeferredBreak?.condition,
            effectiveSettingsSource: decisionTrace.effectiveSettingsSource,
            lastSyncWriter: decisionTrace.lastSyncWriter
        )
    }

    public func snooze(minutes: Int? = nil, repository: BreakHistoryRepository? = nil, cloudSync: CloudKitSyncService? = nil) {
        let context = breakContextForPresentation()
        let breakTypeName = currentCustomBreakType?.name
        let mins = minutes ?? currentCustomBreakType?.snoozeMinutes ?? currentSettings.snoozeDurationMinutes
        guard mins > 0 else { return }
        let clamped = min(mins, 60)
        Observability.emit(category: "BreakScheduler", message: "snoozed \(clamped)min break=\(breakTypeName ?? "unknown")")
        if let repository, let context {
            let session = BreakSession(
                type: legacyBreakType(forCustomTypeID: context.customTypeID),
                scheduledAt: context.scheduledAt,
                status: .snoozed,
                breakTypeName: breakTypeName
            )
            repository.save(session)
            onSessionRecorded?(session, context.insightMetadata)
            if !currentSettings.localOnlyMode, let cloudSync {
                Task { await cloudSync.uploadSession(session) }
            }
        }
        activeBreakContext = nil
        pendingDeferredBreak = nil
        stop()
        guard let context else { return }
        nextBreak = (customTypeID: context.customTypeID, fireDate: Date().addingTimeInterval(Double(clamped) * 60))
        scheduleTimer(for: context.customTypeID, fireDate: nextBreak!.fireDate)
        persistFireDates()
    }

    public func skip(repository: BreakHistoryRepository, cloudSync: CloudKitSyncService? = nil) {
        let context = breakContextForPresentation()
        Observability.emit(category: "BreakScheduler", message: "skipped break=\(currentCustomBreakType?.name ?? "unknown")")
        guard let context else { return }
        let session = BreakSession(
            type: legacyBreakType(forCustomTypeID: context.customTypeID),
            scheduledAt: context.scheduledAt,
            status: .skipped,
            breakTypeName: currentCustomBreakType?.name
        )
        repository.save(session)
        onSessionRecorded?(session, context.insightMetadata)
        if !currentSettings.localOnlyMode, let cloudSync {
            Task { await cloudSync.uploadSession(session) }
        }
        activeBreakContext = nil
        pendingDeferredBreak = nil
        reschedule(with: currentSettings)
        syncDecisionTrace()
    }

    public func markCompleted(repository: BreakHistoryRepository, cloudSync: CloudKitSyncService? = nil) {
        let context = breakContextForPresentation()
        Observability.emit(category: "BreakScheduler", message: "completed break=\(currentCustomBreakType?.name ?? "unknown")")
        guard let context else { return }
        let session = BreakSession(
            type: legacyBreakType(forCustomTypeID: context.customTypeID),
            scheduledAt: context.scheduledAt,
            endedAt: Date(),
            status: .completed,
            breakTypeName: currentCustomBreakType?.name
        )
        repository.save(session)
        onSessionRecorded?(session, context.insightMetadata)
        if !currentSettings.localOnlyMode, let cloudSync {
            Task { await cloudSync.uploadSession(session) }
        }
        activeBreakContext = nil
        pendingDeferredBreak = nil
        reschedule(with: currentSettings)
        syncDecisionTrace()
    }

    public func pause(reason: PauseReason = .manual) {
        let inserted = activePauseReasons.insert(reason).inserted
        currentSettings.isPaused = true
        AppSettingsStore.save(currentSettings)
        guard inserted else { return }
        Observability.emit(category: "BreakScheduler", message: "paused reason=\(reason.rawValue)")
        stop()
        Self.clearPersistedFireDates()
        syncDecisionTrace()
    }

    public func resume(reason: PauseReason = .manual) {
        guard activePauseReasons.contains(reason) else { return }
        activePauseReasons.remove(reason)
        currentSettings.isPaused = !activePauseReasons.isEmpty
        AppSettingsStore.save(currentSettings)
        guard activePauseReasons.isEmpty else {
            let reasons = activePauseReasons.map { $0.rawValue }.sorted()
            Observability.emit(category: "BreakScheduler", message: "resume blocked by remaining reasons=\(reasons)")
            return
        }
        Observability.emit(category: "BreakScheduler", message: "resumed")
        start(settings: currentSettings)
        syncDecisionTrace()
    }

    public func pause() {
        pause(reason: .manual)
    }

    public func resume() {
        resume(reason: .manual)
    }

    public func reschedule(with settings: AppSettings) {
        stop()
        start(settings: settings)
        syncDecisionTrace()
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
        refreshNextBreak()
    }

    private func timerFired(customTypeID: UUID) {
        let scheduledAt = timers[customTypeID]?.fireDate ?? Date()
        timers[customTypeID]?.invalidate()
        timers.removeValue(forKey: customTypeID)
        guard let customType = currentSettings.customBreakTypes.first(where: { $0.id == customTypeID }) else {
            refreshNextBreak()
            persistFireDates()
            return
        }
        let context = ScheduledBreakContext(customTypeID: customTypeID, scheduledAt: scheduledAt)
        Observability.emit(category: "BreakScheduler", message: "timer fired: \(customType.name) (interval=\(customType.intervalMinutes)min)")
        if let onBreakTriggered {
            onBreakTriggered(customType, context)
        } else {
            beginBreakPresentation(context)
        }
        refreshNextBreak()
        persistFireDates()
    }

    private func refreshNextBreak() {
        let pending = timers.compactMap { (id, timer) -> (UUID, Date)? in
            (id, timer.fireDate)
        }.min(by: { $0.1 < $1.1 })
        if let (id, date) = pending {
            nextBreak = (customTypeID: id, fireDate: date)
        } else {
            nextBreak = nil
        }
    }

    private func customTypeName(for customTypeID: UUID) -> String? {
        currentSettings.customBreakTypes.first(where: { $0.id == customTypeID })?.name
    }

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

    private func persistFireDates() {
        var dict: [String: Date] = [:]
        for (id, timer) in timers {
            dict[id.uuidString] = timer.fireDate
        }
        UserDefaults.standard.set(dict, forKey: Self.persistedFireDatesKey)
    }

    private static func loadPersistedFireDates() -> [String: Date] {
        UserDefaults.standard.dictionary(forKey: persistedFireDatesKey) as? [String: Date] ?? [:]
    }

    private static func clearPersistedFireDates() {
        UserDefaults.standard.removeObject(forKey: persistedFireDatesKey)
    }
}
