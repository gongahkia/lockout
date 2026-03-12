import Foundation

public enum ProfileActivationMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case manualHold = "manual_hold"

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic"
        case .manualHold: return "Manual Hold"
        }
    }
}

public enum CalendarAvailabilityMatch: String, Codable, CaseIterable, Sendable {
    case busy
    case free
    case tentative
    case unavailable

    public var displayName: String {
        rawValue.capitalized
    }
}

public struct CalendarMatchOptions: Codable, Equatable, Sendable {
    public var includedAvailabilities: [CalendarAvailabilityMatch]
    public var includeTitleKeywords: [String]
    public var excludeTitleKeywords: [String]
    public var minimumDurationMinutes: Int
    public var includeAllDayEvents: Bool

    public init(
        includedAvailabilities: [CalendarAvailabilityMatch] = [.busy, .unavailable],
        includeTitleKeywords: [String] = [],
        excludeTitleKeywords: [String] = [],
        minimumDurationMinutes: Int = 10,
        includeAllDayEvents: Bool = false
    ) {
        self.includedAvailabilities = Array(Set(includedAvailabilities)).sorted { $0.rawValue < $1.rawValue }
        self.includeTitleKeywords = includeTitleKeywords.map(Self.normalizeKeyword).filter { !$0.isEmpty }
        self.excludeTitleKeywords = excludeTitleKeywords.map(Self.normalizeKeyword).filter { !$0.isEmpty }
        self.minimumDurationMinutes = max(0, min(240, minimumDurationMinutes))
        self.includeAllDayEvents = includeAllDayEvents
    }

    public func matches(title: String, availability: CalendarAvailabilityMatch, isAllDay: Bool, durationMinutes: Int) -> Bool {
        guard includeAllDayEvents || !isAllDay else { return false }
        guard durationMinutes >= minimumDurationMinutes else { return false }
        guard includedAvailabilities.isEmpty || includedAvailabilities.contains(availability) else { return false }

        let normalizedTitle = title.lowercased()
        if !includeTitleKeywords.isEmpty, !includeTitleKeywords.contains(where: normalizedTitle.contains) {
            return false
        }
        if excludeTitleKeywords.contains(where: normalizedTitle.contains) {
            return false
        }
        return true
    }

    private static func normalizeKeyword(_ keyword: String) -> String {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct ProfileAutomationContext: Equatable, Sendable {
    public var minutesFromMidnight: Int
    public var hasMatchingCalendarEvent: Bool
    public var isFocusModeEnabled: Bool
    public var frontmostBundleID: String?
    public var externalDisplayConnected: Bool

    public init(
        minutesFromMidnight: Int,
        hasMatchingCalendarEvent: Bool,
        isFocusModeEnabled: Bool,
        frontmostBundleID: String?,
        externalDisplayConnected: Bool
    ) {
        self.minutesFromMidnight = minutesFromMidnight
        self.hasMatchingCalendarEvent = hasMatchingCalendarEvent
        self.isFocusModeEnabled = isFocusModeEnabled
        self.frontmostBundleID = frontmostBundleID
        self.externalDisplayConnected = externalDisplayConnected
    }
}

public enum ProfileTrigger: Equatable, Sendable {
    case timeWindow(startMinutes: Int, endMinutes: Int)
    case calendarMatch
    case focusMode
    case frontmostApp(bundleIDs: [String])
    case externalDisplayConnected

    public var displayName: String {
        switch self {
        case let .timeWindow(startMinutes, endMinutes):
            return "Time Window \(Self.format(minutes: startMinutes))-\(Self.format(minutes: endMinutes))"
        case .calendarMatch:
            return "Calendar Match"
        case .focusMode:
            return "Focus Mode"
        case let .frontmostApp(bundleIDs):
            return "App Match (\(bundleIDs.joined(separator: ", ")))"
        case .externalDisplayConnected:
            return "External Display"
        }
    }

    public func matches(_ context: ProfileAutomationContext) -> Bool {
        switch self {
        case let .timeWindow(startMinutes, endMinutes):
            if startMinutes == endMinutes { return true }
            if startMinutes < endMinutes {
                return context.minutesFromMidnight >= startMinutes && context.minutesFromMidnight < endMinutes
            }
            return context.minutesFromMidnight >= startMinutes || context.minutesFromMidnight < endMinutes
        case .calendarMatch:
            return context.hasMatchingCalendarEvent
        case .focusMode:
            return context.isFocusModeEnabled
        case let .frontmostApp(bundleIDs):
            guard let frontmostBundleID = context.frontmostBundleID else { return false }
            return bundleIDs.contains(frontmostBundleID)
        case .externalDisplayConnected:
            return context.externalDisplayConnected
        }
    }

    private static func format(minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

extension ProfileTrigger: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case startMinutes
        case endMinutes
        case bundleIDs
    }

    private enum Kind: String, Codable {
        case timeWindow
        case calendarMatch
        case focusMode
        case frontmostApp
        case externalDisplayConnected
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .timeWindow:
            self = .timeWindow(
                startMinutes: try container.decode(Int.self, forKey: .startMinutes),
                endMinutes: try container.decode(Int.self, forKey: .endMinutes)
            )
        case .calendarMatch:
            self = .calendarMatch
        case .focusMode:
            self = .focusMode
        case .frontmostApp:
            self = .frontmostApp(bundleIDs: try container.decode([String].self, forKey: .bundleIDs))
        case .externalDisplayConnected:
            self = .externalDisplayConnected
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .timeWindow(startMinutes, endMinutes):
            try container.encode(Kind.timeWindow, forKey: .kind)
            try container.encode(startMinutes, forKey: .startMinutes)
            try container.encode(endMinutes, forKey: .endMinutes)
        case .calendarMatch:
            try container.encode(Kind.calendarMatch, forKey: .kind)
        case .focusMode:
            try container.encode(Kind.focusMode, forKey: .kind)
        case let .frontmostApp(bundleIDs):
            try container.encode(Kind.frontmostApp, forKey: .kind)
            try container.encode(bundleIDs, forKey: .bundleIDs)
        case .externalDisplayConnected:
            try container.encode(Kind.externalDisplayConnected, forKey: .kind)
        }
    }
}

public struct AutoProfileRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var enabled: Bool
    public var priority: Int
    public var profileID: UUID
    public var triggers: [ProfileTrigger]

