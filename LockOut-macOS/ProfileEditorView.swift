import AppKit
import LockOutCore
import SwiftUI

struct ProfileEditorView: View {
    @EnvironmentObject var scheduler: BreakScheduler
    @State private var newProfileName = ""
    @State private var editingProfile: AppProfile?
    @State private var showEditor = false

    private var profiles: Binding<[AppProfile]> {
        Binding(
            get: { scheduler.currentSettings.profiles },
            set: { scheduler.currentSettings.profiles = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Profiles").font(.title2).bold()
            if profiles.wrappedValue.isEmpty {
                Text("No profiles. Create one to save different break configurations.")
                    .foregroundStyle(.secondary).font(.caption)
            }
            List {
                ForEach(profiles) { $profile in
                    HStack {
                        if scheduler.currentSettings.activeProfileId == profile.id {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                        } else {
                            Image(systemName: "circle").foregroundStyle(.secondary)
                        }
                        TextField("Name", text: $profile.name).textFieldStyle(.plain)
                        Spacer()
                        Text("\(profile.customBreakTypes.count) breaks")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Activate") { activateProfile(profile) }
                            .buttonStyle(.bordered).controlSize(.small)
                            .disabled(scheduler.currentSettings.activeProfileId == profile.id)
                        Button("Edit") { editingProfile = profile; showEditor = true }
                            .buttonStyle(.plain)
                        Button("Duplicate") { duplicate(profile) }
                            .buttonStyle(.plain)
                    }
                }
                .onDelete { profiles.wrappedValue.remove(atOffsets: $0) }
            }
            .frame(minHeight: 150)
            HStack {
                TextField("New profile name", text: $newProfileName)
                Button("Create") {
                    let name = newProfileName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    let profile = scheduler.currentSettings.profileSnapshot(name: name)
                    profiles.wrappedValue.append(profile)
                    newProfileName = ""
                }
                .accessibilityIdentifier("profiles.create")
            }
            Button("Save Current Settings as New Profile") {
                let name = "Profile \(profiles.wrappedValue.count + 1)"
                let profile = scheduler.currentSettings.profileSnapshot(name: name)
                profiles.wrappedValue.append(profile)
                scheduler.currentSettings.activeProfileId = profile.id
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("profiles.saveCurrent")
        }
        .padding()
        .frame(minWidth: 500, minHeight: 300)
        .accessibilityIdentifier("profiles.view")
        .sheet(isPresented: $showEditor) {
            if let editing = editingProfile,
               let idx = profiles.wrappedValue.firstIndex(where: { $0.id == editing.id }) {
                ProfileDetailEditor(profile: profiles[idx]) {
                    let updatedProfile = profiles.wrappedValue[idx]
                    if scheduler.currentSettings.activeProfileId == updatedProfile.id {
                        scheduler.currentSettings.apply(profile: updatedProfile)
                        scheduler.reschedule(with: scheduler.currentSettings)
                    }
                    showEditor = false
                }
            }
        }
    }

    private func activateProfile(_ profile: AppProfile) {
        scheduler.currentSettings.apply(profile: profile)
        scheduler.reschedule(with: scheduler.currentSettings)
    }

    private func duplicate(_ profile: AppProfile) {
        var copy = profile
        copy.id = UUID()
        copy.name = "\(profile.name) Copy"
        profiles.wrappedValue.append(copy)
    }
}

// inline editor for a profile's break types
struct ProfileDetailEditor: View {
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

    var body: some View {
        ScrollView {
            Form {
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
                    Picker("Start time", selection: Binding(
                        get: { profile.workdayStartMinutes ?? -1 },
                        set: { profile.workdayStartMinutes = $0 >= 0 ? $0 : nil }
                    )) {
                        Text("Off").tag(-1)
                        ForEach(SettingsUIHelpers.workdayTimeSlots, id: \.self) { mins in
                            Text(SettingsUIHelpers.formatMinutes(mins)).tag(mins)
                        }
                    }
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
                    .disabled(isLocked(.workdayEndMinutes))
                }

                Section("Notifications & Enforcement") {
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
                    .disabled(isLocked(.breakEnforcementMode))
                }

                Section("Blocklist") {
                    BundleIDSelectionSection(
                        selectedBundleIDs: $profile.blockedBundleIDs,
                        isDisabled: isLocked(.blockedBundleIDs),
                        caption: "Block break overlay for these apps while this profile is active:"
                    )
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

    private func isLocked(_ key: ManagedSettingsKey) -> Bool {
        managedSnapshot?.isForced(key) ?? false
    }
}
