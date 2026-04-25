import SwiftUI
import UserNotifications

@main
struct LockOutMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("LockOut") {
            AppBootstrapView(appDelegate: appDelegate)
        }
        .handlesExternalEvents(matching: ["main"])
    }
}

private struct AppBootstrapView: View {
    @ObservedObject var appDelegate: AppDelegate

    var body: some View {
        Group {
            if appDelegate.isReadyForUI, let repository = appDelegate.repository {
                MainWindowView(
                    repository: repository,
                    cloudSync: appDelegate.cloudSync
                )
                .environmentObject(appDelegate.scheduler)
            } else {
                ProgressView("Starting LockOut…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
