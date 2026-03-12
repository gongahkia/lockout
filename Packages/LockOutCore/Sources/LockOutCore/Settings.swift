import Foundation

// MARK: - Menu bar icon theme
public enum MenuBarIconTheme: String, Codable, CaseIterable, Sendable {
    case monochrome, color, minimal
}

// MARK: - Calendar filter mode
public enum CalendarFilterMode: String, Codable, CaseIterable, Sendable {
    case all
    case busyOnly
    case selected
}

// MARK: - Break enforcement
public enum BreakEnforcementMode: String, Codable, CaseIterable, Sendable {
    case reminder
    case soft_lock
    case hard_lock
}

// MARK: - Pause reason
public enum PauseReason: String, Codable, CaseIterable, Hashable, Sendable {
    case manual
    case idle
    case focus
    case calendar
    case workday

    public var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .idle: return "Idle"
        case .focus: return "Focus Mode"
        case .calendar: return "Calendar"
        case .workday: return "Workday"
        }
    }
}

// MARK: - Role policy
public enum UserRole: String, Codable, CaseIterable, Sendable {
    case developer
    case it_managed
    case health_conscious
}

public struct RolePolicy: Codable, Equatable, Sendable {
    public var role: UserRole
    public var canBypassBreak: Bool

    public init(role: UserRole, canBypassBreak: Bool = true) {
        self.role = role
        self.canBypassBreak = canBypassBreak
    }

    public static var defaults: [RolePolicy] {
        [
            RolePolicy(role: .developer, canBypassBreak: true),
            RolePolicy(role: .it_managed, canBypassBreak: false),
            RolePolicy(role: .health_conscious, canBypassBreak: true),
        ]
    }
}

// MARK: - Hotkey
public struct HotkeyDescriptor: Codable, Equatable, Sendable {
    public var keyCode: Int
    public var modifierFlags: Int

    public init(keyCode: Int, modifierFlags: Int) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
    }
}

// MARK: - Break config
public struct BreakConfig: Codable, Equatable, Sendable {
    public var intervalMinutes: Int
    public var durationSeconds: Int
    public var isEnabled: Bool

    public init(intervalMinutes: Int, durationSeconds: Int, isEnabled: Bool) {
        self.intervalMinutes = intervalMinutes
        self.durationSeconds = durationSeconds
        self.isEnabled = isEnabled
    }
}

