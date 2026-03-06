import Foundation

public enum SettingsChangeDetector {
    public enum FocusPauseAction: Equatable {
        case pause
        case resume
        case none
    }

    public static func workdayTimersNeedRefresh(previous: AppSettings?, current: AppSettings) -> Bool {
        previous?.workdayStartMinutes != current.workdayStartMinutes ||
        previous?.workdayEndMinutes != current.workdayEndMinutes
    }

    public static func calendarPollingPreferenceChanged(previous: AppSettings?, current: AppSettings) -> Bool {
        previous?.pauseDuringCalendarEvents != current.pauseDuringCalendarEvents ||
        previous?.calendarFilterMode != current.calendarFilterMode ||
        previous?.filteredCalendarIDs != current.filteredCalendarIDs
    }

    public static func weeklyNotificationPreferenceChanged(previous: AppSettings?, current: AppSettings) -> Bool {
        previous?.weeklyNotificationEnabled != current.weeklyNotificationEnabled
    }

    public static func focusPauseAction(previousFocusEnabled: Bool?, currentFocusEnabled: Bool, isPaused: Bool) -> FocusPauseAction {
        if previousFocusEnabled == currentFocusEnabled {
            return .none
        }
        if currentFocusEnabled {
            return isPaused ? .none : .pause
        }
        return isPaused ? .resume : .none
    }
}
