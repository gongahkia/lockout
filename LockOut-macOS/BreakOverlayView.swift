import SwiftUI
import LockOutCore

struct BreakOverlayView: View {
    let breakType: BreakType
    let duration: Int
    let scheduler: BreakScheduler
    let repository: BreakHistoryRepository
    let onDismiss: () -> Void

    @State private var remaining: Int
    @State private var breatheScale: CGFloat = 0.5
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(breakType: BreakType, duration: Int, scheduler: BreakScheduler, repository: BreakHistoryRepository, onDismiss: @escaping () -> Void) {
        self.breakType = breakType
        self.duration = duration
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
                    Button("Snooze \(scheduler.currentSettings.snoozeDurationMinutes) min") {
                        scheduler.snooze(minutes: scheduler.currentSettings.snoozeDurationMinutes)
                        onDismiss()
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button("Skip") {
                        scheduler.skip(repository: repository)
                        onDismiss()
                    }
                    .buttonStyle(.plain)
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
        .onAppear {
            if breakType != .eye {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                    breatheScale = 1.0
                }
            }
        }
    }

    @ViewBuilder
    private var breakContent: some View {
        switch breakType {
        case .eye:
            VStack(spacing: 12) {
                Image(systemName: "eye").font(.system(size: 64))
                Text("Eye Break").font(.title).bold()
                Text("Look at something 20 feet away for 20 seconds")
                    .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        case .micro, .long:
            VStack(spacing: 12) {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .scaleEffect(breatheScale)
                Text(breakType == .micro ? "Micro Break" : "Long Break").font(.title).bold()
                Text("Relax and breathe").font(.body).foregroundStyle(.secondary)
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
