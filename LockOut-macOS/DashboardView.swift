import AppKit
import LockOutCore
import SwiftUI

struct DashboardView: View {
    let repository: BreakHistoryRepository

    @EnvironmentObject private var scheduler: BreakScheduler
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }

    private var todaySessions: [BreakSession] {
        repository.fetchSessions(from: Calendar.current.startOfDay(for: Date()), to: Date())
    }

    private var completedToday: Int {
        todaySessions.filter { $0.status == .completed }.count
    }

    private var todayCompliance: Double {
        Double(completedToday) / Double(max(todaySessions.count, 1))
    }

    private var remaining: TimeInterval {
        guard let nextBreak = scheduler.nextBreak else {
            return 0
        }
        return max(0, nextBreak.fireDate.timeIntervalSince(now))
    }

    private var timeString: String {
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return LockOutFormatters.clockTime(minutes: minutes, seconds: seconds)
    }

    private var progress: Double {
        guard scheduler.nextBreak != nil else {
            return 0
        }
        let total = Double(
            scheduler.currentCustomBreakType?.intervalMinutes
                ?? scheduler.currentSettings.eyeConfig.intervalMinutes
        ) * 60
        return 1.0 - (remaining / max(total, 1))
    }

    private var insightCards: [InsightCard] {
        appDelegate?.insightCards(range: 30) ?? []
    }

    private var reviewCards: [InsightCard] {
        appDelegate?.reviewSuggestionCards() ?? []
    }

    private var enabledBreakTypes: Int {
        scheduler.currentSettings.customBreakTypes.filter(\.enabled).count
    }

    private var nextBreakName: String {
        scheduler.currentCustomBreakType?.name ?? "Break"
    }

    private var nextBreakDateSummary: String {
        guard let fireDate = scheduler.nextBreak?.fireDate else {
            return "Enable a break type to start scheduling again."
        }
        return "Scheduled for \(fireDate.formatted(.dateTime.hour().minute()))"
    }

    private var headerSummary: String {
        if let pauseStatus = scheduler.pauseStatusLabel {
            return pauseStatus
        }
        if let pendingDeferred = scheduler.pendingDeferredSummary {
            return pendingDeferred
        }
        return nextBreakDateSummary
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 14)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LockOutScreenHeader(
                    title: "Dashboard",
                    subtitle: "Monitor the next break, review today’s compliance, and keep the active routine in sight.",
                    symbol: "sparkles.rectangle.stack",
                    accent: LockOutPalette.sky
                )

                heroCard

                LazyVGrid(columns: metricColumns, spacing: 14) {
                    LockOutMetricTile(
                        value: "\(Int(todayCompliance * 100))%",
                        label: "Today's compliance",
                        detail: "\(completedToday) of \(max(todaySessions.count, 0)) sessions completed",
                        accent: LockOutPalette.sky
                    )
                    LockOutMetricTile(
                        value: "\(enabledBreakTypes)",
                        label: "Enabled break types",
                        detail: enabledBreakTypes == 1 ? "One routine is active" : "Multiple routines are active",
                        accent: LockOutPalette.mint
                    )
                    LockOutMetricTile(
                        value: "\(scheduler.allUpcomingBreaks.count)",
                        label: "Queued breaks",
                        detail: scheduler.allUpcomingBreaks.isEmpty ? "Nothing is scheduled yet" : "Across the current workday",
                        accent: LockOutPalette.amber
                    )
                    LockOutMetricTile(
                        value: "\(todaySessions.count)",
                        label: "Sessions logged today",
                        detail: todaySessions.isEmpty ? "No recorded sessions yet" : "Includes completed, skipped, snoozed, and deferred",
                        accent: LockOutPalette.coral
                    )
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        leftColumn
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        rightColumn
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        leftColumn
                        rightColumn
                    }
                }
            }
            .padding(28)
        }
        .background(LockOutSceneBackground())
        .onReceive(tick) { now = $0 }
    }

    private var heroCard: some View {
        LockOutCard(accent: LockOutPalette.sky) {
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        LockOutStatusBadge(
                            scheduler.pauseStatusLabel == nil ? "Running" : "Paused",
                            tone: scheduler.pauseStatusLabel == nil ? .success : .warning
                        )
                        LockOutStatusBadge(sourceTitle, tone: sourceTone)
                        if scheduler.currentSettings.profileActivationMode == .manualHold {
                            LockOutStatusBadge("Manual Hold", tone: .warning)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(heroTitle)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(LockOutPalette.slate)

                        Text(headerSummary)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button(primaryActionTitle, action: togglePause)
                            .buttonStyle(.borderedProminent)

                        if scheduler.currentSettings.profileActivationMode == .manualHold {
                            Button("Return to Automatic") {
                                appDelegate?.returnToAutomaticProfileMode()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                Spacer(minLength: 20)

                CountdownRing(
                    progress: progress,
                    label: nextBreakName,
                    timeString: timeString
                )
                .frame(width: 150, height: 150)
            }
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            LockOutCard(
                title: "Break Controls",
                subtitle: "Toggle the built-in break rhythms without opening settings.",
                icon: "switch.2",
                accent: LockOutPalette.mint
            ) {
                VStack(spacing: 12) {
                    DashboardRoutineToggle(
                        title: "Eye breaks",
                        subtitle: "20-20-20 cadence",
                        isOn: eyeBreakBinding
                    )
                    DashboardRoutineToggle(
                        title: "Micro breaks",
                        subtitle: "Short resets between work blocks",
                        isOn: microBreakBinding
                    )
                    DashboardRoutineToggle(
                        title: "Long breaks",
                        subtitle: "Recovery breaks for heavier sessions",
                        isOn: longBreakBinding
                    )
                }
            }

            LockOutCard(
                title: "Upcoming",
                subtitle: "Everything currently queued by the scheduler.",
                icon: "clock.arrow.circlepath",
                accent: LockOutPalette.amber
            ) {
                if scheduler.allUpcomingBreaks.isEmpty {
                    LockOutEmptyState(
                        symbol: "calendar.badge.exclamationmark",
                        title: "No breaks queued",
                        message: "Enable at least one break type to populate the schedule."
                    )
                } else {
                    VStack(spacing: 12) {
                        ForEach(scheduler.allUpcomingBreaks, id: \.customTypeID) { upcomingBreak in
                            DashboardTimelineRow(
                                title: upcomingBreak.name,
                                relativeTime: relativeTime(for: upcomingBreak.fireDate),
                                exactTime: upcomingBreak.fireDate.formatted(.dateTime.hour().minute())
                            )
                        }
                    }
                }
            }
        }
    }

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            LockOutCard(
                title: "Why LockOut?",
                subtitle: "Decision trace for the current profile and policy state.",
                icon: "waveform.path.ecg.text.page",
                accent: LockOutPalette.sky
            ) {
                VStack(spacing: 10) {
                    LockOutKeyValueRow(label: "Active profile", value: scheduler.decisionTrace.activeProfileName ?? "None")
                    LockOutKeyValueRow(label: "Activation mode", value: scheduler.decisionTrace.activationMode.displayName)
                    if let matchedRuleSummary = scheduler.decisionTrace.matchedRuleSummary {
                        LockOutKeyValueRow(label: "Matched rule", value: matchedRuleSummary)
                    }
                    if !scheduler.decisionTrace.activePauseReasons.isEmpty {
                        LockOutKeyValueRow(
                            label: "Pause reasons",
                            value: scheduler.decisionTrace.activePauseReasons.map(\.displayName).joined(separator: ", ")
                        )
                    }
                    if let pendingDeferred = scheduler.decisionTrace.pendingDeferredCondition {
                        LockOutKeyValueRow(label: "Pending defer", value: pendingDeferred.displayName)
                    }
                    if let lastSyncWriter = scheduler.decisionTrace.lastSyncWriter {
                        LockOutKeyValueRow(label: "Last sync writer", value: lastSyncWriter)
                    }
                }
            }

            if !reviewCards.isEmpty {
                insightDeck(
                    title: "First-week review",
                    subtitle: "Suggestions from recent break behavior.",
                    accent: LockOutPalette.amber,
                    cards: reviewCards,
                    dismissAction: dismissReviewSuggestions
                )
            }

            if !insightCards.isEmpty {
                insightDeck(
                    title: "Insights",
                    subtitle: "Behavioral patterns derived from the last few weeks.",
                    accent: LockOutPalette.mint,
                    cards: insightCards
                )
            }
        }
    }

    private var heroTitle: String {
        scheduler.pauseStatusLabel == nil ? "Next \(nextBreakName)" : "Breaks are paused"
    }

    private var primaryActionTitle: String {
        isManuallyPaused ? "Resume Breaks" : "Pause All"
    }

    private var isManuallyPaused: Bool {
        scheduler.activePauseReasons.contains(.manual)
    }

    private var sourceTitle: String {
        scheduler.decisionTrace.effectiveSettingsSource.displayName
    }

    private var sourceTone: LockOutBadgeTone {
        switch scheduler.decisionTrace.effectiveSettingsSource {
        case .local:
            return .neutral
        case .synced:
            return .info
        case .managed:
            return .warning
        }
    }

    private var eyeBreakBinding: Binding<Bool> {
        Binding(
            get: { scheduler.currentSettings.eyeConfig.isEnabled },
            set: { scheduler.currentSettings.eyeConfig.isEnabled = $0; reschedule() }
        )
    }

    private var microBreakBinding: Binding<Bool> {
        Binding(
            get: { scheduler.currentSettings.microConfig.isEnabled },
            set: { scheduler.currentSettings.microConfig.isEnabled = $0; reschedule() }
        )
    }

    private var longBreakBinding: Binding<Bool> {
        Binding(
            get: { scheduler.currentSettings.longConfig.isEnabled },
            set: { scheduler.currentSettings.longConfig.isEnabled = $0; reschedule() }
        )
    }

    private func togglePause() {
        if isManuallyPaused {
            scheduler.resume()
        } else {
            scheduler.pause()
        }
    }

    private func reschedule() {
        scheduler.reschedule(with: scheduler.currentSettings)
    }

    private func relativeTime(for date: Date) -> String {
        let remainingSeconds = max(0, Int(date.timeIntervalSince(now)))
        let hours = remainingSeconds / 3600
        let minutes = (remainingSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    @ViewBuilder
    private func insightDeck(
        title: String,
        subtitle: String,
        accent: Color,
        cards: [InsightCard],
        dismissAction: (() -> Void)? = nil
    ) -> some View {
        LockOutCard(title: title, subtitle: subtitle, icon: "lightbulb", accent: accent) {
            VStack(alignment: .leading, spacing: 12) {
                if let dismissAction {
                    HStack {
                        Spacer()
                        Button("Dismiss", action: dismissAction)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                ForEach(cards) { card in
                    LockOutInsightRow(card: card, accent: accent)
                }
            }
        }
    }

    private func dismissReviewSuggestions() {
        appDelegate?.dismissReviewSuggestions()
    }
}

private struct DashboardRoutineToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: LockOutLayout.cornerRadius)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: LockOutLayout.cornerRadius)
                        .strokeBorder(LockOutPalette.separator.opacity(0.35), lineWidth: 1)
                )
        )
    }
}

private struct DashboardTimelineRow: View {
    let title: String
    let relativeTime: String
    let exactTime: String

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .fill(LockOutPalette.sky)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text("Starts in \(relativeTime)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text(exactTime)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(LockOutPalette.slate)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}