// MARK: - Profiles
public struct AppProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var customBreakTypes: [CustomBreakType]
    public var blockedBundleIDs: [String]
    public var idleThresholdMinutes: Int
    public var pauseDuringFocus: Bool
    public var pauseDuringCalendarEvents: Bool
    public var calendarFilterMode: CalendarFilterMode
    public var filteredCalendarIDs: [String]
    public var workdayStartMinutes: Int?
    public var workdayEndMinutes: Int?
    public var notificationLeadMinutes: Int
    public var breakEnforcementMode: BreakEnforcementMode
    public var snoozeDurationMinutes: Int

    public init(
        id: UUID = UUID(),
        name: String,
        customBreakTypes: [CustomBreakType] = AppSettings.defaultCustomBreakTypes,
        blockedBundleIDs: [String] = [],
        idleThresholdMinutes: Int = 5,
        pauseDuringFocus: Bool = false,
        pauseDuringCalendarEvents: Bool = false,
        calendarFilterMode: CalendarFilterMode = .all,
        filteredCalendarIDs: [String] = [],
        workdayStartMinutes: Int? = nil,
        workdayEndMinutes: Int? = nil,
        notificationLeadMinutes: Int = 1,
        breakEnforcementMode: BreakEnforcementMode = .reminder,
        snoozeDurationMinutes: Int = 5
    ) {
        self.id = id
        self.name = name
        self.customBreakTypes = customBreakTypes
        self.blockedBundleIDs = blockedBundleIDs
        self.idleThresholdMinutes = idleThresholdMinutes
        self.pauseDuringFocus = pauseDuringFocus
        self.pauseDuringCalendarEvents = pauseDuringCalendarEvents
        self.calendarFilterMode = calendarFilterMode
        self.filteredCalendarIDs = filteredCalendarIDs
        self.workdayStartMinutes = workdayStartMinutes
        self.workdayEndMinutes = workdayEndMinutes
        self.notificationLeadMinutes = notificationLeadMinutes
        self.breakEnforcementMode = breakEnforcementMode
        self.snoozeDurationMinutes = snoozeDurationMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        customBreakTypes = try c.decodeIfPresent([CustomBreakType].self, forKey: .customBreakTypes) ?? AppSettings.defaultCustomBreakTypes
        blockedBundleIDs = try c.decodeIfPresent([String].self, forKey: .blockedBundleIDs) ?? []
        idleThresholdMinutes = try c.decodeIfPresent(Int.self, forKey: .idleThresholdMinutes) ?? 5
        pauseDuringFocus = try c.decodeIfPresent(Bool.self, forKey: .pauseDuringFocus) ?? false
        pauseDuringCalendarEvents = try c.decodeIfPresent(Bool.self, forKey: .pauseDuringCalendarEvents) ?? false
        calendarFilterMode = try c.decodeIfPresent(CalendarFilterMode.self, forKey: .calendarFilterMode) ?? .all
        filteredCalendarIDs = try c.decodeIfPresent([String].self, forKey: .filteredCalendarIDs) ?? []
        workdayStartMinutes = try c.decodeIfPresent(Int.self, forKey: .workdayStartMinutes)
        workdayEndMinutes = try c.decodeIfPresent(Int.self, forKey: .workdayEndMinutes)
        notificationLeadMinutes = try c.decodeIfPresent(Int.self, forKey: .notificationLeadMinutes) ?? 1
        breakEnforcementMode = try c.decodeIfPresent(BreakEnforcementMode.self, forKey: .breakEnforcementMode) ?? .reminder
        snoozeDurationMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeDurationMinutes) ?? 5
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(customBreakTypes, forKey: .customBreakTypes)
        try c.encode(blockedBundleIDs, forKey: .blockedBundleIDs)
        try c.encode(idleThresholdMinutes, forKey: .idleThresholdMinutes)
        try c.encode(pauseDuringFocus, forKey: .pauseDuringFocus)
        try c.encode(pauseDuringCalendarEvents, forKey: .pauseDuringCalendarEvents)
        try c.encode(calendarFilterMode, forKey: .calendarFilterMode)
        try c.encode(filteredCalendarIDs, forKey: .filteredCalendarIDs)
        try c.encodeIfPresent(workdayStartMinutes, forKey: .workdayStartMinutes)
        try c.encodeIfPresent(workdayEndMinutes, forKey: .workdayEndMinutes)
        try c.encode(notificationLeadMinutes, forKey: .notificationLeadMinutes)
        try c.encode(breakEnforcementMode, forKey: .breakEnforcementMode)
        try c.encode(snoozeDurationMinutes, forKey: .snoozeDurationMinutes)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, customBreakTypes, blockedBundleIDs, idleThresholdMinutes
        case pauseDuringFocus, pauseDuringCalendarEvents, calendarFilterMode, filteredCalendarIDs
        case workdayStartMinutes, workdayEndMinutes, notificationLeadMinutes
        case breakEnforcementMode, snoozeDurationMinutes
    }
}

