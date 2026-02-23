import SwiftUI
import LockOutCore

struct iOSScheduleView: View {
    private var delegate: iOSAppDelegate { .shared }

    var body: some View {
        NavigationView {
            List {
                breakSection(title: "Eye Break", config: Binding(
                    get: { delegate.settings.eyeConfig },
                    set: { delegate.settings.eyeConfig = $0; reschedule() }
                ))
                breakSection(title: "Micro Break", config: Binding(
                    get: { delegate.settings.microConfig },
                    set: { delegate.settings.microConfig = $0; reschedule() }
                ))
                breakSection(title: "Long Break", config: Binding(
                    get: { delegate.settings.longConfig },
                    set: { delegate.settings.longConfig = $0; reschedule() }
                ))
            }
            .navigationTitle("Schedule")
        }
    }

    @ViewBuilder
    private func breakSection(title: String, config: Binding<BreakConfig>) -> some View {
        Section(header: Text(title)) {
            Stepper("Every \(config.wrappedValue.intervalMinutes) min", value: config.intervalMinutes, in: 1...120)
            Stepper("For \(config.wrappedValue.durationSeconds) sec", value: config.durationSeconds, in: 5...3600)
        }
    }

    private func reschedule() { NotificationScheduler.schedule(settings: delegate.settings) }
}
