import AppKit
import LockOutCore
import SwiftUI

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
                    ForEach(Array(profile.customBreakTypes.enumerated()), id: \.element.id) { index, breakType in
                        HStack {
                            Toggle("", isOn: $profile.customBreakTypes[index].enabled).labelsHidden()
                            Text(breakType.name)
                            Spacer()
                            Text("\(breakType.intervalMinutes)m / \(breakType.durationSeconds)s")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Remove") {
                                profile.customBreakTypes.remove(at: index)
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
                        Text("Soft Lock").tag(BreakEnforcementMode.softLock)
                        Text("Hard Lock").tag(BreakEnforcementMode.hardLock)
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
                        addRule()
                    }
                    .buttonStyle(.bordered)
                }

                Section {
                    HStack {
                        Spacer()
                        Button("Done", action: onDone)
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

    private func addRule() {
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
