import SwiftUI
import LockOutCore
import AppKit

struct DashboardView: View {
    let repository: BreakHistoryRepository
    @EnvironmentObject var scheduler: BreakScheduler
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var appDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }

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

    private var insightCards: [InsightCard] {
        appDelegate?.insightCards(range: 30) ?? []
    }

    private var reviewCards: [InsightCard] {
        appDelegate?.reviewSuggestionCards() ?? []
    }

    var body: some View {
        ScrollView {
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
            decisionInspector
            if !reviewCards.isEmpty {
                reviewSection
            }
            if !insightCards.isEmpty {
                insightSection
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
        }
        .padding(32)
        .onReceive(tick) { now = $0 }
    }

    private func reschedule() {
        scheduler.reschedule(with: scheduler.currentSettings)
    }

    @ViewBuilder private var decisionInspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Why LockOut?")
                    .font(.headline)
                Spacer()
                sourceBadge(scheduler.decisionTrace.effectiveSettingsSource)
            }
            inspectorRow("Active profile", scheduler.decisionTrace.activeProfileName ?? "None")
            HStack {
                inspectorRow("Activation mode", scheduler.decisionTrace.activationMode.displayName)
                Spacer()
                if scheduler.currentSettings.profileActivationMode == .manualHold {
                    Button("Return to Automatic") {
                        appDelegate?.returnToAutomaticProfileMode()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            if let matchedRuleSummary = scheduler.decisionTrace.matchedRuleSummary {
                inspectorRow("Matched rule", matchedRuleSummary)
            }
            if !scheduler.decisionTrace.activePauseReasons.isEmpty {
                inspectorRow("Pause reasons", scheduler.decisionTrace.activePauseReasons.map(\.displayName).joined(separator: ", "))
            }
            if let pending = scheduler.decisionTrace.pendingDeferredCondition {
                inspectorRow("Pending defer", pending.displayName)
            }
            if let lastSyncWriter = scheduler.decisionTrace.lastSyncWriter {
                inspectorRow("Last sync writer", lastSyncWriter)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private var reviewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("First-week review")
                    .font(.headline)
                Spacer()
                Button("Dismiss") {
                    appDelegate?.dismissReviewSuggestions()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach(reviewCards) { card in
                insightCardView(card)
            }
        }
        .padding()
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder private var insightSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Insights")
                .font(.headline)
            ForEach(insightCards) { card in
                insightCardView(card)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func insightCardView(_ card: InsightCard) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.title)
                .font(.subheadline.weight(.semibold))
            Text(card.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(card.recommendation)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption)
    }

    private func sourceBadge(_ source: EffectiveSettingsSource) -> some View {
        Text(source.displayName)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(badgeColor(for: source), in: Capsule())
            .foregroundStyle(.white)
    }

    private func badgeColor(for source: EffectiveSettingsSource) -> Color {
        switch source {
        case .local: return .gray
        case .synced: return .blue
        case .managed: return .orange
        }
    }
}
