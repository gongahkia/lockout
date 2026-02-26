import Foundation

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

    public init(eyeConfig: BreakConfig, microConfig: BreakConfig, longConfig: BreakConfig,
                snoozeDurationMinutes: Int = 5, historyRetentionDays: Int = 7, isPaused: Bool = false,
                customBreakTypes: [CustomBreakType] = AppSettings.defaultCustomBreakTypes,
                blockedBundleIDs: [String] = [], idleThresholdMinutes: Int = 5, pauseDuringFocus: Bool = false,
                pauseDuringCalendarEvents: Bool = false, workdayStartHour: Int? = nil, workdayEndHour: Int? = nil) {
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

    public mutating func clampRetention() {
        historyRetentionDays = max(1, min(historyRetentionDays, 30))
    }
}
