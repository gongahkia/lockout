import SwiftUI
import UserNotifications

@main
struct LookAwayMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup("LookAway") {
            MainWindowView()
                .environmentObject(appDelegate.scheduler)
        }
        .handlesExternalEvents(matching: ["main"])
    }
}
