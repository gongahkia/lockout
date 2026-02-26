import SwiftUI
import LockOutCore

struct ProfileEditorView: View {
    @EnvironmentObject var scheduler: BreakScheduler
    @State private var newProfileName = ""

    private var profiles: Binding<[AppProfile]> {
        Binding(
            get: { scheduler.currentSettings.profiles },
            set: { scheduler.currentSettings.profiles = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Profiles").font(.title2).bold()
            List {
                ForEach(profiles.wrappedValue, id: \.id) { profile in
                    HStack {
                        Text(profile.name)
                        if scheduler.currentSettings.activeProfileId == profile.id {
                            Image(systemName: "checkmark").foregroundStyle(.blue)
                        }
                        Spacer()
                        Button("Duplicate") { duplicate(profile) }
                            .buttonStyle(.plain)
                    }
                }
                .onDelete { profiles.wrappedValue.remove(atOffsets: $0) }
            }
            HStack {
                TextField("New profile name", text: $newProfileName)
                Button("Create") {
                    let name = newProfileName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    profiles.wrappedValue.append(AppProfile(name: name,
                        customBreakTypes: scheduler.currentSettings.customBreakTypes,
                        blockedBundleIDs: scheduler.currentSettings.blockedBundleIDs,
                        idleThresholdMinutes: scheduler.currentSettings.idleThresholdMinutes))
                    newProfileName = ""
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .frame(minWidth: 340, minHeight: 300)
    }

    private func duplicate(_ profile: AppProfile) {
        var copy = profile
        copy.id = UUID()
        copy.name = "\(profile.name) Copy"
        profiles.wrappedValue.append(copy)
    }
}
