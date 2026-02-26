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
    @State private var editingIndex: Int? = nil
    @State private var showEditor = false

    private var customTypes: Binding<[CustomBreakType]> {
        Binding(
            get: { scheduler.currentSettings.customBreakTypes },
            set: { scheduler.currentSettings.customBreakTypes = $0; reschedule() }
        )
    }

    var body: some View {
        Form {
            Section("Break Types") {
                List {
                    ForEach(customTypes.wrappedValue.indices, id: \.self) { i in
                        HStack {
                            Toggle("", isOn: customTypes[i].enabled)
                                .labelsHidden()
                            Text(customTypes.wrappedValue[i].name)
                            Spacer()
                            Text("\(customTypes.wrappedValue[i].intervalMinutes)m / \(customTypes.wrappedValue[i].durationSeconds)s")
                                .foregroundStyle(.secondary).font(.caption)
                            Button("Edit") { editingIndex = i; showEditor = true }
                                .buttonStyle(.plain)
                        }
                    }
                    .onDelete { customTypes.wrappedValue.remove(atOffsets: $0); reschedule() }
                    .onMove { customTypes.wrappedValue.move(fromOffsets: $0, toOffset: $1); reschedule() }
                }
                Button("Add Break Type") {
                    var newType = CustomBreakType(name: "New Break", intervalMinutes: 30, durationSeconds: 60)
                    scheduler.currentSettings.customBreakTypes.append(newType)
                    editingIndex = scheduler.currentSettings.customBreakTypes.count - 1
                    showEditor = true
                    reschedule()
                }
            }
            Button("Restore Defaults") {
                scheduler.currentSettings.customBreakTypes = AppSettings.defaultCustomBreakTypes
                scheduler.reschedule(with: scheduler.currentSettings)
            }
        }
        .padding(24)
        .navigationTitle("Schedule")
        .onAppear { debouncer.setup(scheduler: scheduler) }
        .sheet(isPresented: $showEditor) {
            if let i = editingIndex {
                VStack {
                    CustomBreakTypeEditorView(breakType: customTypes[i])
                        .frame(minWidth: 400)
                    Button("Done") { showEditor = false }
                        .padding()
                }
            }
        }
    }

    private func reschedule() { debouncer.subject.send(scheduler.currentSettings) }
}
