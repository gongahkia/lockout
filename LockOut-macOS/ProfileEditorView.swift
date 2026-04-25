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
            RoundedRectangle(cornerRadius: LockOutLayout.cornerRadius)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: LockOutLayout.cornerRadius)
                        .strokeBorder(isActive ? LockOutPalette.mint.opacity(0.35) : LockOutPalette.separator.opacity(0.35), lineWidth: 1)
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
