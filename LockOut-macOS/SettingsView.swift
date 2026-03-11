import AppKit
import EventKit
import LockOutCore
import SwiftUI

struct SettingsView: View {
    let repository: BreakHistoryRepository
    let cloudSync: CloudKitSyncService

    @EnvironmentObject var scheduler: BreakScheduler

    @State private var manualBundleID = ""
    @State private var isRecordingHotkey = false
    @State private var syncRefresh = false

    private var appDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }
    private var managedSnapshot: ManagedSettingsSnapshot? { appDelegate?.managedSettings }

    var body: some View {
        ScrollView {
            Form {
                if let managedSnapshot {
                    managedBanner(snapshot: managedSnapshot)
                }

                Section("Break Settings") {
                    Stepper(
                        "Snooze duration: \(scheduler.currentSettings.snoozeDurationMinutes) min",
                        value: Binding(
                            get: { scheduler.currentSettings.snoozeDurationMinutes },
                            set: { scheduler.currentSettings.snoozeDurationMinutes = $0 }
                        ),
                        in: 1...30
                    )
                    .disabled(isLocked(.snoozeDurationMinutes))

                    Picker(
                        "Retention period",
                        selection: Binding(
                            get: { scheduler.currentSettings.historyRetentionDays },
                            set: {
                                scheduler.currentSettings.historyRetentionDays = $0
                                repository.pruneOldRecords(retentionDays: $0)
                            }
                        )
                    ) {
                        Text("30 days").tag(30)
                        Text("60 days").tag(60)
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                        Text("Unlimited").tag(0)
                    }
                }

                Section("Auto-Pause") {
                    Stepper(
                        "Idle threshold: \(scheduler.currentSettings.idleThresholdMinutes) min",
                        value: Binding(
                            get: { scheduler.currentSettings.idleThresholdMinutes },
                            set: { scheduler.currentSettings.idleThresholdMinutes = max(1, min(60, $0)) }
                        ),
                        in: 1...60
                    )
                    .disabled(isLocked(.idleThresholdMinutes))

                    Toggle(
                        "Pause during Focus Mode",
                        isOn: Binding(
                            get: { scheduler.currentSettings.pauseDuringFocus },
                            set: { scheduler.currentSettings.pauseDuringFocus = $0 }
                        )
                    )
                    .disabled(isLocked(.pauseDuringFocus))

                    Toggle(
                        "Pause during Calendar events",
                        isOn: Binding(
                            get: { scheduler.currentSettings.pauseDuringCalendarEvents },
                            set: { scheduler.currentSettings.pauseDuringCalendarEvents = $0 }
                        )
                    )
                    .disabled(isLocked(.pauseDuringCalendarEvents))

                    if scheduler.currentSettings.pauseDuringCalendarEvents {
                        Picker(
                            "Filter mode",
                            selection: Binding(
                                get: { scheduler.currentSettings.calendarFilterMode },
                                set: { scheduler.currentSettings.calendarFilterMode = $0 }
                            )
                        ) {
                            Text("All events").tag(CalendarFilterMode.all)
                            Text("Busy events only").tag(CalendarFilterMode.busyOnly)
                            Text("Selected calendars").tag(CalendarFilterMode.selected)
                        }
                        .disabled(isLocked(.calendarFilterMode))

                        if scheduler.currentSettings.calendarFilterMode == .selected {
                            CalendarSelectionSection(
                                selectedIDs: Binding(
                                    get: { scheduler.currentSettings.filteredCalendarIDs },
                                    set: { scheduler.currentSettings.filteredCalendarIDs = $0 }
                                ),
                                isDisabled: isLocked(.filteredCalendarIDs) || isLocked(.pauseDuringCalendarEvents)
                            )
                        }
                    }
                }

                Section("Workday") {
                    Picker(
                        "Start time",
                        selection: Binding(
                            get: { scheduler.currentSettings.workdayStartMinutes ?? -1 },
                            set: { scheduler.currentSettings.workdayStartMinutes = $0 >= 0 ? $0 : nil }
                        )
                    ) {
                        Text("Off").tag(-1)
                        ForEach(workdayTimeSlots, id: \.self) { mins in
                            Text(formatMinutes(mins)).tag(mins)
                        }
                    }
                    .disabled(isLocked(.workdayStartMinutes))

                    Picker(
                        "End time",
                        selection: Binding(
                            get: { scheduler.currentSettings.workdayEndMinutes ?? -1 },
                            set: { scheduler.currentSettings.workdayEndMinutes = $0 >= 0 ? $0 : nil }
                        )
                    ) {
                        Text("Off").tag(-1)
                        ForEach(workdayTimeSlots, id: \.self) { mins in
                            Text(formatMinutes(mins)).tag(mins)
                        }
                    }
                    .disabled(isLocked(.workdayEndMinutes))
                }

                Section("Policy") {
                    Picker(
                        "Active role",
                        selection: Binding(
                            get: { scheduler.currentSettings.activeRole },
                            set: { scheduler.currentSettings.activeRole = $0 }
                        )
                    ) {
                        ForEach(UserRole.allCases, id: \.self) { role in
                            Text(roleLabel(role)).tag(role)
                        }
                    }
                    .disabled(isLocked(.activeRole))

                    Picker(
                        "Break enforcement",
                        selection: Binding(
                            get: { scheduler.currentSettings.breakEnforcementMode },
                            set: { scheduler.currentSettings.breakEnforcementMode = $0 }
                        )
                    ) {
                        ForEach(BreakEnforcementMode.allCases, id: \.self) { mode in
                            Text(enforcementLabel(mode)).tag(mode)
                        }
                    }
                    .disabled(isLocked(.breakEnforcementMode))
                }

                Section("Appearance & Startup") {
                    Picker(
                        "Menu Bar Icon",
                        selection: Binding(
                            get: { scheduler.currentSettings.menuBarIconTheme },
                            set: {
                                scheduler.currentSettings.menuBarIconTheme = $0
                                appDelegate?.menuBarController?.updateStreak()
                            }
                        )
                    ) {
                        Text("Monochrome").tag(MenuBarIconTheme.monochrome)
                        Text("Color").tag(MenuBarIconTheme.color)
                        Text("Minimal").tag(MenuBarIconTheme.minimal)
                    }

                    Toggle(
                        "Launch at Login",
                        isOn: Binding(
                            get: { LaunchAtLoginService.isEnabled },
                            set: { $0 ? LaunchAtLoginService.enable() : LaunchAtLoginService.disable() }
                        )
                    )

                    Toggle(
                        "Local-only mode (disable cloud sync)",
                        isOn: Binding(
                            get: { scheduler.currentSettings.localOnlyMode },
                            set: { scheduler.currentSettings.localOnlyMode = $0 }
                        )
                    )
                    .disabled(isLocked(.localOnlyMode))
                }

                Section("Sync Status") {
                    LabeledContent("Mode", value: scheduler.currentSettings.localOnlyMode ? "Local only" : "Syncing")
                    LabeledContent("Last settings push", value: formatted(appDelegate?.settingsSync.lastPushDate))
                    LabeledContent("Last settings pull", value: formatted(appDelegate?.settingsSync.lastPullDate))
                    LabeledContent("Last history sync", value: formattedHistorySync)
                    LabeledContent("Pending uploads", value: "\(cloudSync.pendingUploadsCount)")
                    LabeledContent("Last settings writer", value: appDelegate?.settingsSync.lastSyncMetadata?.deviceName ?? "Unknown")
                    LabeledContent("Writer app version", value: appDelegate?.settingsSync.lastSyncMetadata?.appVersion ?? "Unknown")
                    if let err = appDelegate?.syncError ?? appDelegate?.settingsSync.lastErrorMessage {
                        LabeledContent("Latest sync error") {
                            Text(err).foregroundStyle(.red)
                        }
                    }
                    Button("Sync Now") {
                        Task {
                            await cloudSync.sync(repository: repository)
                            syncRefresh.toggle()
                        }
                    }
                    .disabled(scheduler.currentSettings.localOnlyMode)
                }

                Section("Notifications") {
                    Toggle(
                        "Weekly compliance summary",
                        isOn: Binding(
                            get: { scheduler.currentSettings.weeklyNotificationEnabled },
                            set: {
                                scheduler.currentSettings.weeklyNotificationEnabled = $0
                                appDelegate?.scheduleWeeklyComplianceNotification()
                            }
                        )
                    )

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
                    .background(
                        HotkeyRecorderHelper(isRecording: $isRecordingHotkey) { keyCode, flags in
                            scheduler.currentSettings.globalSnoozeHotkey = HotkeyDescriptor(keyCode: keyCode, modifierFlags: flags)
                            isRecordingHotkey = false
                        }
                    )

                    Stepper(
                        "Notification lead: \(scheduler.currentSettings.notificationLeadMinutes) min",
                        value: Binding(
                            get: { scheduler.currentSettings.notificationLeadMinutes },
                            set: { scheduler.currentSettings.notificationLeadMinutes = max(0, min(5, $0)) }
                        ),
                        in: 0...5
                    )
                    .disabled(isLocked(.notificationLeadMinutes))
                }

                Section("Settings Transfer") {
                    HStack {
                        Button("Export Settings") { exportSettings() }
                        Button("Import Settings") { importSettings() }
                        Spacer()
                    }
                }

                Section("Blocklist") {
                    blocklistSection
                }

                versionFooter
            }
        }
        .padding(24)
        .navigationTitle("Settings")
        .id(syncRefresh)
    }

    @ViewBuilder private func managedBanner(snapshot: ManagedSettingsSnapshot) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Managed by your organization", systemImage: "lock.shield")
                    .font(.headline)
                Text("Locked settings: \(snapshot.forcedKeys.map(\.displayName).sorted().joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder private var blocklistSection: some View {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        let blocklist = Binding(
            get: { scheduler.currentSettings.blockedBundleIDs },
            set: { scheduler.currentSettings.blockedBundleIDs = $0 }
        )

        VStack(alignment: .leading, spacing: 6) {
            Text("Block break overlay for these apps:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(running, id: \.processIdentifier) { app in
                let bid = app.bundleIdentifier ?? ""
                Toggle(
                    app.localizedName ?? bid,
                    isOn: Binding(
                        get: { blocklist.wrappedValue.contains(bid) },
                        set: { on in
                            if on {
                                if !blocklist.wrappedValue.contains(bid) { blocklist.wrappedValue.append(bid) }
                            } else {
                                blocklist.wrappedValue.removeAll { $0 == bid }
                            }
                        }
                    )
                )
                .disabled(isLocked(.blockedBundleIDs))
            }
            HStack {
                TextField("Manual bundle ID", text: $manualBundleID)
                Button("Add") {
                    let id = manualBundleID.trimmingCharacters(in: .whitespaces)
                    guard !id.isEmpty, !blocklist.wrappedValue.contains(id), isValidBundleID(id) else { return }
                    blocklist.wrappedValue.append(id)
                    manualBundleID = ""
                }
                .disabled(isLocked(.blockedBundleIDs))
            }
            ForEach(blocklist.wrappedValue, id: \.self) { id in
                HStack {
                    Text(id).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") { blocklist.wrappedValue.removeAll { $0 == id } }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                        .disabled(isLocked(.blockedBundleIDs))
                }
            }
        }
    }

    private var versionFooter: some View {
        Text("LockOut v\(AppVersion.current)")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }

    private var formattedHistorySync: String {
        let lastSync = cloudSync.lastSyncDate
        if lastSync == .distantPast { return "Never" }
        return formatted(lastSync)
    }

    private var hotkeyLabel: String {
        guard let hk = scheduler.currentSettings.globalSnoozeHotkey else { return "None" }
        var parts: [String] = []
        let mods = NSEvent.ModifierFlags(rawValue: UInt(hk.modifierFlags))
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.shift) { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeToString(hk.keyCode))
        return parts.joined()
    }

    private var workdayTimeSlots: [Int] {
        stride(from: 0, to: 1440, by: 30).map { $0 }
    }

    private func isLocked(_ key: ManagedSettingsKey) -> Bool {
        managedSnapshot?.isForced(key) ?? false
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

    private func formatMinutes(_ mins: Int) -> String {
        String(format: "%02d:%02d", mins / 60, mins % 60)
    }

    private func isValidBundleID(_ id: String) -> Bool {
        id.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let imported = try AppSettings.decodeValidatedImportJSON(data)
            let resolvedImport = appDelegate?.applyManagedSettings(to: imported) ?? imported
            let changes = diffSettingsKeys(old: scheduler.currentSettings, new: resolvedImport)
            let lockedKeys = managedSnapshot?.forcedKeys.map(\.displayName).sorted() ?? []
            let alert = NSAlert()
            alert.messageText = "Import Settings?"
            var pieces: [String] = []
            pieces.append(changes.isEmpty ? "No changes detected." : "Changed: \(changes.joined(separator: ", "))")
            if !lockedKeys.isEmpty {
                pieces.append("Managed keys will stay locked: \(lockedKeys.joined(separator: ", "))")
            }
            alert.informativeText = pieces.joined(separator: "\n")
            alert.addButton(withTitle: "Apply")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            scheduler.reschedule(with: resolvedImport)
        } catch {
            showImportError(error)
        }
    }

    private func showImportError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Import Failed"
        alert.informativeText = importErrorMessage(error)
        alert.runModal()
    }

    private func importErrorMessage(_ error: Error) -> String {
        if let decodingError = error as? DecodingError {
            return decodingErrorMessage(decodingError)
        }
        if let localized = error as? LocalizedError, let message = localized.errorDescription {
            return message
        }
        return error.localizedDescription
    }

    private func decodingErrorMessage(_ error: DecodingError) -> String {
        switch error {
        case let .typeMismatch(_, context):
            return "Type mismatch at \(codingPathString(context.codingPath)): \(context.debugDescription)"
        case let .valueNotFound(_, context):
            return "Missing value at \(codingPathString(context.codingPath)): \(context.debugDescription)"
        case let .keyNotFound(key, context):
            return "Missing key \(codingPathString(context.codingPath + [key]))."
        case let .dataCorrupted(context):
            return "Invalid value at \(codingPathString(context.codingPath)): \(context.debugDescription)"
        @unknown default:
            return "Unsupported JSON decoding error."
        }
    }

    private func codingPathString(_ codingPath: [CodingKey]) -> String {
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? "<root>" : path
    }

    private func diffSettingsKeys(old: AppSettings, new: AppSettings) -> [String] {
        guard let oldData = try? JSONEncoder().encode(old),
              let newData = try? JSONEncoder().encode(new),
              let oldDict = (try? JSONSerialization.jsonObject(with: oldData)) as? [String: Any],
              let newDict = (try? JSONSerialization.jsonObject(with: newData)) as? [String: Any] else { return [] }
        return oldDict.keys.filter { key in
            let oldJSON = oldDict[key].flatMap(stringifyJSONObject) ?? ""
            let newJSON = newDict[key].flatMap(stringifyJSONObject) ?? ""
            return oldJSON != newJSON
        }.sorted()
    }

    private func stringifyJSONObject(_ object: Any) -> String? {
        if JSONSerialization.isValidJSONObject(object),
           let data = try? JSONSerialization.data(withJSONObject: object) {
            return String(data: data, encoding: .utf8)
        }
        if let string = object as? String { return string }
        if let number = object as? NSNumber { return number.stringValue }
        return nil
    }

    private func exportSettings() {
        let lockedKeys = managedSnapshot?.forcedKeys.map(\.displayName).sorted() ?? []
        if !lockedKeys.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Export Managed Settings?"
            alert.informativeText = "This export will include managed values. Locked keys: \(lockedKeys.joined(separator: ", "))"
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        guard let data = try? JSONEncoder().encode(scheduler.currentSettings) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "lockout-settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func roleLabel(_ role: UserRole) -> String {
        switch role {
        case .developer: return "Developer"
        case .it_managed: return "IT Managed"
        case .health_conscious: return "Health Conscious"
        }
    }

    private func enforcementLabel(_ mode: BreakEnforcementMode) -> String {
        switch mode {
        case .reminder: return "Reminder"
        case .soft_lock: return "Soft Lock"
        case .hard_lock: return "Hard Lock"
        }
    }
}

