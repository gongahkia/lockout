import SwiftUI
import LockOutCore

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case schedule = "Schedule"
    case profiles = "Profiles" // #16
    case statistics = "Statistics"
    case settings = "Settings"
    var id: String { rawValue }
    var accessibilityID: String { "sidebar." + rawValue.lowercased() }
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
                    .accessibilityIdentifier(item.accessibilityID)
            }
            .accessibilityIdentifier("sidebar.list")
            .navigationTitle("LockOut")
        } detail: {
            switch selected {
            case .dashboard: DashboardView(repository: repository).accessibilityIdentifier("detail.dashboard")
            case .schedule: ScheduleView().accessibilityIdentifier("detail.schedule")
            case .profiles: ProfileEditorView().accessibilityIdentifier("detail.profiles") // #16
            case .statistics: StatisticsView(repository: repository, cloudSync: cloudSync).accessibilityIdentifier("detail.statistics")
            case .settings: SettingsView(repository: repository, cloudSync: cloudSync).accessibilityIdentifier("detail.settings")
            case nil: EmptyView()
            }
        }
        .frame(minWidth: 640, minHeight: 440)
        .environmentObject(scheduler)
    }
}
