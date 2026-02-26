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
            Section("Auto-Pause") {
                Stepper("Idle threshold: \(scheduler.currentSettings.idleThresholdMinutes) min",
                        value: Binding(
                            get: { scheduler.currentSettings.idleThresholdMinutes },
                            set: { scheduler.currentSettings.idleThresholdMinutes = max(1, min(60, $0)) }
                        ), in: 1...60)
                Toggle("Pause during Focus Mode", isOn: Binding(
                    get: { scheduler.currentSettings.pauseDuringFocus },
                    set: { scheduler.currentSettings.pauseDuringFocus = $0 }
                ))
                Toggle("Pause during Calendar events", isOn: Binding(
                    get: { scheduler.currentSettings.pauseDuringCalendarEvents },
                    set: { scheduler.currentSettings.pauseDuringCalendarEvents = $0 }
                ))
            }
            Section("Workday") {
                Picker("Start hour", selection: Binding(
                    get: { scheduler.currentSettings.workdayStartHour ?? -1 },
                    set: { scheduler.currentSettings.workdayStartHour = $0 >= 0 ? $0 : nil }
                )) {
                    Text("Off").tag(-1)
                    ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                Picker("End hour", selection: Binding(
                    get: { scheduler.currentSettings.workdayEndHour ?? -1 },
                    set: { scheduler.currentSettings.workdayEndHour = $0 >= 0 ? $0 : nil }
                )) {
                    Text("Off").tag(-1)
                    ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
            }
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
        Section("Blocklist") {
            blocklistSection
        }
        .padding(24)
        .navigationTitle("Settings")
    }

    @ViewBuilder private var blocklistSection: some View {
        let running = NSRunningApplication.runningApplications
            .filter { $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
        let blocklist = Binding(
            get: { scheduler.currentSettings.blockedBundleIDs },
            set: { scheduler.currentSettings.blockedBundleIDs = $0 }
        )
        VStack(alignment: .leading) {
            Text("Block break overlay for these apps:").font(.caption).foregroundStyle(.secondary)
            ForEach(running, id: \.processIdentifier) { app in
                let bid = app.bundleIdentifier ?? ""
                Toggle(app.localizedName ?? bid, isOn: Binding(
                    get: { blocklist.wrappedValue.contains(bid) },
                    set: { on in
                        if on { if !blocklist.wrappedValue.contains(bid) { blocklist.wrappedValue.append(bid) } }
                        else { blocklist.wrappedValue.removeAll { $0 == bid } }
                    }
                ))
            }
            HStack {
                TextField("Manual bundle ID", text: $manualBundleID)
                Button("Add") {
                    let id = manualBundleID.trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty, !blocklist.wrappedValue.contains(id) else { return }
                    blocklist.wrappedValue.append(id)
                    manualBundleID = ""
                }
            }
            ForEach(blocklist.wrappedValue, id: \.self) { id in
                HStack {
                    Text(id).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") { blocklist.wrappedValue.removeAll { $0 == id } }
                        .buttonStyle(.plain).foregroundStyle(.red)
                }
            }
        }
    }

    @State private var manualBundleID = ""

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: date)
    }
}
