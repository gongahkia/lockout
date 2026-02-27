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
            Toggle("Weekly compliance summary", isOn: Binding(
                get: { scheduler.currentSettings.weeklyNotificationEnabled },
                set: {
                    scheduler.currentSettings.weeklyNotificationEnabled = $0
                    AppDelegate.shared.scheduleWeeklyComplianceNotification()
                }
            ))
            HStack {
                Text("Snooze hotkey: \(hotkeyLabel)")
                Spacer()
                Button(isRecordingHotkey ? "Press a key…" : "Record") {
                    isRecordingHotkey = true
                }
                if scheduler.currentSettings.globalSnoozeHotkey != nil {
                    Button("Clear") { scheduler.currentSettings.globalSnoozeHotkey = nil }
                }
            }
            .background(HotkeyRecorderHelper(isRecording: $isRecordingHotkey) { keyCode, flags in
                scheduler.currentSettings.globalSnoozeHotkey = HotkeyDescriptor(keyCode: keyCode, modifierFlags: flags)
                isRecordingHotkey = false
            })
            Stepper("Notification lead: \(scheduler.currentSettings.notificationLeadMinutes) min",
                    value: Binding(
                        get: { scheduler.currentSettings.notificationLeadMinutes },
                        set: { scheduler.currentSettings.notificationLeadMinutes = max(0, min(5, $0)) }
                    ), in: 0...5)
            HStack {
                Button("Export Settings") { exportSettings() }
                Button("Import Settings") { importSettings() }
                Spacer()
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
    @State private var isRecordingHotkey = false

    private var hotkeyLabel: String {
        guard let hk = scheduler.currentSettings.globalSnoozeHotkey else { return "None" }
        var parts: [String] = []
        let mods = NSEvent.ModifierFlags(rawValue: UInt(hk.modifierFlags))
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.shift) { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        let key = keyCodeToString(hk.keyCode)
        parts.append(key)
        return parts.joined()
    }

    private func keyCodeToString(_ code: Int) -> String {
        let map: [Int: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
            11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
            47: ".", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc",
        ]
        return map[code] ?? "?\(code)"
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url),
              let imported = try? JSONDecoder().decode(AppSettings.self, from: data) else { return }
        let changes = diffSettingsKeys(old: scheduler.currentSettings, new: imported)
        let alert = NSAlert()
        alert.messageText = "Import Settings?"
        alert.informativeText = changes.isEmpty ? "No changes detected." : "Changed: \(changes.joined(separator: ", "))"
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        scheduler.reschedule(with: imported)
    }

    private func diffSettingsKeys(old: AppSettings, new: AppSettings) -> [String] {
        guard let oldData = try? JSONEncoder().encode(old),
              let newData = try? JSONEncoder().encode(new),
              let oldDict = (try? JSONSerialization.jsonObject(with: oldData)) as? [String: Any],
              let newDict = (try? JSONSerialization.jsonObject(with: newData)) as? [String: Any] else { return [] }
        return oldDict.keys.filter { key in
            let o = oldDict[key].flatMap { try? JSONSerialization.data(withJSONObject: $0) }.map { String(data: $0, encoding: .utf8) ?? "" } ?? ""
            let n = newDict[key].flatMap { try? JSONSerialization.data(withJSONObject: $0) }.map { String(data: $0, encoding: .utf8) ?? "" } ?? ""
            return o != n
        }.sorted()
    }

    private func exportSettings() {
        guard let data = try? JSONEncoder().encode(scheduler.currentSettings) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "lockout-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    private func formatted(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short; f.timeStyle = .short
        return f.string(from: date)
    }
}

struct HotkeyRecorderHelper: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (Int, Int) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isRecording {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let keyCode = Int(event.keyCode)
                let flags = Int(event.modifierFlags.rawValue)
                self.onCapture(keyCode, flags)
                return nil // consume
            }
        }
    }
}
