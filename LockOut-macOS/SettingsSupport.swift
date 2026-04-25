import AppKit
import EventKit
import LockOutCore
import SwiftUI

struct SettingsPreviewDiff {
    let label: String
    let fromValue: String
    let toValue: String
}

enum SettingsUIHelpers {
    static let workdayTimeSlots = stride(from: 0, to: 1440, by: 30).map { $0 }

    static func formatMinutes(_ mins: Int) -> String {
        LockOutFormatters.clockTime(minutes: mins / 60, seconds: mins % 60)
    }
}

enum SettingsTransferPanels {
    static func chooseImportURL() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseExportURL(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = defaultName
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func confirm(title: String, message: String, confirmTitle: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func showWarning(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

struct CalendarSelectionSection: View {
    @Binding var selectedIDs: [String]
    let isDisabled: Bool

    @State private var calendars: [EKCalendar] = []
    @State private var accessMessage = "Loading calendars..."

    private let store = EKEventStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected calendars")
                .font(.subheadline)
                .fontWeight(.semibold)
            if calendars.isEmpty {
                Text(accessMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Button("Select All") {
                        selectedIDs = calendars.map(\.calendarIdentifier)
                    }
                    Button("Clear All") {
                        selectedIDs = []
                    }
                }
                .disabled(isDisabled)

                ForEach(calendars, id: \.calendarIdentifier) { calendar in
                    Toggle(
                        "\(calendar.title) (\(calendar.source.title))",
                        isOn: Binding(
                            get: { selectedIDs.contains(calendar.calendarIdentifier) },
                            set: { selected in
                                if selected {
                                    if !selectedIDs.contains(calendar.calendarIdentifier) {
                                        selectedIDs.append(calendar.calendarIdentifier)
                                    }
                                } else {
                                    selectedIDs.removeAll { $0 == calendar.calendarIdentifier }
                                }
                            }
                        )
                    )
                    .disabled(isDisabled)
                }
            }
        }
        .task { await loadCalendars() }
    }

    private func loadCalendars() async {
        let granted = await withCheckedContinuation { continuation in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        guard granted else {
            accessMessage = "Calendar access is required to pick specific calendars."
            calendars = []
            return
        }
        let available = store.calendars(for: .event).sorted { lhs, rhs in
            if lhs.source.title == rhs.source.title { return lhs.title < rhs.title }
            return lhs.source.title < rhs.source.title
        }
        calendars = available
        accessMessage = available.isEmpty ? "No calendars are available on this Mac." : ""
    }
}

struct BundleIDSelectionSection: View {
    @Binding var selectedBundleIDs: [String]
    let isDisabled: Bool
    let caption: String

    @State private var manualBundleID = ""

    private var runningApplications: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(runningApplications, id: \.processIdentifier) { app in
                let bundleID = app.bundleIdentifier ?? ""
                Toggle(app.localizedName ?? bundleID, isOn: toggleBinding(for: bundleID))
                    .disabled(isDisabled)
            }

            HStack {
                TextField("Manual bundle ID", text: $manualBundleID)
                    .accessibilityIdentifier("bundle.manual")
                    .accessibilityLabel("Manual bundle ID")
                Button("Add", action: addManualBundleID)
                    .accessibilityIdentifier("bundle.add")
                    .disabled(isDisabled)
            }

            ForEach(Array(Set(selectedBundleIDs)).sorted(), id: \.self) { bundleID in
                HStack {
                    Text(bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") {
                        selectedBundleIDs.removeAll { $0 == bundleID }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .disabled(isDisabled)
                }
            }
        }
    }

    private func toggleBinding(for bundleID: String) -> Binding<Bool> {
        Binding(
            get: { selectedBundleIDs.contains(bundleID) },
            set: { selected in
                if selected {
                    if !selectedBundleIDs.contains(bundleID) {
                        selectedBundleIDs.append(bundleID)
                    }
                } else {
                    selectedBundleIDs.removeAll { $0 == bundleID }
                }
            }
        )
    }

    private func addManualBundleID() {
        let bundleID = manualBundleID.trimmingCharacters(in: .whitespaces)
        guard !bundleID.isEmpty, !selectedBundleIDs.contains(bundleID), isValidBundleID(bundleID) else { return }
        selectedBundleIDs.append(bundleID)
        manualBundleID = ""
    }

    private func isValidBundleID(_ id: String) -> Bool {
        id.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil
    }
}

struct HotkeyRecorderHelper: NSViewRepresentable {
    @Binding var isRecording: Bool
    let onCapture: (Int, Int) -> Void

    final class Coordinator {
        var monitorToken: Any?

        deinit {
            if let monitorToken {
                NSEvent.removeMonitor(monitorToken)
            }
        }

        func removeMonitorIfNeeded() {
            if let monitorToken {
                NSEvent.removeMonitor(monitorToken)
                self.monitorToken = nil
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isRecording {
            guard context.coordinator.monitorToken == nil else { return }
            context.coordinator.monitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let keyCode = Int(event.keyCode)
                let flags = Int(event.modifierFlags.rawValue)
                onCapture(keyCode, flags)
                isRecording = false
                context.coordinator.removeMonitorIfNeeded()
                return nil
            }
        } else {
            context.coordinator.removeMonitorIfNeeded()
        }
    }
}
