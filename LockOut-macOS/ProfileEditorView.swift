import SwiftUI
import LockOutCore

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
                    let profile = AppProfile(name: name,
                        customBreakTypes: scheduler.currentSettings.customBreakTypes,
                        blockedBundleIDs: scheduler.currentSettings.blockedBundleIDs,
                        idleThresholdMinutes: scheduler.currentSettings.idleThresholdMinutes)
                    profiles.wrappedValue.append(profile)
                    newProfileName = ""
                }
            }
            Button("Save Current Settings as New Profile") {
                let name = "Profile \(profiles.wrappedValue.count + 1)"
                let profile = AppProfile(name: name,
                    customBreakTypes: scheduler.currentSettings.customBreakTypes,
                    blockedBundleIDs: scheduler.currentSettings.blockedBundleIDs,
                    idleThresholdMinutes: scheduler.currentSettings.idleThresholdMinutes)
                profiles.wrappedValue.append(profile)
                scheduler.currentSettings.activeProfileId = profile.id
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(minWidth: 500, minHeight: 300)
        .sheet(isPresented: $showEditor) {
            if let editing = editingProfile,
               let idx = profiles.wrappedValue.firstIndex(where: { $0.id == editing.id }) {
                ProfileDetailEditor(profile: profiles[idx]) { showEditor = false }
            }
        }
    }

    private func activateProfile(_ profile: AppProfile) {
        scheduler.currentSettings.activeProfileId = profile.id
        scheduler.currentSettings.customBreakTypes = profile.customBreakTypes
        scheduler.currentSettings.blockedBundleIDs = profile.blockedBundleIDs
        scheduler.currentSettings.idleThresholdMinutes = profile.idleThresholdMinutes
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit: \(profile.name)").font(.headline)
            List {
                ForEach(profile.customBreakTypes.indices, id: \.self) { i in
                    HStack {
                        Toggle("", isOn: $profile.customBreakTypes[i].enabled).labelsHidden()
                        Text(profile.customBreakTypes[i].name)
                        Spacer()
                        Text("\(profile.customBreakTypes[i].intervalMinutes)m / \(profile.customBreakTypes[i].durationSeconds)s")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .onDelete { profile.customBreakTypes.remove(atOffsets: $0) }
            }
            Stepper("Idle threshold: \(profile.idleThresholdMinutes) min",
                    value: $profile.idleThresholdMinutes, in: 1...60)
            Button("Done") { onDone() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}
