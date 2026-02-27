import SwiftUI
import LockOutCore

struct CustomBreakTypeEditorView: View {
    @Binding var breakType: CustomBreakType
    @State private var newTip = ""
    @State private var validationError: String?

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $breakType.name)
            }
            Section("Timing") {
                Stepper("Interval: \(breakType.intervalMinutes) min", value: $breakType.intervalMinutes, in: 1...480)
                Stepper("Duration: \(breakType.durationSeconds) sec", value: $breakType.durationSeconds, in: 10...7200)
                Stepper("Min display: \(breakType.minDisplaySeconds) sec", value: $breakType.minDisplaySeconds, in: 1...breakType.durationSeconds)
                Stepper("Snooze: \(breakType.snoozeMinutes) min", value: $breakType.snoozeMinutes, in: 1...60)
            }
            Section("Display") {
                Slider(value: $breakType.overlayOpacity, in: 0.1...1.0) { Text("Opacity") }
                Text("Opacity: \(Int(breakType.overlayOpacity * 100))%").font(.caption)
                TextField("Color (hex, e.g. #1A2B3C)", text: $breakType.overlayColorHex)
                Picker("Blur", selection: $breakType.overlayBlurMaterial) {
                    Text("Ultra Thin").tag("ultraThin")
                    Text("Thin").tag("thin")
                    Text("Medium").tag("medium")
                    Text("HUD Window").tag("hudWindow")
                }
            }
            Section("Content") {
                TextField("Message", text: Binding(
                    get: { breakType.message ?? "" },
                    set: { breakType.message = $0.isEmpty ? nil : $0 }
                ))
                TextField("Sound name (optional)", text: Binding(
                    get: { breakType.soundName ?? "" },
                    set: { breakType.soundName = $0.isEmpty ? nil : $0 }
                ))
            }
            Section("Tips") {
                ForEach(breakType.tips, id: \.self) { tip in
                    Text(tip)
                }
                .onDelete { breakType.tips.remove(atOffsets: $0) }
                HStack {
                    TextField("Add tip", text: $newTip)
                    Button("Add") {
                        guard !newTip.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        breakType.tips.append(newTip)
                        newTip = ""
                    }
                }
            }
            Section {
                Toggle("Enabled", isOn: $breakType.enabled)
            }
            if let err = validationError {
                Text(err).foregroundStyle(.red).font(.caption)
            }
        }
        .onChange(of: breakType) { _, _ in validate() }
        .padding()
    }

    private func validate() {
        if breakType.intervalMinutes < 1 {
            validationError = "Interval must be at least 1 minute."
        } else if breakType.durationSeconds < 10 {
            validationError = "Duration must be at least 10 seconds."
        } else if breakType.minDisplaySeconds > breakType.durationSeconds {
            validationError = "Min display cannot exceed duration."
        } else {
            validationError = nil
        }
    }

    var isValid: Bool { validationError == nil }
}
