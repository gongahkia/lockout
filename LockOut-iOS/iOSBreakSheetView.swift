import SwiftUI
import LockOutCore

struct iOSBreakSheetView: View {
    let breakType: BreakType
    let duration: Int
    let onDismiss: () -> Void

    @State private var remaining: Int
    @State private var breatheScale: CGFloat = 0.5
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var delegate: iOSAppDelegate { .shared }

    init(breakType: BreakType, duration: Int, onDismiss: @escaping () -> Void) {
        self.breakType = breakType; self.duration = duration; self.onDismiss = onDismiss
        _remaining = State(initialValue: duration)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                if breakType == .eye {
                    Image(systemName: "eye").font(.system(size: 64)).foregroundColor(.white)
                    Text("Eye Break").font(.title).bold().foregroundColor(.white)
                    Text("Look at something 20 feet away").foregroundColor(.white.opacity(0.7))
                } else {
                    Circle().fill(Color.blue.opacity(0.4)).frame(width: 80, height: 80).scaleEffect(breatheScale)
                    Text(breakType == .micro ? "Micro Break" : "Long Break").font(.title).bold().foregroundColor(.white)
                    Text("Relax and breathe").foregroundColor(.white.opacity(0.7))
                }
                CountdownRingView(progress: 1 - Double(remaining) / Double(max(duration, 1)),
                                  timeString: String(format: "%02d:%02d", remaining / 60, remaining % 60))
                Spacer()
                HStack {
                    Button("Snooze \(delegate.settings.snoozeDurationMinutes) min") { onDismiss() }
                        .foregroundColor(.white)
                    Spacer()
                    Button("Done") {
                        delegate.repository.save(BreakSession(type: breakType, scheduledAt: Date(), endedAt: Date(), status: .completed))
                        onDismiss()
                    }.foregroundColor(.white)
                }.padding(24)
            }
        }
        .onReceive(tick) { _ in
            if remaining > 0 { remaining -= 1 } else { onDismiss() }
        }
        .onAppear {
            if breakType != .eye {
                withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { breatheScale = 1 }
            }
        }
    }
}

struct CountdownRingView: View {
    let progress: Double
    let timeString: String
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.3), lineWidth: 8)
            Circle().trim(from: 0, to: progress)
                .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .foregroundColor(.white)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
            Text(timeString).font(.title2.monospacedDigit()).bold().foregroundColor(.white)
        }.frame(width: 120, height: 120)
    }
}
