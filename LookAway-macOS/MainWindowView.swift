import SwiftUI
import LookAwayCore

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case schedule = "Schedule"
    case statistics = "Statistics"
    case settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: "house"
        case .schedule: "clock"
        case .statistics: "chart.bar"
        case .settings: "gear"
        }
    }
}

struct MainWindowView: View {
    @EnvironmentObject var scheduler: BreakScheduler
    @State private var selected: SidebarItem? = .dashboard
    private var appDelegate: AppDelegate { .shared }

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selected) { item in
                Label(item.rawValue, systemImage: item.icon)
            }
            .navigationTitle("LookAway")
        } detail: {
            switch selected {
            case .dashboard: DashboardView()
            case .schedule: ScheduleView()
            case .statistics: StatisticsView()
            case .settings: SettingsView()
            case nil: EmptyView()
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .environmentObject(scheduler)
    }
}
