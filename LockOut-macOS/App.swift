import SwiftUI
import UserNotifications

@main
struct LockOutMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var tick = false
    var body: some Scene {
        WindowGroup("LockOut") {
            if let scheduler = appDelegate.scheduler,
               let repository = appDelegate.repository,
               let cloudSync = appDelegate.cloudSync {
                MainWindowView(repository: repository, cloudSync: cloudSync)
                    .environmentObject(scheduler)
            } else {
                ProgressView("Starting LockOut…")
                    .task {
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        tick.toggle() // force re-eval
                    }
                    .id(tick)
            }
        }
        .handlesExternalEvents(matching: ["main"])
    }
}