    public init(
        id: UUID = UUID(),
        enabled: Bool = true,
        priority: Int = 0,
        profileID: UUID,
        triggers: [ProfileTrigger] = []
    ) {
        self.id = id
        self.enabled = enabled
        self.priority = priority
        self.profileID = profileID
        self.triggers = triggers
    }

    public func matches(_ context: ProfileAutomationContext) -> Bool {
        enabled && triggers.contains { $0.matches(context) }
    }

    public var summary: String {
        guard !triggers.isEmpty else { return "No triggers" }
        return triggers.map(\.displayName).joined(separator: " OR ")
    }
}

public enum DeferredBreakCondition: Equatable, Sendable {
    case minutes(Int)
    case untilMeetingEnds(eventID: String?)
    case untilFullscreenEnds
    case untilAppChanges(bundleID: String)

    public var displayName: String {
        switch self {
        case let .minutes(minutes):
            return "In \(minutes) min"
        case .untilMeetingEnds:
            return "Until Meeting Ends"
        case .untilFullscreenEnds:
            return "Until Fullscreen Ends"
        case let .untilAppChanges(bundleID):
            return "Until App Changes (\(bundleID))"
        }
    }
}

extension DeferredBreakCondition: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case minutes
        case eventID
        case bundleID
    }

    private enum Kind: String, Codable {
        case minutes
        case untilMeetingEnds
        case untilFullscreenEnds
        case untilAppChanges
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .minutes:
            self = .minutes(try container.decode(Int.self, forKey: .minutes))
        case .untilMeetingEnds:
            self = .untilMeetingEnds(eventID: try container.decodeIfPresent(String.self, forKey: .eventID))
        case .untilFullscreenEnds:
            self = .untilFullscreenEnds
        case .untilAppChanges:
            self = .untilAppChanges(bundleID: try container.decode(String.self, forKey: .bundleID))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .minutes(minutes):
            try container.encode(Kind.minutes, forKey: .kind)
            try container.encode(minutes, forKey: .minutes)
        case let .untilMeetingEnds(eventID):
            try container.encode(Kind.untilMeetingEnds, forKey: .kind)
            try container.encodeIfPresent(eventID, forKey: .eventID)
        case .untilFullscreenEnds:
            try container.encode(Kind.untilFullscreenEnds, forKey: .kind)
        case let .untilAppChanges(bundleID):
            try container.encode(Kind.untilAppChanges, forKey: .kind)
            try container.encode(bundleID, forKey: .bundleID)
        }
    }
}

public struct DeferredBreakEvaluationContext: Equatable, Sendable {
    public var now: Date
    public var activeMeetingEventIDs: Set<String>
    public var isFullscreen: Bool
    public var frontmostBundleID: String?

    public init(
        now: Date = Date(),
        activeMeetingEventIDs: Set<String> = [],
        isFullscreen: Bool,
        frontmostBundleID: String?
    ) {
        self.now = now
        self.activeMeetingEventIDs = activeMeetingEventIDs
        self.isFullscreen = isFullscreen
        self.frontmostBundleID = frontmostBundleID
    }
}

public struct BreakInsightMetadata: Codable, Equatable, Sendable {
    public var activeProfileID: UUID?
    public var activeProfileName: String?
    public var calendarOverlap: Bool
    public var fullscreenOverlap: Bool
    public var frontmostBundleID: String?

    public init(
        activeProfileID: UUID? = nil,
        activeProfileName: String? = nil,
        calendarOverlap: Bool = false,
        fullscreenOverlap: Bool = false,
        frontmostBundleID: String? = nil
    ) {
        self.activeProfileID = activeProfileID
        self.activeProfileName = activeProfileName
        self.calendarOverlap = calendarOverlap
        self.fullscreenOverlap = fullscreenOverlap
        self.frontmostBundleID = frontmostBundleID
    }
}