private struct CalendarSelectionSection: View {
    @Binding var selectedIDs: [String]
    let isDisabled: Bool

    @State private var calendars: [EKCalendar] = []
    @State private var accessMessage = "Loading calendars…"

    private let store = EKEventStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected calendars")
                .font(.subheadline)
                .fontWeight(.semibold)
            if calendars.isEmpty {
                Text(accessMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Button("Select All") {
                        selectedIDs = calendars.map(\.calendarIdentifier)
                    }
                    Button("Clear All") {
                        selectedIDs = []
                    }
                }
                .disabled(isDisabled)

                ForEach(calendars, id: \.calendarIdentifier) { calendar in
                    Toggle(
                        "\(calendar.title) (\(calendar.source.title))",
                        isOn: Binding(
                            get: { selectedIDs.contains(calendar.calendarIdentifier) },
                            set: { selected in
                                if selected {
                                    if !selectedIDs.contains(calendar.calendarIdentifier) {
                                        selectedIDs.append(calendar.calendarIdentifier)
                                    }
                                } else {
                                    selectedIDs.removeAll { $0 == calendar.calendarIdentifier }
                                }
                            }
                        )
                    )
                    .disabled(isDisabled)
                }
            }
        }
        .task { await loadCalendars() }
    }

    private func loadCalendars() async {
        let granted = await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        guard granted else {
            accessMessage = "Calendar access is required to pick specific calendars."
            calendars = []
            return
        }
        let available = store.calendars(for: .event).sorted { lhs, rhs in
            if lhs.source.title == rhs.source.title { return lhs.title < rhs.title }
            return lhs.source.title < rhs.source.title
        }
        calendars = available
        accessMessage = available.isEmpty ? "No calendars are available on this Mac." : ""
    }
}

struct HotkeyRecorderHelper: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (Int, Int) -> Void

    final class Coordinator {
        var monitorToken: Any?

        deinit {
            if let monitorToken {
                NSEvent.removeMonitor(monitorToken)
            }
        }

        func removeMonitorIfNeeded() {
            if let monitorToken {
                NSEvent.removeMonitor(monitorToken)
                self.monitorToken = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isRecording {
            guard context.coordinator.monitorToken == nil else { return }
            context.coordinator.monitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let keyCode = Int(event.keyCode)
                let flags = Int(event.modifierFlags.rawValue)
                self.onCapture(keyCode, flags)
                self.isRecording = false
                context.coordinator.removeMonitorIfNeeded()
                return nil
            }
        } else {
            context.coordinator.removeMonitorIfNeeded()
        }
    }
}
