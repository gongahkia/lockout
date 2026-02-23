import SwiftUI
import LockOutCore

struct iOSDashboardView: View {
    private var delegate: iOSAppDelegate { .shared }
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var settings: AppSettings { delegate.settings }

    private var todayCompliance: Double {
        delegate.repository.dailyStats(for: 1).first?.complianceRate ?? 0
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Text("Next break: \(nextBreakLabel)")
                    .font(.headline)
                Text("Today's compliance: \(Int(todayCompliance * 100))%")
                    .font(.subheadline).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Eye breaks", isOn: Binding(
                        get: { settings.eyeConfig.isEnabled },
                        set: { delegate.settings.eyeConfig.isEnabled = $0; reschedule() }
                    ))
                    Toggle("Micro breaks", isOn: Binding(
                        get: { settings.microConfig.isEnabled },
                        set: { delegate.settings.microConfig.isEnabled = $0; reschedule() }
                    ))
                    Toggle("Long breaks", isOn: Binding(
                        get: { settings.longConfig.isEnabled },
                        set: { delegate.settings.longConfig.isEnabled = $0; reschedule() }
                    ))
                }
                .padding(.horizontal)
            }
            .navigationTitle("Dashboard")
            .onReceive(tick) { now = $0 }
        }
    }

    private var nextBreakLabel: String {
        let configs: [(BreakType, BreakConfig)] = [
            (.eye, settings.eyeConfig), (.micro, settings.microConfig), (.long, settings.longConfig)
        ]
        guard let earliest = configs.filter({ $0.1.isEnabled }).min(by: { $0.1.intervalMinutes < $1.1.intervalMinutes }) else { return "None" }
        return "\(earliest.0.rawValue.capitalized)"
    }

    private func reschedule() { NotificationScheduler.schedule(settings: delegate.settings) }
}
