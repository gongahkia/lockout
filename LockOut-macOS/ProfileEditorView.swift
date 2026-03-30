import AppKit
import LockOutCore
import SwiftUI

private struct EditingProfileContext: Identifiable {
    let id: UUID
}

struct ProfileEditorView: View {
    @EnvironmentObject private var scheduler: BreakScheduler
    @State private var newProfileName = ""
    @State private var editingContext: EditingProfileContext?
    @State private var bootstrapStatusMessage: String?

    private var profiles: Binding<[AppProfile]> {
        Binding(
            get: { scheduler.currentSettings.profiles },
            set: { scheduler.currentSettings.profiles = $0 }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LockOutScreenHeader(
                    title: "Profiles",
                    subtitle: "Save different routines, switch into manual hold, and define the automation rules that decide when each profile wins.",
                    symbol: "person.crop.rectangle.stack",
                    accent: LockOutPalette.amber
                )

                LockOutCard(
                    title: "Saved Profiles",
                    subtitle: "Profiles capture the full routine: break types, workday window, enforcement, notifications, and blocklist behavior.",
                    icon: "rectangle.stack.person.crop",
                    accent: LockOutPalette.amber
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            LockOutStatusBadge(
                                scheduler.currentSettings.profileActivationMode.displayName,
                                tone: scheduler.currentSettings.profileActivationMode == .manualHold ? .warning : .info
                            )
                            Spacer()
                            Button("Bootstrap Agent Presets", action: bootstrapAgentDeveloperProfiles)
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("profiles.bootstrapAgentPresets")
                            Button("Save Current Settings as New Profile", action: saveCurrentProfile)
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("profiles.saveCurrent")
                        }

                        if let bootstrapStatusMessage {
                            Text(bootstrapStatusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if profiles.wrappedValue.isEmpty {
                            LockOutEmptyState(
                                symbol: "person.crop.circle.badge.plus",
                                title: "No profiles yet",
                                message: "Create a profile to save a specific break configuration or to start building automation rules.",
                                accent: LockOutPalette.amber
                            )
                        } else {
                            ForEach(profiles) { $profile in
                                ProfileSummaryRow(
                                    profile: $profile,
                                    isActive: scheduler.currentSettings.activeProfileId == profile.id,
                                    onActivate: { activateProfile(profile) },
                                    onEdit: { editingContext = EditingProfileContext(id: profile.id) },
                                    onDuplicate: { duplicate(profile) },
                                    onDelete: { delete(profile) }
                                )
                            }
                        }
                    }
                }

                LockOutCard(
                    title: "Create Profile",
                    subtitle: "Start from the current scheduler settings and give the new routine a stable name.",
                    icon: "plus.circle",
                    accent: LockOutPalette.sky
                ) {
                    HStack(spacing: 12) {
                        TextField("New profile name", text: $newProfileName)
                        Button("Create", action: createProfile)
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("profiles.create")
                    }
                }
            }
            .padding(28)
        }
        .frame(minWidth: 620, minHeight: 420)
        .background(LockOutSceneBackground())
        .accessibilityIdentifier("profiles.view")
        .sheet(item: $editingContext) { context in
            if let index = profiles.wrappedValue.firstIndex(where: { $0.id == context.id }) {
                ProfileDetailEditor(profile: profiles[index]) {
                    let updatedProfile = profiles.wrappedValue[index]
                    if scheduler.currentSettings.activeProfileId == updatedProfile.id {
                        scheduler.currentSettings.apply(profile: updatedProfile)
                        scheduler.reschedule(with: scheduler.currentSettings)
                    }
                    editingContext = nil
                }
            }
        }
    }

    private func createProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let profile = scheduler.currentSettings.profileSnapshot(name: name)
        profiles.wrappedValue.append(profile)
        newProfileName = ""
    }

    private func saveCurrentProfile() {
        let name = "Profile \(profiles.wrappedValue.count + 1)"
        let profile = scheduler.currentSettings.profileSnapshot(name: name)
        profiles.wrappedValue.append(profile)
        scheduler.currentSettings.activeProfileId = profile.id
    }

    private func bootstrapAgentDeveloperProfiles() {
        var settings = scheduler.currentSettings
        let result = AgentDeveloperPresets.bootstrap(into: &settings)
        scheduler.currentSettings = settings
        if result.isNoOp {
            bootstrapStatusMessage = "Agent presets already exist in this workspace."
            return
        }
        bootstrapStatusMessage = "Added \(result.addedProfiles.count) agent profiles and \(result.addedRules) starter rules (rules are disabled by default)."
    }

    private func activateProfile(_ profile: AppProfile) {
        var settings = scheduler.currentSettings
        settings.apply(profile: profile)
        settings.profileActivationMode = .manualHold
        scheduler.reschedule(with: settings)
        (NSApp.delegate as? AppDelegate)?.refreshDecisionTrace()
    }

    private func duplicate(_ profile: AppProfile) {
        var copy = profile
        copy.id = UUID()
        copy.name = "\(profile.name) Copy"
        profiles.wrappedValue.append(copy)
    }

    private func delete(_ profile: AppProfile) {
        profiles.wrappedValue.removeAll { $0.id == profile.id }
        if scheduler.currentSettings.activeProfileId == profile.id {
            scheduler.currentSettings.activeProfileId = nil
            scheduler.currentSettings.profileActivationMode = .automatic
        }
    }
}

