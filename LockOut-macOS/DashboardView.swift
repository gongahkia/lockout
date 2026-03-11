import SwiftUI
import LockOutCore

struct DashboardView: View {
    let repository: BreakHistoryRepository
    @EnvironmentObject var scheduler: BreakScheduler
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var remaining: TimeInterval {
        guard let nb = scheduler.nextBreak else { return 0 }
        return max(0, nb.fireDate.timeIntervalSince(now))
    }

    private var timeString: String {
        let m = Int(remaining) / 60; let s = Int(remaining) % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var progress: Double {
        guard scheduler.nextBreak != nil else { return 0 }
        let total = Double(scheduler.currentCustomBreakType?.intervalMinutes ?? scheduler.currentSettings.eyeConfig.intervalMinutes) * 60
        return 1.0 - (remaining / max(total, 1))
    }

    private var todayCompliance: Double {
        let sessions = repository.fetchSessions(from: Calendar.current.startOfDay(for: Date()), to: Date())
        return Double(sessions.filter { $0.status == .completed }.count) / Double(max(sessions.count, 1))
    }

    var body: some View {
        VStack(spacing: 24) {
            CountdownRing(
                progress: progress,
                label: scheduler.currentCustomBreakType?.name ?? "—",
                timeString: timeString
            )
            if let pauseStatus = scheduler.pauseStatusLabel {
                Text(pauseStatus)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else if let pending = scheduler.pendingDeferredSummary {
                Text(pending)
                    .font(.headline)
                    .foregroundStyle(.orange)
            }
            VStack {
                Text("\(Int(todayCompliance * 100))%")
                    .font(.largeTitle).bold()
                Text("Today's compliance").font(.caption).foregroundStyle(.secondary)
            }
            // #22: upcoming schedule
            let upcoming = scheduler.allUpcomingBreaks
            if !upcoming.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Upcoming").font(.headline)
                    ForEach(upcoming, id: \.customTypeID) { b in
                        HStack {
                            Text(b.name)
                            Spacer()
                            let mins = max(0, Int(b.fireDate.timeIntervalSince(now)) / 60)
                            Text("in \(mins)m").foregroundStyle(.secondary).monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
                .padding(.horizontal)
            }
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Eye breaks (20-20-20)", isOn: Binding(
                    get: { scheduler.currentSettings.eyeConfig.isEnabled },
                    set: { scheduler.currentSettings.eyeConfig.isEnabled = $0; reschedule() }
                ))
                Toggle("Micro breaks", isOn: Binding(
                    get: { scheduler.currentSettings.microConfig.isEnabled },
                    set: { scheduler.currentSettings.microConfig.isEnabled = $0; reschedule() }
                ))
                Toggle("Long breaks", isOn: Binding(
                    get: { scheduler.currentSettings.longConfig.isEnabled },
                    set: { scheduler.currentSettings.longConfig.isEnabled = $0; reschedule() }
                ))
            }
            Button(scheduler.currentSettings.isPaused ? "Resume" : "Pause All") {
                scheduler.currentSettings.isPaused ? scheduler.resume() : scheduler.pause()
            }
        }
        .padding(32)
        .onReceive(tick) { now = $0 }
    }

    private func reschedule() {
        scheduler.reschedule(with: scheduler.currentSettings)
    }
}
