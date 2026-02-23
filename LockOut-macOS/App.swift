import SwiftUI
import UserNotifications

@main
struct LockOutMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup("LockOut") {
            MainWindowView()
                .environmentObject(appDelegate.scheduler)
        }
        .handlesExternalEvents(matching: ["main"])
    }
}
