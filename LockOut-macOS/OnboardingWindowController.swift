import AppKit
import EventKit
import LockOutCore
import SwiftUI
import UserNotifications

final class OnboardingWindowController: NSWindowController {
    private static var instance: OnboardingWindowController?

    static func present(scheduler: BreakScheduler) {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Welcome to LockOut"
        win.center()
        win.contentView = NSHostingView(rootView: OnboardingView(scheduler: scheduler) { win.close() })
        let ctrl = OnboardingWindowController(window: win)
        instance = ctrl
        ctrl.showWindow(nil)
    }
}

private enum OnboardingPreset: String, CaseIterable, Identifiable {
    case agentDeveloper
    case developerFocus
    case strictRecovery
    case managerCalendarFirst
    case writerGentleRoutine
    case consultantMultiMac
    case managedTeam

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agentDeveloper: return "Agent Developer"
        case .developerFocus: return "Developer Focus"
        case .strictRecovery: return "Strict Recovery"
        case .managerCalendarFirst: return "Manager Calendar-First"
        case .writerGentleRoutine: return "Writer Gentle Routine"
        case .consultantMultiMac: return "Consultant Multi-Mac"
        case .managedTeam: return "Managed Team"
        }
    }

    var summary: String {
        switch self {
        case .agentDeveloper:
            return "Bootstraps profiles for coding sprints, eval runs, and incident windows."
        case .developerFocus:
            return "Focus-aware reminders, workday scheduling, and a faster pre-break warning."
        case .strictRecovery:
            return "Stricter cadence and enforcement for users actively protecting eyes, posture, or RSI recovery."
        case .managerCalendarFirst:
            return "Meeting-aware breaks that stay out of the way during busy calendar blocks."
        case .writerGentleRoutine:
            return "A lighter rhythm for long writing sessions with fewer hard interruptions."
        case .consultantMultiMac:
            return "A sync-friendly setup designed to feel consistent across more than one Mac."
        case .managedTeam:
            return "A policy-friendly baseline for managed environments and mandatory break routines."
        }
    }

    func applying(to settings: AppSettings) -> AppSettings {
        var updated = settings
        switch self {
        case .agentDeveloper:
            updated.activeRole = .developer
            let result = AgentDeveloperPresets.bootstrap(into: &updated)
            if let firstProfileName = result.addedProfiles.first,
               let profile = updated.profiles.first(where: { $0.name == firstProfileName }) {
                updated.apply(profile: profile)
                updated.activeProfileId = profile.id
            }
        case .developerFocus:
            updated.pauseDuringFocus = true
            updated.pauseDuringCalendarEvents = false
            updated.workdayStartMinutes = 9 * 60
            updated.workdayEndMinutes = 18 * 60
            updated.notificationLeadMinutes = 2
            updated.breakEnforcementMode = .reminder
            updated.snoozeDurationMinutes = 5
        case .strictRecovery:
            updated.customBreakTypes = [
                CustomBreakType(name: "Eye Break", intervalMinutes: 20, durationSeconds: 30, minDisplaySeconds: 15, tips: ["Look 20 feet away and blink slowly"], overlayOpacity: 0.9, snoozeMinutes: 3),
                CustomBreakType(name: "Micro Break", intervalMinutes: 35, durationSeconds: 60, minDisplaySeconds: 20, tips: ["Drop your shoulders and loosen your grip"], overlayOpacity: 0.9, snoozeMinutes: 3),
                CustomBreakType(name: "Long Break", intervalMinutes: 75, durationSeconds: 600, minDisplaySeconds: 30, tips: ["Stand up, stretch, and step away"], overlayOpacity: 0.95, snoozeMinutes: 5),
            ]
            updated.breakEnforcementMode = .hardLock
            updated.notificationLeadMinutes = 1
            updated.snoozeDurationMinutes = 3
            updated.pauseDuringFocus = false
            updated.pauseDuringCalendarEvents = false
        case .managerCalendarFirst:
            updated.pauseDuringCalendarEvents = true
            updated.calendarFilterMode = .busyOnly
            updated.pauseDuringFocus = false
            updated.workdayStartMinutes = 9 * 60
            updated.workdayEndMinutes = 18 * 60
            updated.notificationLeadMinutes = 5
            updated.breakEnforcementMode = .reminder
        case .writerGentleRoutine:
            updated.customBreakTypes = [
                CustomBreakType(name: "Eye Break", intervalMinutes: 25, durationSeconds: 20, minDisplaySeconds: 5, tips: ["Look past the screen and relax your gaze"], snoozeMinutes: 5),
                CustomBreakType(name: "Micro Break", intervalMinutes: 60, durationSeconds: 45, minDisplaySeconds: 10, tips: ["Unclench your jaw and drop your shoulders"], snoozeMinutes: 5),
                CustomBreakType(name: "Long Break", intervalMinutes: 120, durationSeconds: 600, minDisplaySeconds: 15, tips: ["Leave the desk and reset"], snoozeMinutes: 10),
            ]
            updated.breakEnforcementMode = .reminder
            updated.notificationLeadMinutes = 1
            updated.pauseDuringFocus = false
            updated.pauseDuringCalendarEvents = false
        case .consultantMultiMac:
            updated.pauseDuringCalendarEvents = true
            updated.calendarFilterMode = .busyOnly
            updated.pauseDuringFocus = true
            updated.workdayStartMinutes = 8 * 60 + 30
            updated.workdayEndMinutes = 18 * 60
            updated.notificationLeadMinutes = 2
            updated.breakEnforcementMode = .softLock
            updated.localOnlyMode = false
        case .managedTeam:
            updated.activeRole = .itManaged
            updated.pauseDuringCalendarEvents = true
            updated.pauseDuringFocus = true
            updated.workdayStartMinutes = 9 * 60
            updated.workdayEndMinutes = 17 * 60
            updated.notificationLeadMinutes = 2
            updated.breakEnforcementMode = .softLock
            updated.snoozeDurationMinutes = 5
        }
        return updated
    }
}

