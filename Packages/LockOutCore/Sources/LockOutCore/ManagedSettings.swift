import Foundation

public enum ManagedSettingsKey: String, Codable, CaseIterable, Hashable, Sendable {
    case customBreakTypes
    case snoozeDurationMinutes
    case idleThresholdMinutes
    case pauseDuringFocus
    case pauseDuringCalendarEvents
    case calendarFilterMode
    case filteredCalendarIDs
    case workdayStartMinutes
    case workdayEndMinutes
    case notificationLeadMinutes
    case breakEnforcementMode
    case blockedBundleIDs
    case rolePolicies
    case activeRole
    case localOnlyMode

    public var displayName: String {
        switch self {
        case .customBreakTypes: return "Break Types"
        case .snoozeDurationMinutes: return "Snooze Duration"
        case .idleThresholdMinutes: return "Idle Threshold"
        case .pauseDuringFocus: return "Pause During Focus Mode"
        case .pauseDuringCalendarEvents: return "Pause During Calendar Events"
        case .calendarFilterMode: return "Calendar Filter Mode"
        case .filteredCalendarIDs: return "Selected Calendars"
        case .workdayStartMinutes: return "Workday Start"
        case .workdayEndMinutes: return "Workday End"
        case .notificationLeadMinutes: return "Notification Lead"
        case .breakEnforcementMode: return "Break Enforcement"
        case .blockedBundleIDs: return "Blocked Apps"
        case .rolePolicies: return "Role Policies"
        case .activeRole: return "Active Role"
        case .localOnlyMode: return "Local-only Mode"
        }
    }
}

public struct ManagedSettingsMetadata: Codable, Equatable, Sendable {
    public var source: String
    public var retrievedAt: Date

    public init(source: String = "managed_preferences", retrievedAt: Date = Date()) {
        self.source = source
        self.retrievedAt = retrievedAt
    }
}

public struct ManagedSettingsSnapshot: Codable, Equatable, Sendable {
    public var settings: AppSettings
    public var forcedKeys: Set<ManagedSettingsKey>
    public var metadata: ManagedSettingsMetadata

    public init(settings: AppSettings, forcedKeys: Set<ManagedSettingsKey>, metadata: ManagedSettingsMetadata = ManagedSettingsMetadata()) {
        self.settings = settings
        self.forcedKeys = forcedKeys
        self.metadata = metadata
    }

    public func isForced(_ key: ManagedSettingsKey) -> Bool {
        forcedKeys.contains(key)
    }
}

public enum ManagedSettingsResolver {
    public static func load(from defaults: UserDefaults = .standard) -> ManagedSettingsSnapshot? {
        var settings = AppSettings.defaults
        var forcedKeys = Set<ManagedSettingsKey>()

        for key in ManagedSettingsKey.allCases where defaults.objectIsForced(forKey: key.rawValue) {
            guard applyManagedValue(for: key, from: defaults, to: &settings) else { continue }
            forcedKeys.insert(key)
        }

        guard !forcedKeys.isEmpty else { return nil }
        return ManagedSettingsSnapshot(settings: settings, forcedKeys: forcedKeys)
    }

    public static func apply(_ snapshot: ManagedSettingsSnapshot?, to settings: AppSettings) -> AppSettings {
        guard let snapshot else { return settings }
        var resolved = settings
        for key in snapshot.forcedKeys {
            applyManagedValue(key, from: snapshot.settings, to: &resolved)
        }
        return resolved
    }

    public static func resolve(local: AppSettings?, remote: AppSettings?, managed: ManagedSettingsSnapshot?) -> AppSettings {
        let base = local ?? remote ?? .defaults
        let merged = remote.map { SettingsSyncService.merge(local: base, remote: $0) } ?? base
        return apply(managed, to: merged)
    }

    private static func applyManagedValue(_ key: ManagedSettingsKey, from source: AppSettings, to target: inout AppSettings) {
        switch key {
        case .customBreakTypes: target.customBreakTypes = source.customBreakTypes
        case .snoozeDurationMinutes: target.snoozeDurationMinutes = source.snoozeDurationMinutes
        case .idleThresholdMinutes: target.idleThresholdMinutes = source.idleThresholdMinutes
        case .pauseDuringFocus: target.pauseDuringFocus = source.pauseDuringFocus
        case .pauseDuringCalendarEvents: target.pauseDuringCalendarEvents = source.pauseDuringCalendarEvents
        case .calendarFilterMode: target.calendarFilterMode = source.calendarFilterMode
        case .filteredCalendarIDs: target.filteredCalendarIDs = source.filteredCalendarIDs
        case .workdayStartMinutes: target.workdayStartMinutes = source.workdayStartMinutes
        case .workdayEndMinutes: target.workdayEndMinutes = source.workdayEndMinutes
        case .notificationLeadMinutes: target.notificationLeadMinutes = source.notificationLeadMinutes
        case .breakEnforcementMode: target.breakEnforcementMode = source.breakEnforcementMode
        case .blockedBundleIDs: target.blockedBundleIDs = source.blockedBundleIDs
        case .rolePolicies: target.rolePolicies = source.rolePolicies
        case .activeRole: target.activeRole = source.activeRole
        case .localOnlyMode: target.localOnlyMode = source.localOnlyMode
        }
    }

