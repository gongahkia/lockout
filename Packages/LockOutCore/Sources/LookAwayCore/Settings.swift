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

    public init(eyeConfig: BreakConfig, microConfig: BreakConfig, longConfig: BreakConfig,
                snoozeDurationMinutes: Int = 5, historyRetentionDays: Int = 7, isPaused: Bool = false) {
        self.eyeConfig = eyeConfig
        self.microConfig = microConfig
        self.longConfig = longConfig
        self.snoozeDurationMinutes = snoozeDurationMinutes
        self.historyRetentionDays = historyRetentionDays
        self.isPaused = isPaused
    }

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
