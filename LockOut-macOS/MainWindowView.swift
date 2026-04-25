import LockOutCore
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case schedule = "Schedule"
    case profiles = "Profiles"
    case statistics = "Statistics"
    case settings = "Settings"

    var id: String { rawValue }

    var accessibilityID: String {
        "sidebar." + rawValue.lowercased()
    }

    var icon: String {
        switch self {
        case .dashboard:
            return "house"
        case .schedule:
            return "clock"
        case .profiles:
            return "person.2"
        case .statistics:
            return "chart.bar"
        case .settings:
            return "gear"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard:
            return "Next break and activity"
        case .schedule:
            return "Custom break cadence"
        case .profiles:
            return "Saved routines and rules"
        case .statistics:
            return "Compliance and sync status"
        case .settings:
            return "Policy, sync, and startup"
        }
    }
}

struct MainWindowView: View {
    let repository: BreakHistoryRepository
    let cloudSync: CloudKitSyncService

    @EnvironmentObject private var scheduler: BreakScheduler
    @State private var selected: SidebarItem? = .dashboard

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 12) {
                SidebarSummaryCard(
                    pauseStatus: scheduler.pauseStatusLabel,
                    profileName: activeProfileName,
                    usesCloudSync: !scheduler.currentSettings.localOnlyMode
                )

                List(SidebarItem.allCases, id: \.self, selection: $selected) { item in
                    SidebarRow(item: item)
                        .tag(item)
                        .accessibilityIdentifier(item.accessibilityID)
                }
                .accessibilityIdentifier("sidebar.list")
                .listStyle(.sidebar)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        } detail: {
            detailView(for: selected ?? .dashboard)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(LockOutSceneBackground())
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 960, minHeight: 640)
        .environmentObject(scheduler)
    }

    private var activeProfileName: String {
        guard let activeProfileID = scheduler.currentSettings.activeProfileId else {
            return "Automatic routine"
        }
        return scheduler.currentSettings.profiles.first(where: { $0.id == activeProfileID })?.name ?? "Custom routine"
    }

    @ViewBuilder
    private func detailView(for item: SidebarItem) -> some View {
        switch item {
        case .dashboard:
            DashboardView(repository: repository)
                .accessibilityIdentifier("detail.dashboard")
        case .schedule:
            ScheduleView()
                .accessibilityIdentifier("detail.schedule")
        case .profiles:
            ProfileEditorView()
                .accessibilityIdentifier("detail.profiles")
        case .statistics:
            StatisticsView(repository: repository, cloudSync: cloudSync)
                .accessibilityIdentifier("detail.statistics")
        case .settings:
            SettingsView(repository: repository, cloudSync: cloudSync)
                .accessibilityIdentifier("detail.settings")
        }
    }
}

private struct SidebarSummaryCard: View {
    let pauseStatus: String?
    let profileName: String
    let usesCloudSync: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(LockOutPalette.sky, in: RoundedRectangle(cornerRadius: LockOutLayout.iconCornerRadius))

                VStack(alignment: .leading, spacing: 2) {
                    Text("LockOut")
                        .font(.headline)

                    Text("Menu bar recovery for long screen sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                LockOutStatusBadge(pauseStatus ?? "Running", tone: pauseStatus == nil ? .success : .warning)
                LockOutStatusBadge(usesCloudSync ? "Cloud Sync" : "Local Only", tone: usesCloudSync ? .info : .neutral)
            }

            Text(profileName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LockOutPalette.slate)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: LockOutLayout.cornerRadius)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: LockOutLayout.cornerRadius)
                        .strokeBorder(LockOutPalette.separator.opacity(0.35), lineWidth: 1)
                )
        )
    }
}

private struct SidebarRow: View {
    let item: SidebarItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.rawValue)
                    .lineLimit(1)

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}
