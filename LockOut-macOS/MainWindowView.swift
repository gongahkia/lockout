import SwiftUI
import LockOutCore

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case schedule = "Schedule"
    case profiles = "Profiles" // #16
    case statistics = "Statistics"
    case settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: "house"
        case .schedule: "clock"
        case .profiles: "person.2"
        case .statistics: "chart.bar"
        case .settings: "gear"
        }
    }
}

struct MainWindowView: View {
    let repository: BreakHistoryRepository
    let cloudSync: CloudKitSyncService
    @EnvironmentObject var scheduler: BreakScheduler
    @State private var selected: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selected) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .navigationTitle("LockOut")
        } detail: {
            switch selected {
            case .dashboard: DashboardView(repository: repository)
            case .schedule: ScheduleView()
            case .profiles: ProfileEditorView() // #16
            case .statistics: StatisticsView(repository: repository, cloudSync: cloudSync)
            case .settings: SettingsView(repository: repository, cloudSync: cloudSync)
            case nil: EmptyView()
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .environmentObject(scheduler)
    }
}