struct OnboardingView: View {
    let scheduler: BreakScheduler
    let onFinish: () -> Void

    @State private var page = 0
    @State private var selectedPreset: OnboardingPreset = .developerFocus
    @State private var enableCalendar = false
    @State private var enableFocus = false

    private var appDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }
    private var managedSnapshot: ManagedSettingsSnapshot? { appDelegate?.managedSettings }
    private var presets: [OnboardingPreset] {
        managedSnapshot == nil ? OnboardingPreset.allCases : [.managedTeam]
    }

    var body: some View {
        TabView(selection: $page) {
            presetSelection.tag(0)
            permissionsPage.tag(1)
            integrationsPage.tag(2)
            launchPage.tag(3)
        }
        .tabViewStyle(.automatic)
        .frame(width: 560, height: 620)
        .accessibilityIdentifier("onboarding.root")
        .onAppear {
            if managedSnapshot != nil {
                selectedPreset = .managedTeam
                enableCalendar = scheduler.currentSettings.pauseDuringCalendarEvents
                enableFocus = scheduler.currentSettings.pauseDuringFocus
            }
        }
    }

    private var presetSelection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Choose a working style")
                .font(.largeTitle).bold()
            Text("LockOut will start with a preset tuned for how you work. You can refine it later in Settings and Profiles.")
                .foregroundStyle(.secondary)

            if let managedSnapshot {
                Text("Your organization manages these settings: \(managedSnapshot.forcedKeys.map(\.displayName).sorted().joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(presets) { preset in
                Button {
                    selectedPreset = preset
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(preset.title).font(.headline)
                            Spacer()
                            if selectedPreset == preset {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.blue)
                            }
                        }
                        Text(preset.summary)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selectedPreset == preset ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("onboarding.preset.\(preset.rawValue)")
                .accessibilityLabel(preset.title)
                .disabled(managedSnapshot != nil && preset != .managedTeam)
            }

            Spacer()
            Button("Continue") {
                applyPreset()
                page = 1
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("onboarding.continue")
        }
        .padding(32)
    }

    private var permissionsPage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "bell.badge")
                .font(.system(size: 64))
            Text("Enable essential permissions")
                .font(.title).bold()
            Text("Notifications let LockOut warn you before a break. Calendar access powers selected-calendar and busy-time pauses.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Allow Notifications") {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                        if let error {
                            FileLogger.shared.log(.error, category: "Onboarding", "notification permission request failed: \(error)")
                            DiagnosticsStore.shared.record(level: .error, category: "Onboarding", message: "notification permission request failed: \(error.localizedDescription)")
                            return
                        }
                        FileLogger.shared.log(.info, category: "Onboarding", "notification permission granted=\(granted)")
                        DiagnosticsStore.shared.record(level: .info, category: "Onboarding", message: "notification permission granted=\(granted)")
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Allow Calendar Access") {
                    EKEventStore().requestFullAccessToEvents { granted, error in
                        if let error {
                            FileLogger.shared.log(.error, category: "Onboarding", "calendar permission request failed: \(error)")
                            DiagnosticsStore.shared.record(level: .error, category: "Onboarding", message: "calendar permission request failed: \(error.localizedDescription)")
                            return
                        }
                        FileLogger.shared.log(.info, category: "Onboarding", "calendar permission granted=\(granted)")
                        DiagnosticsStore.shared.record(level: .info, category: "Onboarding", message: "calendar permission granted=\(granted)")
                    }
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button("Next") { page = 2 }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("onboarding.permissions.next")
        }
        .padding(40)
    }

    private var integrationsPage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 64))
            Text("Confirm live integrations")
                .font(.title).bold()
            Text("Use these only where they help. Managed settings are shown but cannot be changed here.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Toggle("Pause during Calendar events", isOn: $enableCalendar)
                .disabled(isManaged(.pauseDuringCalendarEvents))
            Toggle("Pause during Focus Mode", isOn: $enableFocus)
                .disabled(isManaged(.pauseDuringFocus))

            if let managedSnapshot {
                Text("Managed setup active from \(managedSnapshot.metadata.source).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Button("Next") {
                scheduler.currentSettings.pauseDuringCalendarEvents = enableCalendar
                scheduler.currentSettings.pauseDuringFocus = enableFocus
                if let appDelegate {
                    scheduler.reschedule(with: appDelegate.applyManagedSettings(to: scheduler.currentSettings))
                } else {
                    scheduler.reschedule(with: scheduler.currentSettings)
                }
                page = 3
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("onboarding.integrations.next")
        }
        .padding(40)
    }

    private var launchPage: some View {
        VStack(spacing: 18) {
            Spacer()
            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { LaunchAtLoginService.isEnabled },
                    set: { $0 ? LaunchAtLoginService.enable() : LaunchAtLoginService.disable() }
                )
            )
            Text("Preset: \(selectedPreset.title)")
                .font(.headline)
            Text("LockOut lives in your menu bar. You can change your preset later by saving a full profile in the app.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Get Started") {
                UserDefaults.standard.set(true, forKey: "hasOnboarded")
                UserDefaults.standard.set(true, forKey: "hasSeenMainWindow")
                onFinish()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("onboarding.getStarted")
        }
        .padding(40)
    }

    private func applyPreset() {
        let presetSettings = selectedPreset.applying(to: scheduler.currentSettings)
        let resolved = appDelegate?.applyManagedSettings(to: presetSettings) ?? presetSettings
        scheduler.reschedule(with: resolved)
        enableCalendar = resolved.pauseDuringCalendarEvents
        enableFocus = resolved.pauseDuringFocus
    }

    private func isManaged(_ key: ManagedSettingsKey) -> Bool {
        managedSnapshot?.isForced(key) ?? false
    }
}
