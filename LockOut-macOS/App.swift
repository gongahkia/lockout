import SwiftUI
import UserNotifications

@main
struct LockOutMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup("LockOut") {
            if let scheduler = appDelegate.scheduler,
               let repository = appDelegate.repository,
               let cloudSync = appDelegate.cloudSync {
                MainWindowView(repository: repository, cloudSync: cloudSync)
                    .environmentObject(scheduler)
            } else {
                ProgressView("Starting LockOut…")
            }
        }
        .handlesExternalEvents(matching: ["main"])
    }
}
