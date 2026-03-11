import AppKit
import EventKit
import LockOutCore
import SwiftUI

struct SettingsView: View {
    let repository: BreakHistoryRepository
    let cloudSync: CloudKitSyncService

    @EnvironmentObject var scheduler: BreakScheduler

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
                        ForEach(SettingsUIHelpers.workdayTimeSlots, id: \.self) { mins in
                            Text(SettingsUIHelpers.formatMinutes(mins)).tag(mins)
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
                        ForEach(SettingsUIHelpers.workdayTimeSlots, id: \.self) { mins in
                            Text(SettingsUIHelpers.formatMinutes(mins)).tag(mins)
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
        .accessibilityIdentifier("settings.view")
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
        BundleIDSelectionSection(
            selectedBundleIDs: Binding(
            get: { scheduler.currentSettings.blockedBundleIDs },
            set: { scheduler.currentSettings.blockedBundleIDs = $0 }
            ),
            isDisabled: isLocked(.blockedBundleIDs),
            caption: "Block break overlay for these apps:"
        )
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
            let alert = NSAlert()
            alert.messageText = "Import Settings?"
            alert.informativeText = importPreviewMessage(imported: imported, resolvedImport: resolvedImport)
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
        if let preview = exportPreviewMessage() {
            let alert = NSAlert()
            alert.messageText = "Export Managed Settings?"
            alert.informativeText = preview
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

    private func importPreviewMessage(imported: AppSettings, resolvedImport: AppSettings) -> String {
        let editableChanges = previewDiffs(from: scheduler.currentSettings, to: resolvedImport)
        let lockedChanges = lockedImportDiffs(imported: imported, resolvedImport: resolvedImport)
        var sections: [String] = []

        if editableChanges.isEmpty {
            sections.append("No editable changes detected.")
        } else {
            sections.append("Will change:")
            sections.append(contentsOf: previewLines(for: editableChanges))
        }

        if !lockedChanges.isEmpty {
            sections.append("")
            sections.append("Managed, ignored from file:")
            sections.append(contentsOf: previewLines(for: lockedChanges, prefix: "Requested"))
        }

        return sections.joined(separator: "\n")
    }

    private func exportPreviewMessage() -> String? {
        guard let managedSnapshot, !managedSnapshot.forcedKeys.isEmpty else { return nil }
        let entries = managedSnapshot.forcedKeys.sorted { $0.displayName < $1.displayName }.map {
            "• \($0.displayName) = \(settingsValueSummary(for: $0.rawValue, in: scheduler.currentSettings))"
        }
        return (["This export includes values enforced by managed preferences.", "", "Locked fields:"]
            + limitPreviewLines(entries))
            .joined(separator: "\n")
    }

    private func previewDiffs(from current: AppSettings, to updated: AppSettings) -> [SettingsPreviewDiff] {
        previewableKeys.compactMap { key in
            guard settingsRawValueString(for: key, in: current) != settingsRawValueString(for: key, in: updated) else { return nil }
            return SettingsPreviewDiff(
                label: settingsLabel(for: key),
                fromValue: settingsValueSummary(for: key, in: current),
                toValue: settingsValueSummary(for: key, in: updated)
            )
        }
    }

    private func lockedImportDiffs(imported: AppSettings, resolvedImport: AppSettings) -> [SettingsPreviewDiff] {
        guard let managedSnapshot else { return [] }
        return managedSnapshot.forcedKeys.sorted { $0.displayName < $1.displayName }.compactMap { key in
            guard settingsRawValueString(for: key.rawValue, in: imported) != settingsRawValueString(for: key.rawValue, in: resolvedImport) else { return nil }
            return SettingsPreviewDiff(
                label: key.displayName,
                fromValue: settingsValueSummary(for: key.rawValue, in: imported),
                toValue: settingsValueSummary(for: key.rawValue, in: resolvedImport)
            )
        }
    }

    private func previewLines(for diffs: [SettingsPreviewDiff], prefix: String? = nil) -> [String] {
        let lines = diffs.map { diff in
            if let prefix {
                return "• \(diff.label): \(prefix) \(diff.fromValue), effective \(diff.toValue)"
            }
            return "• \(diff.label): \(diff.fromValue) -> \(diff.toValue)"
        }
        return limitPreviewLines(lines)
    }

    private func limitPreviewLines(_ lines: [String], maxCount: Int = 10) -> [String] {
        guard lines.count > maxCount else { return lines }
        return Array(lines.prefix(maxCount)) + ["• +\(lines.count - maxCount) more"]
    }

    private var previewableKeys: [String] {
        [
            "eyeConfig",
            "microConfig",
            "longConfig",
            "snoozeDurationMinutes",
            "historyRetentionDays",
            "isPaused",
            "customBreakTypes",
            "blockedBundleIDs",
            "idleThresholdMinutes",
            "pauseDuringFocus",
            "pauseDuringCalendarEvents",
            "calendarFilterMode",
            "filteredCalendarIDs",
            "workdayStartMinutes",
            "workdayEndMinutes",
            "profiles",
            "activeProfileId",
            "notificationLeadMinutes",
            "weeklyNotificationEnabled",
            "globalSnoozeHotkey",
            "menuBarIconTheme",
            "breakEnforcementMode",
            "rolePolicies",
            "activeRole",
            "localOnlyMode",
        ]
    }

    private func settingsLabel(for key: String) -> String {
        if let managedKey = ManagedSettingsKey(rawValue: key) {
            return managedKey.displayName
        }
        switch key {
        case "eyeConfig": return "Eye Break"
        case "microConfig": return "Micro Break"
        case "longConfig": return "Long Break"
        case "historyRetentionDays": return "Retention Period"
        case "isPaused": return "Pause State"
        case "profiles": return "Profiles"
        case "activeProfileId": return "Active Profile"
        case "weeklyNotificationEnabled": return "Weekly Summary"
        case "globalSnoozeHotkey": return "Snooze Hotkey"
        case "menuBarIconTheme": return "Menu Bar Icon"
        default: return key
        }
    }

    private func settingsValueSummary(for key: String, in settings: AppSettings) -> String {
        switch key {
        case "eyeConfig":
            return breakConfigSummary(settings.eyeConfig)
        case "microConfig":
            return breakConfigSummary(settings.microConfig)
        case "longConfig":
            return breakConfigSummary(settings.longConfig)
        case "snoozeDurationMinutes":
            return "\(settings.snoozeDurationMinutes) min"
        case "historyRetentionDays":
            return settings.historyRetentionDays == 0 ? "Unlimited" : "\(settings.historyRetentionDays) days"
        case "isPaused":
            return settings.isPaused ? "Paused" : "Running"
        case "customBreakTypes":
            return "\(settings.customBreakTypes.count) type(s)"
        case "blockedBundleIDs":
            return listSummary(settings.blockedBundleIDs, empty: "None")
        case "idleThresholdMinutes":
            return "\(settings.idleThresholdMinutes) min"
        case "pauseDuringFocus":
            return toggleSummary(settings.pauseDuringFocus)
        case "pauseDuringCalendarEvents":
            return toggleSummary(settings.pauseDuringCalendarEvents)
        case "calendarFilterMode":
            return calendarFilterSummary(settings.calendarFilterMode)
        case "filteredCalendarIDs":
            return settings.filteredCalendarIDs.isEmpty ? "None" : "\(settings.filteredCalendarIDs.count) calendar(s)"
        case "workdayStartMinutes":
            return settings.workdayStartMinutes.map(SettingsUIHelpers.formatMinutes) ?? "Off"
        case "workdayEndMinutes":
            return settings.workdayEndMinutes.map(SettingsUIHelpers.formatMinutes) ?? "Off"
        case "profiles":
            return "\(settings.profiles.count) profile(s)"
        case "activeProfileId":
            return activeProfileSummary(for: settings)
        case "notificationLeadMinutes":
            return "\(settings.notificationLeadMinutes) min"
        case "weeklyNotificationEnabled":
            return toggleSummary(settings.weeklyNotificationEnabled)
        case "globalSnoozeHotkey":
            return hotkeyLabel(for: settings.globalSnoozeHotkey)
        case "menuBarIconTheme":
            return menuBarThemeSummary(settings.menuBarIconTheme)
        case "breakEnforcementMode":
            return enforcementLabel(settings.breakEnforcementMode)
        case "rolePolicies":
            return "\(settings.rolePolicies.count) role policy(s)"
        case "activeRole":
            return roleLabel(settings.activeRole)
        case "localOnlyMode":
            return settings.localOnlyMode ? "Local only" : "Syncing"
        default:
            guard let object = rawSettingsValue(for: key, in: settings) else { return "Unknown" }
            return stringifyJSONObject(object) ?? "Unknown"
        }
    }

    private func settingsRawValueString(for key: String, in settings: AppSettings) -> String {
        guard let object = rawSettingsValue(for: key, in: settings) else { return "" }
        return stringifyJSONObject(object) ?? ""
    }

    private func rawSettingsValue(for key: String, in settings: AppSettings) -> Any? {
        guard let data = try? JSONEncoder().encode(settings),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return dict[key]
    }

    private func breakConfigSummary(_ config: BreakConfig) -> String {
        "\(config.intervalMinutes)m / \(config.durationSeconds)s / \(config.isEnabled ? "On" : "Off")"
    }

    private func listSummary(_ values: [String], empty: String) -> String {
        guard !values.isEmpty else { return empty }
        let sorted = values.sorted()
        if sorted.count <= 3 {
            return sorted.joined(separator: ", ")
        }
        return sorted.prefix(3).joined(separator: ", ") + " +\(sorted.count - 3) more"
    }

    private func toggleSummary(_ value: Bool) -> String {
        value ? "On" : "Off"
    }

    private func calendarFilterSummary(_ mode: CalendarFilterMode) -> String {
        switch mode {
        case .all: return "All events"
        case .busyOnly: return "Busy only"
        case .selected: return "Selected calendars"
        }
    }

    private func activeProfileSummary(for settings: AppSettings) -> String {
        guard let activeID = settings.activeProfileId else { return "None" }
        return settings.profiles.first(where: { $0.id == activeID })?.name ?? activeID.uuidString
    }

    private func hotkeyLabel(for hotkey: HotkeyDescriptor?) -> String {
        guard let hotkey else { return "None" }
        var parts: [String] = []
        let mods = NSEvent.ModifierFlags(rawValue: UInt(hotkey.modifierFlags))
        if mods.contains(.control) { parts.append("⌃") }
        if mods.contains(.option) { parts.append("⌥") }
        if mods.contains(.shift) { parts.append("⇧") }
        if mods.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeToString(hotkey.keyCode))
        return parts.joined()
    }

    private func menuBarThemeSummary(_ theme: MenuBarIconTheme) -> String {
        switch theme {
        case .monochrome: return "Monochrome"
        case .color: return "Color"
        case .minimal: return "Minimal"
        }
    }
}

private struct SettingsPreviewDiff {
    let label: String
    let fromValue: String
    let toValue: String
}

enum SettingsUIHelpers {
    static let workdayTimeSlots = stride(from: 0, to: 1440, by: 30).map { $0 }

    static func formatMinutes(_ mins: Int) -> String {
        String(format: "%02d:%02d", mins / 60, mins % 60)
    }
}

struct CalendarSelectionSection: View {
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

struct BundleIDSelectionSection: View {
    @Binding var selectedBundleIDs: [String]
    let isDisabled: Bool
    let caption: String

    @State private var manualBundleID = ""

    private var runningApplications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(runningApplications, id: \.processIdentifier) { app in
                let bundleID = app.bundleIdentifier ?? ""
                Toggle(app.localizedName ?? bundleID, isOn: toggleBinding(for: bundleID))
                    .disabled(isDisabled)
            }

            HStack {
                TextField("Manual bundle ID", text: $manualBundleID)
                Button("Add", action: addManualBundleID)
                    .disabled(isDisabled)
            }

            ForEach(Array(Set(selectedBundleIDs)).sorted(), id: \.self) { bundleID in
                HStack {
                    Text(bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") {
                        selectedBundleIDs.removeAll { $0 == bundleID }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .disabled(isDisabled)
                }
            }
        }
    }

    private func toggleBinding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { selectedBundleIDs.contains(bundleID) },
            set: { selected in
                if selected {
                    if !selectedBundleIDs.contains(bundleID) {
                        selectedBundleIDs.append(bundleID)
                    }
                } else {
                    selectedBundleIDs.removeAll { $0 == bundleID }
                }
            }
        )
    }

    private func addManualBundleID() {
        let bundleID = manualBundleID.trimmingCharacters(in: .whitespaces)
        guard !bundleID.isEmpty, !selectedBundleIDs.contains(bundleID), isValidBundleID(bundleID) else { return }
        selectedBundleIDs.append(bundleID)
        manualBundleID = ""
    }

    private func isValidBundleID(_ id: String) -> Bool {
        id.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil
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
