import AppKit
import SwiftUI
import LockOutCore

struct BreakOverlayView: View {
    let breakType: BreakType
    let duration: Int
    let minDisplaySeconds: Int
    let scheduledAt: Date
    let scheduler: BreakScheduler
    let repository: BreakHistoryRepository
    let cloudSync: CloudKitSyncService
    let onDismiss: () -> Void

    @State private var remaining: Int
    @State private var breatheScale: CGFloat = 0.5
    @State private var showTime = Date()
    @State private var tipIndex = 0
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let tipTick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var elapsed: TimeInterval { Date().timeIntervalSince(showTime) }
    private var canSkip: Bool { elapsed >= Double(minDisplaySeconds) }
    private var appDelegate: AppDelegate? { NSApp.delegate as? AppDelegate }
    private var canBypass: Bool {
        scheduler.currentSettings.rolePolicies
            .first(where: { $0.role == scheduler.currentSettings.activeRole })?
            .canBypassBreak ?? true
    }
    private var emergencyEscapeAvailable: Bool { elapsed >= 30 }
    private var enforcementMode: BreakEnforcementMode { scheduler.currentSettings.breakEnforcementMode }
    private var showSkipSnoozeButtons: Bool {
        switch enforcementMode {
        case .reminder: return true
        case .softLock: return canBypass
        case .hardLock: return canBypass && emergencyEscapeAvailable
        }
    }
    private var controlsEnabled: Bool {
        switch enforcementMode {
        case .reminder: return canSkip && canBypass
        case .softLock: return canSkip && canBypass
        case .hardLock: return emergencyEscapeAvailable && canBypass
        }
    }
    private var showEmergencyExit: Bool {
        switch enforcementMode {
        case .reminder: return false
        case .softLock, .hardLock: return emergencyEscapeAvailable
        }
    }
    private var deferredOptions: [ManualDeferredOption] {
        appDelegate?.availableDeferredOptions() ?? []
    }
    private var primaryMessage: String {
        scheduler.currentCustomBreakType?.message ?? defaultMessage
    }
    private var secondaryTip: String? {
        let tips = scheduler.currentCustomBreakType?.tips ?? []
        guard !tips.isEmpty else { return nil }
        return tips[tipIndex % tips.count]
    }
    private var defaultMessage: String {
        switch breakType {
        case .eye:
            return "Look at something 20 feet away for 20 seconds"
        case .micro, .long:
            return "Relax and breathe"
        }
    }

    init(breakType: BreakType, duration: Int, minDisplaySeconds: Int = 5, scheduledAt: Date, scheduler: BreakScheduler, repository: BreakHistoryRepository, cloudSync: CloudKitSyncService, onDismiss: @escaping () -> Void) {
        self.breakType = breakType
        self.duration = duration
        self.minDisplaySeconds = minDisplaySeconds
        self.scheduledAt = scheduledAt
        self.scheduler = scheduler
        self.repository = repository
        self.cloudSync = cloudSync
        self.onDismiss = onDismiss
        _remaining = State(initialValue: duration)
    }

    var body: some View {
        let overlayColor = Color(hex: scheduler.currentCustomBreakType?.overlayColorHex ?? "#000000")
        let overlayOpacity = scheduler.currentCustomBreakType?.overlayOpacity ?? 0.85
        ZStack {
            VisualEffectBackground().ignoresSafeArea()
            overlayColor.opacity(overlayOpacity).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                breakContent
                CountdownRing(
                    progress: 1.0 - Double(remaining) / Double(max(duration, 1)),
                    label: scheduler.currentCustomBreakType?.name ?? breakType.rawValue.capitalized,
                    timeString: LockOutFormatters.clockTime(minutes: remaining / 60, seconds: remaining % 60)
                )
                .frame(width: 140, height: 140)
                Spacer()
                if showSkipSnoozeButtons {
                    HStack {
                        Button("Snooze \(scheduler.currentCustomBreakType?.snoozeMinutes ?? scheduler.currentSettings.snoozeDurationMinutes) min") {
                            scheduler.snooze(repository: repository, cloudSync: cloudSync)
                            onDismiss()
                        }
                        .buttonStyle(.plain)
                        .disabled(!controlsEnabled)
                        Spacer()
                        Button("Skip") {
                            scheduler.skip(repository: repository, cloudSync: cloudSync)
                            onDismiss()
                        }
                        .buttonStyle(.plain)
                        .disabled(!controlsEnabled)
                    }
                }
                if !deferredOptions.isEmpty && canBypass {
                    Menu("Defer") {
                        ForEach(deferredOptions) { option in
                            Button(option.title) {
                                appDelegate?.deferCurrentBreak(option.condition)
                                onDismiss()
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                }
                if enforcementMode != .reminder && !showEmergencyExit {
                    Text(lockStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                if showEmergencyExit {
                    Button("Emergency Exit") {
                        scheduler.skip(repository: repository, cloudSync: cloudSync)
                        onDismiss()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red.opacity(0.7))
                    .font(.caption)
                    .padding(.top, 4)
                }
            }
            .padding(40)
        }
        .onReceive(tick) { _ in
            if remaining > 0 { remaining -= 1 }
            else {
                scheduler.markCompleted(repository: repository, cloudSync: cloudSync)
                NotificationCenter.default.post(name: .streakDidChange, object: nil)
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
        switch breakType {
        case .eye:
            VStack(spacing: 12) {
                Image(systemName: "eye").font(.system(size: 64))
                Text(ct?.name ?? "Eye Break").font(.title).bold()
                Text(primaryMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let secondaryTip {
                    Text(secondaryTip)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        case .micro, .long:
            VStack(spacing: 12) {
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .scaleEffect(breatheScale)
                Text(ct?.name ?? (breakType == .micro ? "Micro Break" : "Long Break")).font(.title).bold()
                Text(primaryMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let secondaryTip {
                    Text(secondaryTip)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private var lockStatusText: String {
        if !canBypass {
            return "Bypass disabled. Emergency exit available in \(max(0, 30 - Int(elapsed)))s."
        }
        switch enforcementMode {
        case .softLock:
            return "Skip and snooze unlock in \(max(0, minDisplaySeconds - Int(elapsed)))s."
        case .hardLock:
            return "Skip and snooze unlock after the emergency timeout."
        case .reminder:
            return ""
        }
    }
}

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b, a: UInt64
        switch h.count {
        case 6: (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8: (r, g, b, a) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (r, g, b, a) = (0, 0, 0, 255)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
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