private struct ProfileSummaryRow: View {
    @Binding var profile: AppProfile
    let isActive: Bool
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? LockOutPalette.mint : .secondary)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Name", text: $profile.name)
                    .textFieldStyle(.plain)
                    .font(.headline)

                Text("\(profile.customBreakTypes.count) break types, \(profile.autoPauseSummary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button("Activate", action: onActivate)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isActive)
                Button("Edit", action: onEdit)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("profiles.edit")
                Button("Duplicate", action: onDuplicate)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Delete", action: onDelete)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(isActive ? LockOutPalette.mint.opacity(0.35) : .white.opacity(0.55), lineWidth: 1)
                )
        )
    }
}

private extension AppProfile {
    var autoPauseSummary: String {
        var segments: [String] = []
        if pauseDuringFocus {
            segments.append("Focus")
        }
        if pauseDuringCalendarEvents {
            segments.append("Calendar")
        }
        if let workdayStartMinutes, let workdayEndMinutes {
            segments.append("\(SettingsUIHelpers.formatMinutes(workdayStartMinutes))-\(SettingsUIHelpers.formatMinutes(workdayEndMinutes))")
        }
        return segments.isEmpty ? "no auto-pause" : segments.joined(separator: ", ")
    }
}

// inline editor for a profile's break types
struct ProfileDetailEditor: View {
    @EnvironmentObject var scheduler: BreakScheduler
    @Binding var profile: AppProfile
    let onDone: () -> Void

    private var managedSnapshot: ManagedSettingsSnapshot? {
        (NSApp.delegate as? AppDelegate)?.managedSettings
    }

    private var lockedProfileKeys: [ManagedSettingsKey] {
        let supportedKeys: [ManagedSettingsKey] = [
            .customBreakTypes,
            .blockedBundleIDs,
            .idleThresholdMinutes,
            .pauseDuringFocus,
            .pauseDuringCalendarEvents,
            .calendarFilterMode,
            .filteredCalendarIDs,
            .workdayStartMinutes,
            .workdayEndMinutes,
            .notificationLeadMinutes,
            .breakEnforcementMode,
            .snoozeDurationMinutes,
        ]
        return supportedKeys.filter(isLocked).sorted { $0.displayName < $1.displayName }
    }