public enum EffectiveSettingsSource: String, Codable, CaseIterable, Sendable {
    case local
    case synced
    case managed

    public var displayName: String {
        rawValue.capitalized
    }
}

public struct DecisionTrace: Codable, Equatable, Sendable {
    public var activeProfileID: UUID?
    public var activeProfileName: String?
    public var activationMode: ProfileActivationMode
    public var matchedRuleID: UUID?
    public var matchedRuleSummary: String?
    public var activePauseReasons: [PauseReason]
    public var pendingDeferredCondition: DeferredBreakCondition?
    public var effectiveSettingsSource: EffectiveSettingsSource
    public var lastSyncWriter: String?

    public init(
        activeProfileID: UUID? = nil,
        activeProfileName: String? = nil,
        activationMode: ProfileActivationMode = .automatic,
        matchedRuleID: UUID? = nil,
        matchedRuleSummary: String? = nil,
        activePauseReasons: [PauseReason] = [],
        pendingDeferredCondition: DeferredBreakCondition? = nil,
        effectiveSettingsSource: EffectiveSettingsSource = .local,
        lastSyncWriter: String? = nil
    ) {
        self.activeProfileID = activeProfileID
        self.activeProfileName = activeProfileName
        self.activationMode = activationMode
        self.matchedRuleID = matchedRuleID
        self.matchedRuleSummary = matchedRuleSummary
        self.activePauseReasons = activePauseReasons
        self.pendingDeferredCondition = pendingDeferredCondition
        self.effectiveSettingsSource = effectiveSettingsSource
        self.lastSyncWriter = lastSyncWriter
    }
}

public enum InsightCardType: String, Codable, CaseIterable, Sendable {
    case skipHotspot
    case deferHotspot
    case profileComparison
    case meetingCollision
    case streakRisk
    case bestDaypart
}

public struct InsightCard: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var type: InsightCardType
    public var title: String
    public var summary: String
    public var recommendation: String
    public var destination: String

    public init(
        id: UUID = UUID(),
        type: InsightCardType,
        title: String,
        summary: String,
        recommendation: String,
        destination: String
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.summary = summary
        self.recommendation = recommendation
        self.destination = destination
    }
}

public struct SyncDeviceRecord: Codable, Equatable, Identifiable, Sendable {
    public var deviceID: String
    public var deviceName: String
    public var lastSeenAt: Date
    public var lastSettingsWriteAt: Date?
    public var lastHistoryUploadAt: Date?
    public var appVersion: String

    public var id: String { deviceID }

    public init(
        deviceID: String,
        deviceName: String,
        lastSeenAt: Date = Date(),
        lastSettingsWriteAt: Date? = nil,
        lastHistoryUploadAt: Date? = nil,
        appVersion: String
    ) {
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.lastSeenAt = lastSeenAt
        self.lastSettingsWriteAt = lastSettingsWriteAt
        self.lastHistoryUploadAt = lastHistoryUploadAt
        self.appVersion = appVersion
    }
}

public struct OnboardingReviewState: Codable, Equatable, Sendable {
    public var firstLaunchDate: Date
    public var completedSessionCount: Int
    public var dismissalCount: Int
    public var lastPresentedAt: Date?

    public init(
        firstLaunchDate: Date = Date(),
        completedSessionCount: Int = 0,
        dismissalCount: Int = 0,
        lastPresentedAt: Date? = nil
    ) {
        self.firstLaunchDate = firstLaunchDate
        self.completedSessionCount = completedSessionCount
        self.dismissalCount = dismissalCount
        self.lastPresentedAt = lastPresentedAt
    }

    public func shouldPresent(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard dismissalCount == 0, lastPresentedAt == nil else { return false }
        let start = calendar.startOfDay(for: firstLaunchDate)
        let current = calendar.startOfDay(for: now)
        let dayCount = calendar.dateComponents([.day], from: start, to: current).day ?? 0
        return completedSessionCount >= 5 || dayCount >= 7
    }
}

public struct RecoveryModeConfig: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var skipThreshold: Int
    public var snoozeThreshold: Int
    public var lookbackDays: Int
    public var temporaryEnforcementMode: BreakEnforcementMode
    public var coachingCopy: String

    public init(
        isEnabled: Bool = false,
        skipThreshold: Int = 3,
        snoozeThreshold: Int = 5,
        lookbackDays: Int = 3,
        temporaryEnforcementMode: BreakEnforcementMode = .soft_lock,
        coachingCopy: String = "You are skipping or snoozing breaks frequently. Consider a stricter profile during heavy focus periods."
    ) {
        self.isEnabled = isEnabled
        self.skipThreshold = max(1, skipThreshold)
        self.snoozeThreshold = max(1, snoozeThreshold)
        self.lookbackDays = max(1, lookbackDays)
        self.temporaryEnforcementMode = temporaryEnforcementMode
        self.coachingCopy = coachingCopy
    }

    public func shouldSuggest(skipCount: Int, snoozeCount: Int) -> Bool {
        skipCount >= skipThreshold || snoozeCount >= snoozeThreshold
    }
}
