import SwiftUI
import Combine
import LockOutCore

@MainActor
private final class ScheduleDebouncer: ObservableObject {
    let subject = PassthroughSubject<AppSettings, Never>()
    private var cancellable: AnyCancellable?
    func setup(scheduler: BreakScheduler) {
        guard cancellable == nil else { return }
        cancellable = subject
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak scheduler] s in scheduler?.reschedule(with: s) }
    }
}

struct ScheduleView: View {
    @EnvironmentObject var scheduler: BreakScheduler
    @StateObject private var debouncer = ScheduleDebouncer()

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
        .onAppear { debouncer.setup(scheduler: scheduler) }
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

    private func reschedule() { debouncer.subject.send(scheduler.currentSettings) }
}
