import AppKit
import Combine
import LockOutCore
import SwiftUI

@MainActor
private final class ScheduleDebouncer: ObservableObject {
    let subject = PassthroughSubject<AppSettings, Never>()
    private var cancellable: AnyCancellable?

    func setup(scheduler: BreakScheduler) {
        guard cancellable == nil else {
            return
        }
        cancellable = subject
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak scheduler] settings in
                scheduler?.reschedule(with: settings)
            }
    }
}

private struct BreakTypeEditorContext: Identifiable {
    let id: UUID
}

struct ScheduleView: View {
    @EnvironmentObject private var scheduler: BreakScheduler
    @StateObject private var debouncer = ScheduleDebouncer()
    @State private var editorContext: BreakTypeEditorContext?

    private var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }

    private var breakTypesLocked: Bool {
        appDelegate?.managedSettings?.isForced(.customBreakTypes) ?? false
    }

    private var customTypes: Binding<[CustomBreakType]> {
        Binding(
            get: { scheduler.currentSettings.customBreakTypes },
            set: {
                scheduler.currentSettings.customBreakTypes = $0
                reschedule()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                LockOutScreenHeader(
                    title: "Schedule",
                    subtitle: "Shape the cadence of eye, micro, and recovery breaks without disturbing the scheduler logic behind them.",
                    symbol: "calendar.badge.clock",
                    accent: LockOutPalette.mint
                )

                if breakTypesLocked {
                    LockOutCard(accent: LockOutPalette.amber) {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.shield")
                                .foregroundStyle(LockOutPalette.amber)
                            Text("Break types are managed by your organization and can’t be edited here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                LockOutCard(
                    title: "Break Types",
                    subtitle: "Custom break types drive the next-break countdown, overlay behavior, and recurring schedule.",
                    icon: "list.bullet.rectangle.portrait",
                    accent: LockOutPalette.mint
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            LockOutStatusBadge(
                                "\(scheduler.currentSettings.customBreakTypes.filter(\.enabled).count) active",
                                tone: .success
                            )
                            Spacer()
                            Button("Restore Defaults", action: restoreDefaults)
                                .buttonStyle(.bordered)
                                .disabled(breakTypesLocked)
                            Button("Add Break Type", action: addBreakType)
                                .buttonStyle(.borderedProminent)
                                .disabled(breakTypesLocked)
                        }

                        if scheduler.currentSettings.customBreakTypes.isEmpty {
                            LockOutEmptyState(
                                symbol: "timer",
                                title: "No break types configured",
                                message: "Add a break type to start scheduling future sessions.",
                                accent: LockOutPalette.mint
                            )
                        } else {
                            ForEach(Array(customTypes.wrappedValue.enumerated()), id: \.element.id) { index, breakType in
                                ScheduleBreakTypeRow(
                                    breakType: breakType,
                                    isOn: customTypes[index].enabled,
                                    isLocked: breakTypesLocked,
                                    onEdit: { editorContext = BreakTypeEditorContext(id: breakType.id) },
                                    onDelete: { deleteBreakType(id: breakType.id) }
                                )
                            }
                        }
                    }
                }

                LockOutCard(
                    title: "Scheduler Notes",
                    subtitle: "LockOut can run multiple timers at once. The soonest enabled break drives the dashboard countdown and menu bar summary.",
                    icon: "sparkles",
                    accent: LockOutPalette.sky
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        LockOutKeyValueRow(label: "Upcoming breaks", value: "\(scheduler.allUpcomingBreaks.count)")
                        LockOutKeyValueRow(label: "Next break", value: scheduler.currentCustomBreakType?.name ?? "None")
                        LockOutKeyValueRow(label: "Pause state", value: scheduler.pauseStatusLabel ?? "Running")
                    }
                }
            }
            .padding(28)
        }
        .background(LockOutSceneBackground())
        .navigationTitle("Schedule")
        .onAppear {
            debouncer.setup(scheduler: scheduler)
        }
        .sheet(item: $editorContext) { context in
            if let breakTypeBinding = breakTypeBinding(for: context.id) {
                ScheduleEditorSheet(
                    breakType: breakTypeBinding,
                    dismiss: { editorContext = nil }
                )
            }
        }
    }

    private func addBreakType() {
        let newType = CustomBreakType(name: "New Break", intervalMinutes: 30, durationSeconds: 60)
        scheduler.currentSettings.customBreakTypes.append(newType)
        editorContext = BreakTypeEditorContext(id: newType.id)
        reschedule()
    }

    private func restoreDefaults() {
        scheduler.currentSettings.customBreakTypes = AppSettings.defaultCustomBreakTypes
        scheduler.reschedule(with: scheduler.currentSettings)
    }

    private func deleteBreakType(id: UUID) {
        scheduler.currentSettings.customBreakTypes.removeAll { $0.id == id }
        reschedule()
    }

    private func breakTypeBinding(for id: UUID) -> Binding<CustomBreakType>? {
        guard let index = scheduler.currentSettings.customBreakTypes.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        return customTypes[index]
    }

    private func reschedule() {
        debouncer.subject.send(scheduler.currentSettings)
    }
}

private struct ScheduleBreakTypeRow: View {
    let breakType: CustomBreakType
    @Binding var isOn: Bool
    let isLocked: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(isLocked)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(breakType.name)
                        .font(.headline)
                    LockOutStatusBadge(breakType.enabled ? "Enabled" : "Disabled", tone: breakType.enabled ? .success : .neutral)
                }

                Text("\(breakType.intervalMinutes)m interval, \(breakType.durationSeconds)s duration, \(breakType.snoozeMinutes)m snooze")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button("Edit", action: onEdit)
                    .buttonStyle(.bordered)
                    .disabled(isLocked)
                Button("Delete", action: onDelete)
                    .buttonStyle(.bordered)
                    .disabled(isLocked)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.6), lineWidth: 1)
                )
        )
    }
}

private struct ScheduleEditorSheet: View {
    @Binding var breakType: CustomBreakType
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Edit Break Type")
                        .font(.title3.weight(.semibold))
                    Text("Update timing, overlay behavior, and the prompt shown during breaks.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: dismiss)
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)

            Divider()

            CustomBreakTypeEditorView(breakType: $breakType)
                .frame(minWidth: 460, minHeight: 520)
        }
    }
}
