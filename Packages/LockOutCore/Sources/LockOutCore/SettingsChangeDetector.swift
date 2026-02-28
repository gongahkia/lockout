import Foundation

public enum SettingsChangeDetector {
    public static func workdayTimersNeedRefresh(previous: AppSettings?, current: AppSettings) -> Bool {
        previous?.workdayStartHour != current.workdayStartHour ||
        previous?.workdayEndHour != current.workdayEndHour
    }

    public static func calendarPollingPreferenceChanged(previous: AppSettings?, current: AppSettings) -> Bool {
        previous?.pauseDuringCalendarEvents != current.pauseDuringCalendarEvents
    }
}
