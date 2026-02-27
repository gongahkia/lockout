import Foundation

// MARK: - Menu bar icon theme
public enum MenuBarIconTheme: String, Codable, CaseIterable, Sendable {
    case monochrome, color, minimal
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

// MARK: - Profiles
public struct AppProfile: Codable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var customBreakTypes: [CustomBreakType]
    public var blockedBundleIDs: [String]
    public var idleThresholdMinutes: Int

    public init(id: UUID = UUID(), name: String, customBreakTypes: [CustomBreakType] = AppSettings.defaultCustomBreakTypes,
                blockedBundleIDs: [String] = [], idleThresholdMinutes: Int = 5) {
        self.id = id; self.name = name; self.customBreakTypes = customBreakTypes
        self.blockedBundleIDs = blockedBundleIDs; self.idleThresholdMinutes = idleThresholdMinutes
    }
}

public struct BreakConfig: Codable, Sendable {
    public var intervalMinutes: Int
    public var durationSeconds: Int
    public var isEnabled: Bool

    public init(intervalMinutes: Int, durationSeconds: Int, isEnabled: Bool) {
        self.intervalMinutes = intervalMinutes
        self.durationSeconds = durationSeconds
        self.isEnabled = isEnabled
    }
}

public struct AppSettings: Codable, Sendable {
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
    public var workdayStartHour: Int?   // nil = no automatic start
    public var workdayEndHour: Int?     // nil = no automatic end
    public var profiles: [AppProfile]
    public var activeProfileId: UUID?
    public var notificationLeadMinutes: Int  // 0-5, minutes before break to fire reminder
    public var weeklyNotificationEnabled: Bool
    public var globalSnoozeHotkey: HotkeyDescriptor?
    public var menuBarIconTheme: MenuBarIconTheme

    public init(eyeConfig: BreakConfig, microConfig: BreakConfig, longConfig: BreakConfig,
                snoozeDurationMinutes: Int = 5, historyRetentionDays: Int = 30, isPaused: Bool = false,
                customBreakTypes: [CustomBreakType] = AppSettings.defaultCustomBreakTypes,
                blockedBundleIDs: [String] = [], idleThresholdMinutes: Int = 5, pauseDuringFocus: Bool = false,
                pauseDuringCalendarEvents: Bool = false, workdayStartHour: Int? = nil, workdayEndHour: Int? = nil,
                profiles: [AppProfile] = [], activeProfileId: UUID? = nil,
                notificationLeadMinutes: Int = 1, weeklyNotificationEnabled: Bool = false,
                globalSnoozeHotkey: HotkeyDescriptor? = nil,
                menuBarIconTheme: MenuBarIconTheme = .monochrome) {
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
        self.workdayStartHour = workdayStartHour
        self.workdayEndHour = workdayEndHour
        self.profiles = profiles
        self.activeProfileId = activeProfileId
        self.notificationLeadMinutes = max(0, min(5, notificationLeadMinutes))
        self.weeklyNotificationEnabled = weeklyNotificationEnabled
        self.globalSnoozeHotkey = globalSnoozeHotkey
        self.menuBarIconTheme = menuBarIconTheme
    }

    public static var defaultCustomBreakTypes: [CustomBreakType] {[
        CustomBreakType(name: "Eye Break", intervalMinutes: 20, durationSeconds: 20, minDisplaySeconds: 5, tips: ["Look 20 feet away for 20 seconds"]),
        CustomBreakType(name: "Micro Break", intervalMinutes: 45, durationSeconds: 30, minDisplaySeconds: 5, tips: ["Relax and breathe"]),
        CustomBreakType(name: "Long Break", intervalMinutes: 90, durationSeconds: 900, minDisplaySeconds: 10, tips: ["Stand up and stretch"]),
    ]}

    public static var defaults: AppSettings {
        AppSettings(
            eyeConfig: BreakConfig(intervalMinutes: 20, durationSeconds: 20, isEnabled: true),
            microConfig: BreakConfig(intervalMinutes: 45, durationSeconds: 30, isEnabled: true),
            longConfig: BreakConfig(intervalMinutes: 90, durationSeconds: 900, isEnabled: true)
        )
    }

    // valid options: 30, 60, 90, 365, 0 (unlimited)
    public mutating func clampRetention() {
        let valid = [0, 30, 60, 90, 365]
        if !valid.contains(historyRetentionDays) { historyRetentionDays = 30 }
    }
}
