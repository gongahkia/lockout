import SwiftUI
import LockOutCore

struct MainTabView: View {
    private var delegate: iOSAppDelegate { .shared }

    var body: some View {
        TabView {
            iOSDashboardView()
                .tabItem { Label("Dashboard", systemImage: "house") }
            iOSScheduleView()
                .tabItem { Label("Schedule", systemImage: "clock") }
            iOSStatisticsView()
                .tabItem { Label("Statistics", systemImage: "chart.bar") }
            iOSSettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