    private static func applyManagedValue(for key: ManagedSettingsKey, from defaults: UserDefaults, to settings: inout AppSettings) -> Bool {
        switch key {
        case .customBreakTypes:
            guard let value: [CustomBreakType] = decodeManagedValue(defaults.object(forKey: key.rawValue)) else { return false }
            settings.customBreakTypes = value
        case .snoozeDurationMinutes:
            guard let value = decodeInt(defaults.object(forKey: key.rawValue)) else { return false }
            settings.snoozeDurationMinutes = value
        case .idleThresholdMinutes:
            guard let value = decodeInt(defaults.object(forKey: key.rawValue)) else { return false }
            settings.idleThresholdMinutes = value
        case .pauseDuringFocus:
            guard let value = decodeBool(defaults.object(forKey: key.rawValue)) else { return false }
            settings.pauseDuringFocus = value
        case .pauseDuringCalendarEvents:
            guard let value = decodeBool(defaults.object(forKey: key.rawValue)) else { return false }
            settings.pauseDuringCalendarEvents = value
        case .calendarFilterMode:
            guard let value: CalendarFilterMode = decodeManagedValue(defaults.object(forKey: key.rawValue)) else { return false }
            settings.calendarFilterMode = value
        case .filteredCalendarIDs:
            guard let value = defaults.stringArray(forKey: key.rawValue) ?? decodeManagedValue(defaults.object(forKey: key.rawValue)) as [String]? else { return false }
            settings.filteredCalendarIDs = value
        case .workdayStartMinutes:
            settings.workdayStartMinutes = decodeInt(defaults.object(forKey: key.rawValue))
        case .workdayEndMinutes:
            settings.workdayEndMinutes = decodeInt(defaults.object(forKey: key.rawValue))
        case .notificationLeadMinutes:
            guard let value = decodeInt(defaults.object(forKey: key.rawValue)) else { return false }
            settings.notificationLeadMinutes = value
        case .breakEnforcementMode:
            guard let value: BreakEnforcementMode = decodeManagedValue(defaults.object(forKey: key.rawValue)) else { return false }
            settings.breakEnforcementMode = value
        case .blockedBundleIDs:
            guard let value = defaults.stringArray(forKey: key.rawValue) ?? decodeManagedValue(defaults.object(forKey: key.rawValue)) as [String]? else { return false }
            settings.blockedBundleIDs = value
        case .rolePolicies:
            guard let value: [RolePolicy] = decodeManagedValue(defaults.object(forKey: key.rawValue)) else { return false }
            settings.rolePolicies = value
        case .activeRole:
            guard let value: UserRole = decodeManagedValue(defaults.object(forKey: key.rawValue)) else { return false }
            settings.activeRole = value
        case .localOnlyMode:
            guard let value = decodeBool(defaults.object(forKey: key.rawValue)) else { return false }
            settings.localOnlyMode = value
        }
        return true
    }

    private static func decodeInt(_ object: Any?) -> Int? {
        switch object {
        case let int as Int: return int
        case let number as NSNumber: return number.intValue
        case let string as String: return Int(string)
        default: return nil
        }
    }

    private static func decodeBool(_ object: Any?) -> Bool? {
        switch object {
        case let bool as Bool: return bool
        case let number as NSNumber: return number.boolValue
        case let string as String:
            return (string as NSString).boolValue
        default:
            return nil
        }
    }

    private static func decodeManagedValue<Value: Decodable>(_ object: Any?) -> Value? {
        guard let object else { return nil }
        if let data = object as? Data {
            return try? JSONDecoder().decode(Value.self, from: data)
        }
        if JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object) {
            return try? JSONDecoder().decode(Value.self, from: data)
        }
        if let string = object as? String {
            return try? JSONDecoder().decode(Value.self, from: Data("\"\(string)\"".utf8))
        }
        if let number = object as? NSNumber {
            return try? JSONDecoder().decode(Value.self, from: Data(number.stringValue.utf8))
        }
        if let bool = object as? Bool {
            return try? JSONDecoder().decode(Value.self, from: Data((bool ? "true" : "false").utf8))
        }
        return nil
    }
}