    private var autoProfileRules: Binding<[AutoProfileRule]> {
        Binding(
            get: { scheduler.currentSettings.autoProfileRules.filter { $0.profileID == profile.id } },
            set: { updatedRules in
                var allRules = scheduler.currentSettings.autoProfileRules.filter { $0.profileID != profile.id }
                allRules.append(contentsOf: updatedRules)
                scheduler.currentSettings.autoProfileRules = allRules.sorted { $0.priority > $1.priority }
            }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section {
                    quickJumpBar(proxy: proxy)
                    Text("This profile includes workday scheduling, notifications, enforcement, and blocklist settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile.fullRoutineSummary")
                }

                if !lockedProfileKeys.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Some profile fields are managed", systemImage: "lock.shield")
                                .font(.headline)
                            Text(lockedProfileKeys.map(\.displayName).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Break Types") {
                    ForEach(Array(profile.customBreakTypes.enumerated()), id: \.element.id) { i, breakType in
                        HStack {
                            Toggle("", isOn: $profile.customBreakTypes[i].enabled).labelsHidden()
                            Text(breakType.name)
                            Spacer()
                            Text("\(breakType.intervalMinutes)m / \(breakType.durationSeconds)s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Remove") {
                                profile.customBreakTypes.remove(at: i)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                            .disabled(isLocked(.customBreakTypes))
                        }
                    }
                    .disabled(isLocked(.customBreakTypes))
                }

                Section("Auto-Pause") {
                    Stepper(
                        "Idle threshold: \(profile.idleThresholdMinutes) min",
                        value: $profile.idleThresholdMinutes,
                        in: 1...60
                    )
                    .disabled(isLocked(.idleThresholdMinutes))

                    Toggle("Pause during Focus Mode", isOn: $profile.pauseDuringFocus)
                        .disabled(isLocked(.pauseDuringFocus))

                    Toggle("Pause during Calendar events", isOn: $profile.pauseDuringCalendarEvents)
                        .disabled(isLocked(.pauseDuringCalendarEvents))

                    if profile.pauseDuringCalendarEvents {
                        Picker("Calendar Filter", selection: $profile.calendarFilterMode) {
                            Text("All events").tag(CalendarFilterMode.all)
                            Text("Busy only").tag(CalendarFilterMode.busyOnly)
                            Text("Selected calendars").tag(CalendarFilterMode.selected)
                        }
                        .disabled(isLocked(.calendarFilterMode))

                        if profile.calendarFilterMode == .selected {
                            CalendarSelectionSection(
                                selectedIDs: $profile.filteredCalendarIDs,
                                isDisabled: isLocked(.filteredCalendarIDs) || isLocked(.pauseDuringCalendarEvents)
                            )
                        }
                    }
                }

                Section("Workday") {
                    Color.clear
                        .frame(height: 1)
                        .id("profile.anchor.workday")

                    Text("Profile workday settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile.section.workday")

                    Picker("Start time", selection: Binding(
                        get: { profile.workdayStartMinutes ?? -1 },
                        set: { profile.workdayStartMinutes = $0 >= 0 ? $0 : nil }
                    )) {
                        Text("Off").tag(-1)
                        ForEach(SettingsUIHelpers.workdayTimeSlots, id: \.self) { mins in
                            Text(SettingsUIHelpers.formatMinutes(mins)).tag(mins)
                        }
                    }
                    .accessibilityIdentifier("profile.workday.start")
                    .accessibilityLabel("Start time")
                    .disabled(isLocked(.workdayStartMinutes))

                    Picker("End time", selection: Binding(
                        get: { profile.workdayEndMinutes ?? -1 },
                        set: { profile.workdayEndMinutes = $0 >= 0 ? $0 : nil }
                    )) {
                        Text("Off").tag(-1)
                        ForEach(SettingsUIHelpers.workdayTimeSlots, id: \.self) { mins in
                            Text(SettingsUIHelpers.formatMinutes(mins)).tag(mins)
                        }
                    }
                    .accessibilityIdentifier("profile.workday.end")
                    .accessibilityLabel("End time")
                    .disabled(isLocked(.workdayEndMinutes))
                }

                Section("Notifications & Enforcement") {
                    Color.clear
                        .frame(height: 1)
                        .id("profile.anchor.notifications")

                    Text("Profile enforcement settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile.section.notifications")

                    Stepper(
                        "Notification lead: \(profile.notificationLeadMinutes) min",
                        value: $profile.notificationLeadMinutes,
                        in: 0...5
                    )
                    .disabled(isLocked(.notificationLeadMinutes))

                    Stepper(
                        "Snooze duration: \(profile.snoozeDurationMinutes) min",
                        value: $profile.snoozeDurationMinutes,
                        in: 1...30
                    )
                    .disabled(isLocked(.snoozeDurationMinutes))

                    Picker("Break enforcement", selection: $profile.breakEnforcementMode) {
                        Text("Reminder").tag(BreakEnforcementMode.reminder)
                        Text("Soft Lock").tag(BreakEnforcementMode.soft_lock)
                        Text("Hard Lock").tag(BreakEnforcementMode.hard_lock)
                    }
                    .accessibilityIdentifier("profile.enforcement")
                    .accessibilityLabel("Break enforcement")
                    .disabled(isLocked(.breakEnforcementMode))
                }

                Section("Blocklist") {
                    Color.clear
                        .frame(height: 1)
                        .id("profile.anchor.blocklist")

                    Text("Profile blocklist settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("profile.section.blocklist")

                    BundleIDSelectionSection(
                        selectedBundleIDs: $profile.blockedBundleIDs,
                        isDisabled: isLocked(.blockedBundleIDs),
                        caption: "Block break overlay for these apps while this profile is active:"
                    )
                }

                Section("Automation") {
                    Text("Rules are OR-based. The highest-priority matching rule wins unless manual hold is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if autoProfileRules.wrappedValue.isEmpty {
                        Text("No automatic rules yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(autoProfileRules.wrappedValue.indices), id: \.self) { index in
                        AutoProfileRuleEditor(
                            rule: Binding(
                                get: { autoProfileRules.wrappedValue[index] },
                                set: {
                                    var rules = autoProfileRules.wrappedValue
                                    rules[index] = $0
                                    autoProfileRules.wrappedValue = rules
                                }
                            )
                        )
                        Button("Remove Rule") {
                            var rules = autoProfileRules.wrappedValue
                            rules.remove(at: index)
                            autoProfileRules.wrappedValue = rules
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                    Button("Add Rule") {
                        var rules = autoProfileRules.wrappedValue
                        rules.append(
                            AutoProfileRule(
                                enabled: true,
                                priority: (rules.map(\.priority).max() ?? 0) + 1,
                                profileID: profile.id,
                                triggers: [
                                    .timeWindow(
                                        startMinutes: profile.workdayStartMinutes ?? 540,
                                        endMinutes: profile.workdayEndMinutes ?? 1020
                                    )
                                ]
                            )
                        )
                        autoProfileRules.wrappedValue = rules
                    }
                    .buttonStyle(.bordered)
                }

                Section {
                    HStack {
                        Spacer()
                        Button("Done") { onDone() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 540, minHeight: 560)
        .navigationTitle(profile.name)
        .accessibilityIdentifier("profile.detail")
    }

    @ViewBuilder
    private func quickJumpBar(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 8) {
            jumpButton(title: "Workday", accessibilityID: "profile.jump.workday", anchor: "profile.anchor.workday", proxy: proxy)
            jumpButton(title: "Enforcement", accessibilityID: "profile.jump.notifications", anchor: "profile.anchor.notifications", proxy: proxy)
            jumpButton(title: "Blocklist", accessibilityID: "profile.jump.blocklist", anchor: "profile.anchor.blocklist", proxy: proxy)
        }
    }

    private func jumpButton(
        title: String,
        accessibilityID: String,
        anchor: String,
        proxy: ScrollViewProxy
    ) -> some View {
        Button(title) {
            withAnimation {
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityIdentifier(accessibilityID)
    }

    private func isLocked(_ key: ManagedSettingsKey) -> Bool {
        managedSnapshot?.isForced(key) ?? false
    }
}

private struct AutoProfileRuleEditor: View {
    @Binding var rule: AutoProfileRule

    private var timeWindow: (Int, Int)? {
        for trigger in rule.triggers {
            if case let .timeWindow(startMinutes, endMinutes) = trigger {
                return (startMinutes, endMinutes)
            }
        }
        return nil
    }

    private var appBundleIDs: [String] {
        for trigger in rule.triggers {
            if case let .frontmostApp(bundleIDs) = trigger {
                return bundleIDs
            }
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Enabled", isOn: $rule.enabled)
            Stepper("Priority: \(rule.priority)", value: $rule.priority, in: 0...100)
            Toggle("Match calendar context", isOn: triggerBinding(for: .calendarMatch))
            Toggle("Match Focus Mode", isOn: triggerBinding(for: .focusMode))
            Toggle("Match external display", isOn: triggerBinding(for: .externalDisplayConnected))
            Toggle("Use time window", isOn: timeWindowEnabledBinding)
            if let timeWindow {
                Picker("Start", selection: timeWindowStartBinding(defaultValue: timeWindow.0)) {
                    ForEach(SettingsUIHelpers.workdayTimeSlots, id: \.self) { mins in
                        Text(SettingsUIHelpers.formatMinutes(mins)).tag(mins)
                    }
                }
                Picker("End", selection: timeWindowEndBinding(defaultValue: timeWindow.1)) {
                    ForEach(SettingsUIHelpers.workdayTimeSlots, id: \.self) { mins in
                        Text(SettingsUIHelpers.formatMinutes(mins)).tag(mins)
                    }
                }
            }
            TextField(
                "Frontmost app bundle IDs",
                text: Binding(
                    get: { appBundleIDs.joined(separator: ", ") },
                    set: { updateFrontmostApps($0) }
                )
            )
            .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 6)
    }

    private func triggerBinding(for trigger: ProfileTrigger) -> Binding<Bool> {
        Binding(
            get: { rule.triggers.contains(trigger) },
            set: { enabled in
                if enabled {
                    if !rule.triggers.contains(trigger) {
                        rule.triggers.append(trigger)
                    }
                } else {
                    rule.triggers.removeAll { $0 == trigger }
                }
            }
        )
    }

    private var timeWindowEnabledBinding: Binding<Bool> {
        Binding(
            get: { timeWindow != nil },
            set: { enabled in
                if enabled {
                    if timeWindow == nil {
                        rule.triggers.append(.timeWindow(startMinutes: 540, endMinutes: 1020))
                    }
                } else {
                    rule.triggers.removeAll { trigger in
                        if case .timeWindow = trigger { return true }
                        return false
                    }
                }
            }
        )
    }

    private func timeWindowStartBinding(defaultValue: Int) -> Binding<Int> {
        Binding(
            get: { timeWindow?.0 ?? defaultValue },
            set: { newValue in updateTimeWindow(start: newValue, end: timeWindow?.1 ?? 1020) }
        )
    }

    private func timeWindowEndBinding(defaultValue: Int) -> Binding<Int> {
        Binding(
            get: { timeWindow?.1 ?? defaultValue },
            set: { newValue in updateTimeWindow(start: timeWindow?.0 ?? 540, end: newValue) }
        )
    }

    private func updateTimeWindow(start: Int, end: Int) {
        rule.triggers.removeAll { trigger in
            if case .timeWindow = trigger { return true }
            return false
        }
        rule.triggers.append(.timeWindow(startMinutes: start, endMinutes: end))
    }

    private func updateFrontmostApps(_ text: String) {
        let bundleIDs = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        rule.triggers.removeAll { trigger in
            if case .frontmostApp = trigger { return true }
            return false
        }
        if !bundleIDs.isEmpty {
            rule.triggers.append(.frontmostApp(bundleIDs: bundleIDs))
        }
    }
}
