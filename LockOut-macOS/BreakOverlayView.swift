import SwiftUI
import LockOutCore

struct BreakOverlayView: View {
    let breakType: BreakType
    let duration: Int
    let minDisplaySeconds: Int
    let scheduler: BreakScheduler
    let repository: BreakHistoryRepository
    let onDismiss: () -> Void

    @State private var remaining: Int
    @State private var breatheScale: CGFloat = 0.5
    @State private var showTime = Date()
    @State private var tipIndex = 0
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let tipTick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var canSkip: Bool { Date().timeIntervalSince(showTime) >= Double(minDisplaySeconds) }

    init(breakType: BreakType, duration: Int, minDisplaySeconds: Int = 5, scheduler: BreakScheduler, repository: BreakHistoryRepository, onDismiss: @escaping () -> Void) {
        self.breakType = breakType
        self.duration = duration
        self.minDisplaySeconds = minDisplaySeconds
        self.scheduler = scheduler
        self.repository = repository
        self.onDismiss = onDismiss
        _remaining = State(initialValue: duration)
    }

    var body: some View {
        ZStack {
            VisualEffectBackground().ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                breakContent
                CountdownRing(
                    progress: 1.0 - Double(remaining) / Double(max(duration, 1)),
                    label: breakType.rawValue.capitalized,
                    timeString: String(format: "%02d:%02d", remaining / 60, remaining % 60)
                )
                .frame(width: 140, height: 140)
                Spacer()
                HStack {
                    Button("Snooze \(scheduler.currentCustomBreakType?.snoozeMinutes ?? scheduler.currentSettings.snoozeDurationMinutes) min") {
                        scheduler.snooze()
                        onDismiss()
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSkip)
                    Spacer()
                    Button("Skip") {
                        scheduler.skip(repository: repository)
                        onDismiss()
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSkip)
                }
                .padding(24)
            }
            .padding(40)
        }
        .onReceive(tick) { _ in
            if remaining > 0 { remaining -= 1 }
            else {
                scheduler.markCompleted(repository: repository)
                AppDelegate.shared.menuBarController?.updateStreak()
                onDismiss()
            }
        }
        .onReceive(tipTick) { _ in
            let tips = scheduler.currentCustomBreakType?.tips ?? []
            if tips.count > 1 { tipIndex = (tipIndex + 1) % tips.count }
        }
        .onAppear {
            showTime = Date()
            if breakType != .eye {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    breatheScale = 1.0
                }
            }
        }
    }

    @ViewBuilder
    private var breakContent: some View {
        let ct = scheduler.currentCustomBreakType
        let tips = ct?.tips ?? []
        let currentTip = tips.isEmpty ? nil : tips[tipIndex % tips.count]
        switch breakType {
        case .eye:
            VStack(spacing: 12) {
                Image(systemName: "eye").font(.system(size: 64))
                Text(ct?.name ?? "Eye Break").font(.title).bold()
                Text(currentTip ?? "Look at something 20 feet away for 20 seconds")
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        case .micro, .long:
            VStack(spacing: 12) {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .scaleEffect(breatheScale)
                Text(ct?.name ?? (breakType == .micro ? "Micro Break" : "Long Break")).font(.title).bold()
                Text(currentTip ?? "Relax and breathe").font(.body).foregroundStyle(.secondary)
            }
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .fullScreenUI
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
