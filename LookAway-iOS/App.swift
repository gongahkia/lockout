import SwiftUI
import SwiftData
import UserNotifications
import BackgroundTasks
import LookAwayCore

@main
struct LookAwayiOSApp: App {
    @UIApplicationDelegateAdaptor(iOSAppDelegate.self) var delegate
    @State private var showBreakSheet = false
    @State private var activeBreak: (BreakType, Int)?

    var body: some Scene {
        WindowGroup {
            Group {
                if !UserDefaults.standard.bool(forKey: "hasOnboarded") {
                    iOSOnboardingView()
                } else {
                    MainTabView()
                        .sheet(isPresented: $showBreakSheet) {
                            if let (type, dur) = activeBreak {
                                iOSBreakSheetView(breakType: type, duration: dur) { showBreakSheet = false }
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .breakFirediOS)) { note in
                            guard let info = note.userInfo,
                                  let t = info["type"] as? BreakType,
                                  let d = info["duration"] as? Int else { return }
                            activeBreak = (t, d)
                            showBreakSheet = true
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                            let s = iOSAppDelegate.shared.settings
                            NotificationScheduler.schedule(settings: s)
                        }
                }
            }
        }
        .modelContainer(iOSAppDelegate.shared.modelContainer)
    }
}

extension Notification.Name {
    static let breakFirediOS = Notification.Name("breakFirediOS")
}