public enum AppSettingsImportValidationError: Error, LocalizedError, Equatable, Sendable {
    case outOfRange(field: String, expected: String, actual: String)
    case invalidValue(field: String, expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case let .outOfRange(field, expected, actual):
            return "Invalid value for \(field): expected \(expected), got \(actual)."
        case let .invalidValue(field, expected, actual):
            return "Invalid value for \(field): expected \(expected), got \(actual)."
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var eyeConfig: BreakConfig
    public var microConfig: BreakConfig
    public var longConfig: BreakConfig
    public var snoozeDurationMinutes: Int
    public var historyRetentionDays: Int
    public var isPaused: Bool
    public var customBreakTypes: [CustomBreakType]
    public var blockedBundleIDs: [String]
    public var idleThresholdMinutes: Int
    public var pauseDuringFocus: Bool
    public var pauseDuringCalendarEvents: Bool
    public var calendarFilterMode: CalendarFilterMode
    public var filteredCalendarIDs: [String]
    public var calendarMatchOptions: CalendarMatchOptions
    public var workdayStartMinutes: Int?
    public var workdayEndMinutes: Int?
    public var profiles: [AppProfile]
    public var autoProfileRules: [AutoProfileRule]
    public var activeProfileId: UUID?
    public var profileActivationMode: ProfileActivationMode
    public var notificationLeadMinutes: Int
    public var weeklyNotificationEnabled: Bool
    public var globalSnoozeHotkey: HotkeyDescriptor?
    public var menuBarIconTheme: MenuBarIconTheme
    public var breakEnforcementMode: BreakEnforcementMode
    public var rolePolicies: [RolePolicy]
    public var activeRole: UserRole
    public var localOnlyMode: Bool
    public var onboardingReviewState: OnboardingReviewState
    public var recoveryModeConfig: RecoveryModeConfig

    public init(
        eyeConfig: BreakConfig,
        microConfig: BreakConfig,
        longConfig: BreakConfig,
        snoozeDurationMinutes: Int = 5,
        historyRetentionDays: Int = 30,
        isPaused: Bool = false,
        customBreakTypes: [CustomBreakType] = AppSettings.defaultCustomBreakTypes,
        blockedBundleIDs: [String] = [],
        idleThresholdMinutes: Int = 5,
        pauseDuringFocus: Bool = false,
        pauseDuringCalendarEvents: Bool = false,
        calendarFilterMode: CalendarFilterMode = .all,
        filteredCalendarIDs: [String] = [],
        calendarMatchOptions: CalendarMatchOptions = CalendarMatchOptions(),
        workdayStartMinutes: Int? = nil,
        workdayEndMinutes: Int? = nil,
        profiles: [AppProfile] = [],
        autoProfileRules: [AutoProfileRule] = [],
        activeProfileId: UUID? = nil,
        profileActivationMode: ProfileActivationMode = .automatic,
        notificationLeadMinutes: Int = 1,
        weeklyNotificationEnabled: Bool = false,
        globalSnoozeHotkey: HotkeyDescriptor? = nil,
        menuBarIconTheme: MenuBarIconTheme = .monochrome,
        breakEnforcementMode: BreakEnforcementMode = .reminder,
        rolePolicies: [RolePolicy] = RolePolicy.defaults,
        activeRole: UserRole = .developer,
        localOnlyMode: Bool = false,
        onboardingReviewState: OnboardingReviewState = OnboardingReviewState(),
        recoveryModeConfig: RecoveryModeConfig = RecoveryModeConfig()
    ) {
        self.eyeConfig = eyeConfig
        self.microConfig = microConfig
        self.longConfig = longConfig
        self.snoozeDurationMinutes = snoozeDurationMinutes
        self.historyRetentionDays = historyRetentionDays
        self.isPaused = isPaused
        self.customBreakTypes = customBreakTypes
        self.blockedBundleIDs = blockedBundleIDs
        self.idleThresholdMinutes = max(1, min(60, idleThresholdMinutes))
        self.pauseDuringFocus = pauseDuringFocus
        self.pauseDuringCalendarEvents = pauseDuringCalendarEvents
        self.calendarFilterMode = calendarFilterMode
        self.filteredCalendarIDs = filteredCalendarIDs
        self.calendarMatchOptions = calendarMatchOptions
        self.workdayStartMinutes = workdayStartMinutes
        self.workdayEndMinutes = workdayEndMinutes
        self.profiles = profiles
        self.autoProfileRules = autoProfileRules
        self.activeProfileId = activeProfileId
        self.profileActivationMode = profileActivationMode
        self.notificationLeadMinutes = max(0, min(5, notificationLeadMinutes))
        self.weeklyNotificationEnabled = weeklyNotificationEnabled
        self.globalSnoozeHotkey = globalSnoozeHotkey
        self.menuBarIconTheme = menuBarIconTheme
        self.breakEnforcementMode = breakEnforcementMode
        self.rolePolicies = rolePolicies
        self.activeRole = activeRole
        self.localOnlyMode = localOnlyMode
        self.onboardingReviewState = onboardingReviewState
        self.recoveryModeConfig = recoveryModeConfig
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eyeConfig = try c.decode(BreakConfig.self, forKey: .eyeConfig)
        microConfig = try c.decode(BreakConfig.self, forKey: .microConfig)
        longConfig = try c.decode(BreakConfig.self, forKey: .longConfig)
        snoozeDurationMinutes = try c.decode(Int.self, forKey: .snoozeDurationMinutes)
        historyRetentionDays = try c.decode(Int.self, forKey: .historyRetentionDays)
        isPaused = try c.decode(Bool.self, forKey: .isPaused)
        customBreakTypes = try c.decode([CustomBreakType].self, forKey: .customBreakTypes)
        blockedBundleIDs = try c.decode([String].self, forKey: .blockedBundleIDs)
        idleThresholdMinutes = try c.decode(Int.self, forKey: .idleThresholdMinutes)
        pauseDuringFocus = try c.decode(Bool.self, forKey: .pauseDuringFocus)
        pauseDuringCalendarEvents = try c.decode(Bool.self, forKey: .pauseDuringCalendarEvents)
        calendarFilterMode = try c.decodeIfPresent(CalendarFilterMode.self, forKey: .calendarFilterMode) ?? .all
        filteredCalendarIDs = try c.decodeIfPresent([String].self, forKey: .filteredCalendarIDs) ?? []
        calendarMatchOptions = try c.decodeIfPresent(CalendarMatchOptions.self, forKey: .calendarMatchOptions) ?? CalendarMatchOptions()
        if let mins = try c.decodeIfPresent(Int.self, forKey: .workdayStartMinutes) {
            workdayStartMinutes = mins
        } else if let hour = try c.decodeIfPresent(Int.self, forKey: .workdayStartHourLegacy) {
            workdayStartMinutes = hour * 60
        } else {
            workdayStartMinutes = nil
        }
        if let mins = try c.decodeIfPresent(Int.self, forKey: .workdayEndMinutes) {
            workdayEndMinutes = mins
        } else if let hour = try c.decodeIfPresent(Int.self, forKey: .workdayEndHourLegacy) {
            workdayEndMinutes = hour * 60
        } else {
            workdayEndMinutes = nil
        }
        profiles = try c.decodeIfPresent([AppProfile].self, forKey: .profiles) ?? []
        autoProfileRules = try c.decodeIfPresent([AutoProfileRule].self, forKey: .autoProfileRules) ?? []
        activeProfileId = try c.decodeIfPresent(UUID.self, forKey: .activeProfileId)
        profileActivationMode = try c.decodeIfPresent(ProfileActivationMode.self, forKey: .profileActivationMode) ?? .automatic
        notificationLeadMinutes = try c.decode(Int.self, forKey: .notificationLeadMinutes)
        weeklyNotificationEnabled = try c.decode(Bool.self, forKey: .weeklyNotificationEnabled)
        globalSnoozeHotkey = try c.decodeIfPresent(HotkeyDescriptor.self, forKey: .globalSnoozeHotkey)
        menuBarIconTheme = try c.decode(MenuBarIconTheme.self, forKey: .menuBarIconTheme)
        breakEnforcementMode = try c.decode(BreakEnforcementMode.self, forKey: .breakEnforcementMode)
        rolePolicies = try c.decode([RolePolicy].self, forKey: .rolePolicies)
        activeRole = try c.decode(UserRole.self, forKey: .activeRole)
        localOnlyMode = try c.decode(Bool.self, forKey: .localOnlyMode)
        onboardingReviewState = try c.decodeIfPresent(OnboardingReviewState.self, forKey: .onboardingReviewState) ?? OnboardingReviewState()
        recoveryModeConfig = try c.decodeIfPresent(RecoveryModeConfig.self, forKey: .recoveryModeConfig) ?? RecoveryModeConfig()
    }

    private enum CodingKeys: String, CodingKey {
        case eyeConfig, microConfig, longConfig, snoozeDurationMinutes, historyRetentionDays
        case isPaused, customBreakTypes, blockedBundleIDs, idleThresholdMinutes
        case pauseDuringFocus, pauseDuringCalendarEvents, calendarFilterMode, filteredCalendarIDs, calendarMatchOptions
        case workdayStartMinutes, workdayEndMinutes
        case workdayStartHourLegacy = "workdayStartHour"
        case workdayEndHourLegacy = "workdayEndHour"
        case profiles, autoProfileRules, activeProfileId, profileActivationMode
        case notificationLeadMinutes, weeklyNotificationEnabled
        case globalSnoozeHotkey, menuBarIconTheme, breakEnforcementMode, rolePolicies, activeRole, localOnlyMode
        case onboardingReviewState, recoveryModeConfig
    }

    public var workdayStartHourDisplay: Int? { workdayStartMinutes.map { $0 / 60 } }
    public var workdayEndHourDisplay: Int? { workdayEndMinutes.map { $0 / 60 } }
    public var workdayStartMinuteOffset: Int { (workdayStartMinutes ?? 0) % 60 }
    public var workdayEndMinuteOffset: Int { (workdayEndMinutes ?? 0) % 60 }

    public func profileSnapshot(name: String, id: UUID = UUID()) -> AppProfile {
        AppProfile(
            id: id,
            name: name,
            customBreakTypes: customBreakTypes,
            blockedBundleIDs: blockedBundleIDs,
            idleThresholdMinutes: idleThresholdMinutes,
            pauseDuringFocus: pauseDuringFocus,
            pauseDuringCalendarEvents: pauseDuringCalendarEvents,
            calendarFilterMode: calendarFilterMode,
            filteredCalendarIDs: filteredCalendarIDs,
            workdayStartMinutes: workdayStartMinutes,
            workdayEndMinutes: workdayEndMinutes,
            notificationLeadMinutes: notificationLeadMinutes,
            breakEnforcementMode: breakEnforcementMode,
            snoozeDurationMinutes: snoozeDurationMinutes
        )
    }

    public mutating func apply(profile: AppProfile) {
        activeProfileId = profile.id
        customBreakTypes = profile.customBreakTypes
        blockedBundleIDs = profile.blockedBundleIDs
        idleThresholdMinutes = profile.idleThresholdMinutes
        pauseDuringFocus = profile.pauseDuringFocus
        pauseDuringCalendarEvents = profile.pauseDuringCalendarEvents
        calendarFilterMode = profile.calendarFilterMode
        filteredCalendarIDs = profile.filteredCalendarIDs
        workdayStartMinutes = profile.workdayStartMinutes
        workdayEndMinutes = profile.workdayEndMinutes
        notificationLeadMinutes = profile.notificationLeadMinutes
        breakEnforcementMode = profile.breakEnforcementMode
        snoozeDurationMinutes = profile.snoozeDurationMinutes
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(eyeConfig, forKey: .eyeConfig)
        try c.encode(microConfig, forKey: .microConfig)
        try c.encode(longConfig, forKey: .longConfig)
        try c.encode(snoozeDurationMinutes, forKey: .snoozeDurationMinutes)
        try c.encode(historyRetentionDays, forKey: .historyRetentionDays)
        try c.encode(isPaused, forKey: .isPaused)
        try c.encode(customBreakTypes, forKey: .customBreakTypes)
        try c.encode(blockedBundleIDs, forKey: .blockedBundleIDs)
        try c.encode(idleThresholdMinutes, forKey: .idleThresholdMinutes)
        try c.encode(pauseDuringFocus, forKey: .pauseDuringFocus)
        try c.encode(pauseDuringCalendarEvents, forKey: .pauseDuringCalendarEvents)
        try c.encode(calendarFilterMode, forKey: .calendarFilterMode)
        try c.encode(filteredCalendarIDs, forKey: .filteredCalendarIDs)
        try c.encode(calendarMatchOptions, forKey: .calendarMatchOptions)
        try c.encodeIfPresent(workdayStartMinutes, forKey: .workdayStartMinutes)
        try c.encodeIfPresent(workdayEndMinutes, forKey: .workdayEndMinutes)
        try c.encode(profiles, forKey: .profiles)
        try c.encode(autoProfileRules, forKey: .autoProfileRules)
        try c.encodeIfPresent(activeProfileId, forKey: .activeProfileId)
        try c.encode(profileActivationMode, forKey: .profileActivationMode)
        try c.encode(notificationLeadMinutes, forKey: .notificationLeadMinutes)
        try c.encode(weeklyNotificationEnabled, forKey: .weeklyNotificationEnabled)
        try c.encodeIfPresent(globalSnoozeHotkey, forKey: .globalSnoozeHotkey)
        try c.encode(menuBarIconTheme, forKey: .menuBarIconTheme)
        try c.encode(breakEnforcementMode, forKey: .breakEnforcementMode)
        try c.encode(rolePolicies, forKey: .rolePolicies)
        try c.encode(activeRole, forKey: .activeRole)
        try c.encode(localOnlyMode, forKey: .localOnlyMode)
        try c.encode(onboardingReviewState, forKey: .onboardingReviewState)
        try c.encode(recoveryModeConfig, forKey: .recoveryModeConfig)
    }

    public static var defaultCustomBreakTypes: [CustomBreakType] {
        [
            CustomBreakType(name: "Eye Break", intervalMinutes: 20, durationSeconds: 20, minDisplaySeconds: 5, tips: ["Look 20 feet away for 20 seconds"]),
            CustomBreakType(name: "Micro Break", intervalMinutes: 45, durationSeconds: 30, minDisplaySeconds: 5, tips: ["Relax and breathe"]),
            CustomBreakType(name: "Long Break", intervalMinutes: 90, durationSeconds: 900, minDisplaySeconds: 10, tips: ["Stand up and stretch"]),
        ]
    }

    public static var defaults: AppSettings {
        AppSettings(
            eyeConfig: BreakConfig(intervalMinutes: 20, durationSeconds: 20, isEnabled: true),
            microConfig: BreakConfig(intervalMinutes: 45, durationSeconds: 30, isEnabled: true),
            longConfig: BreakConfig(intervalMinutes: 90, durationSeconds: 900, isEnabled: true)
        )
    }

    public static func decodeValidatedImportJSON(_ data: Data) throws -> AppSettings {
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        try settings.validateForImport()
        return settings
    }

    public func validateForImport() throws {
        try Self.validateRange(snoozeDurationMinutes, field: "snoozeDurationMinutes", range: 1...30)
        try Self.validateRetention(historyRetentionDays)
        try Self.validateRange(idleThresholdMinutes, field: "idleThresholdMinutes", range: 1...60)
        try Self.validateRange(notificationLeadMinutes, field: "notificationLeadMinutes", range: 0...5)
        try Self.validateWorkdayMinutes(workdayStartMinutes, field: "workdayStartMinutes")
        try Self.validateWorkdayMinutes(workdayEndMinutes, field: "workdayEndMinutes")
        try Self.validateRange(calendarMatchOptions.minimumDurationMinutes, field: "calendarMatchOptions.minimumDurationMinutes", range: 0...240)
        try Self.validateRange(recoveryModeConfig.lookbackDays, field: "recoveryModeConfig.lookbackDays", range: 1...14)
        try Self.validateRange(recoveryModeConfig.skipThreshold, field: "recoveryModeConfig.skipThreshold", range: 1...20)
        try Self.validateRange(recoveryModeConfig.snoozeThreshold, field: "recoveryModeConfig.snoozeThreshold", range: 1...20)

        try Self.validateBreakConfig(eyeConfig, fieldPrefix: "eyeConfig")
        try Self.validateBreakConfig(microConfig, fieldPrefix: "microConfig")
        try Self.validateBreakConfig(longConfig, fieldPrefix: "longConfig")

        for (index, profile) in profiles.enumerated() {
            try Self.validateRange(profile.idleThresholdMinutes, field: "profiles[\(index)].idleThresholdMinutes", range: 1...60)
            try Self.validateRange(profile.notificationLeadMinutes, field: "profiles[\(index)].notificationLeadMinutes", range: 0...5)
            try Self.validateRange(profile.snoozeDurationMinutes, field: "profiles[\(index)].snoozeDurationMinutes", range: 1...30)
            try Self.validateWorkdayMinutes(profile.workdayStartMinutes, field: "profiles[\(index)].workdayStartMinutes")
            try Self.validateWorkdayMinutes(profile.workdayEndMinutes, field: "profiles[\(index)].workdayEndMinutes")
            for (breakIndex, breakType) in profile.customBreakTypes.enumerated() {
                try Self.validateCustomBreakType(breakType, index: breakIndex, prefix: "profiles[\(index)].customBreakTypes")
            }
        }

        for (index, rule) in autoProfileRules.enumerated() {
            try Self.validateRange(rule.priority, field: "autoProfileRules[\(index)].priority", range: 0...100)
            for trigger in rule.triggers {
                if case let .timeWindow(startMinutes, endMinutes) = trigger {
                    try Self.validateRange(startMinutes, field: "autoProfileRules[\(index)].timeWindow.startMinutes", range: 0...1439)
                    try Self.validateRange(endMinutes, field: "autoProfileRules[\(index)].timeWindow.endMinutes", range: 0...1439)
                }
            }
        }

        for (index, breakType) in customBreakTypes.enumerated() {
            try Self.validateCustomBreakType(breakType, index: index)
        }
    }

    public mutating func clampRetention() {
        let valid = [0, 30, 60, 90, 365]
        if !valid.contains(historyRetentionDays) { historyRetentionDays = 30 }
    }

    private static func validateBreakConfig(_ config: BreakConfig, fieldPrefix: String) throws {
        try validateRange(config.intervalMinutes, field: "\(fieldPrefix).intervalMinutes", range: 1...480)
        try validateRange(config.durationSeconds, field: "\(fieldPrefix).durationSeconds", range: 10...7200)
    }

    private static func validateCustomBreakType(_ breakType: CustomBreakType, index: Int, prefix: String = "customBreakTypes") throws {
        let fieldPrefix = "\(prefix)[\(index)]"
        try validateRange(breakType.intervalMinutes, field: "\(fieldPrefix).intervalMinutes", range: 1...480)
        try validateRange(breakType.durationSeconds, field: "\(fieldPrefix).durationSeconds", range: 10...7200)
        try validateRange(breakType.snoozeMinutes, field: "\(fieldPrefix).snoozeMinutes", range: 1...60)

        if breakType.minDisplaySeconds < 1 || breakType.minDisplaySeconds > breakType.durationSeconds {
            throw AppSettingsImportValidationError.outOfRange(
                field: "\(fieldPrefix).minDisplaySeconds",
                expected: "an integer in 1...\(breakType.durationSeconds)",
                actual: "\(breakType.minDisplaySeconds)"
            )
        }

        if !breakType.overlayOpacity.isFinite || !(0.1...1.0).contains(breakType.overlayOpacity) {
            throw AppSettingsImportValidationError.outOfRange(
                field: "\(fieldPrefix).overlayOpacity",
                expected: "a number in 0.1...1.0",
                actual: "\(breakType.overlayOpacity)"
            )
        }
    }

    private static func validateRange(_ value: Int, field: String, range: ClosedRange<Int>) throws {
        guard range.contains(value) else {
            throw AppSettingsImportValidationError.outOfRange(
                field: field,
                expected: "an integer in \(range.lowerBound)...\(range.upperBound)",
                actual: "\(value)"
            )
        }
    }

    private static func validateRetention(_ value: Int) throws {
        let valid = [0, 30, 60, 90, 365]
        guard valid.contains(value) else {
            throw AppSettingsImportValidationError.invalidValue(
                field: "historyRetentionDays",
                expected: "one of \(valid)",
                actual: "\(value)"
            )
        }
    }

    private static func validateWorkdayMinutes(_ value: Int?, field: String) throws {
        guard let value else { return }
        try validateRange(value, field: field, range: 0...1439)
    }
}
