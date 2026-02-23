import SwiftUI
import LockOutCore

struct SettingsView: View {
    @EnvironmentObject var scheduler: BreakScheduler
    @State private var lastSynced: Date? = UserDefaults.standard.object(forKey: "ck_last_sync_date") as? Date

    private var repo: BreakHistoryRepository { AppDelegate.shared.repository }
    private var cloudSync: CloudKitSyncService { AppDelegate.shared.cloudSync }

    var body: some View {
        Form {
            Stepper("Snooze duration: \(scheduler.currentSettings.snoozeDurationMinutes) min",
                    value: Binding(
                        get: { scheduler.currentSettings.snoozeDurationMinutes },
                        set: { scheduler.currentSettings.snoozeDurationMinutes = $0 }
                    ), in: 1...30)
            Stepper("Keep history for \(scheduler.currentSettings.historyRetentionDays) days",
                    value: Binding(
                        get: { scheduler.currentSettings.historyRetentionDays },
                        set: {
                            scheduler.currentSettings.historyRetentionDays = $0
                            repo.pruneOldRecords(retentionDays: $0)
                        }
                    ), in: 1...30)
            Toggle("Launch at Login", isOn: Binding(
                get: { LaunchAtLoginService.isEnabled },
                set: { $0 ? LaunchAtLoginService.enable() : LaunchAtLoginService.disable() }
            ))
            HStack {
                Text("Last synced: \(lastSynced.map { formatted($0) } ?? "Never")")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Sync Now") {
                    Task {
                        await cloudSync.sync(repository: repo)
                        lastSynced = UserDefaults.standard.object(forKey: "ck_last_sync_date") as? Date
                    }
                }
            }
            if let err = AppDelegate.shared.syncError {
                Text(err).foregroundStyle(.red).font(.caption)
            }
        }
        .padding(24)
        .navigationTitle("Settings")
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: date)
    }
}
