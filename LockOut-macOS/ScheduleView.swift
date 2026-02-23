import SwiftUI
import LockOutCore

struct ScheduleView: View {
    @EnvironmentObject var scheduler: BreakScheduler

    var body: some View {
        Form {
            breakGroup(title: "Eye Break (20-20-20)", config: Binding(
                get: { scheduler.currentSettings.eyeConfig },
                set: { scheduler.currentSettings.eyeConfig = $0; reschedule() }
            ))
            breakGroup(title: "Micro Break", config: Binding(
                get: { scheduler.currentSettings.microConfig },
                set: { scheduler.currentSettings.microConfig = $0; reschedule() }
            ))
            breakGroup(title: "Long Break", config: Binding(
                get: { scheduler.currentSettings.longConfig },
                set: { scheduler.currentSettings.longConfig = $0; reschedule() }
            ))
            Button("Restore Defaults") {
                scheduler.reschedule(with: .defaults)
            }
        }
        .padding(24)
        .navigationTitle("Schedule")
    }

    @ViewBuilder
    private func breakGroup(title: String, config: Binding<BreakConfig>) -> some View {
        GroupBox(label: Text(title).font(.headline)) {
            Stepper("Every \(config.wrappedValue.intervalMinutes) min",
                    value: config.intervalMinutes, in: 1...120)
            Stepper("For \(config.wrappedValue.durationSeconds) sec",
                    value: config.durationSeconds, in: 5...3600)
        }
    }

    private func reschedule() { scheduler.reschedule(with: scheduler.currentSettings) }
}
