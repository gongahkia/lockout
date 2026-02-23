import SwiftUI
import LookAwayCore

struct iOSSettingsView: View {
    private var delegate: iOSAppDelegate { .shared }
    @State private var lastSynced: Date? = UserDefaults.standard.object(forKey: "ck_last_sync_date") as? Date
    @State private var notifGranted = UserDefaults.standard.bool(forKey: "notif_granted")

    var body: some View {
        NavigationView {
            Form {
                Stepper("Snooze: \(delegate.settings.snoozeDurationMinutes) min",
                        value: Binding(
                            get: { delegate.settings.snoozeDurationMinutes },
                            set: { delegate.settings.snoozeDurationMinutes = $0 }
                        ), in: 1...30)
                Stepper("History: \(delegate.settings.historyRetentionDays) days",
                        value: Binding(
                            get: { delegate.settings.historyRetentionDays },
                            set: {
                                delegate.settings.historyRetentionDays = $0
                                delegate.repository.pruneOldRecords(retentionDays: $0)
                            }
                        ), in: 1...30)
                HStack {
                    Text("iCloud: \(lastSynced.map { fmt($0) } ?? "Never")").foregroundStyle(.secondary)
                    Spacer()
                    Button("Sync Now") {
                        Task {
                            await delegate.cloudSync.sync(repository: delegate.repository)
                            lastSynced = UserDefaults.standard.object(forKey: "ck_last_sync_date") as? Date
                        }
                    }
                }
                if !notifGranted {
                    Button("Request Notification Permission") {
                        Task {
                            let g = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
                            UserDefaults.standard.set(g, forKey: "notif_granted")
                            notifGranted = g
                        }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func fmt(_ d: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short; return f.string(from: d)
    }
}
