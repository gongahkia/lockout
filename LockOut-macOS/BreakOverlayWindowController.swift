import AppKit
import SwiftUI
import AVFoundation
import LockOutCore

enum OverlayPresentationResult {
    case shown
    case deferred(DeferredBreakCondition?)
}

@MainActor
final class BreakOverlayWindowController {
    private var windows: [NSWindow] = []
    private let scheduler: BreakScheduler
    private let repo: BreakHistoryRepository
    private let cloudSync: CloudKitSyncService
    private var audioPlayer: AVAudioPlayer?

    var isShowingOverlay: Bool { !windows.isEmpty }

    init(scheduler: BreakScheduler, repository: BreakHistoryRepository, cloudSync: CloudKitSyncService) {
        self.scheduler = scheduler
        self.repo = repository
        self.cloudSync = cloudSync
    }

    func show(breakType: BreakType, duration: Int, minDisplaySeconds: Int = 5, scheduledAt: Date) -> OverlayPresentationResult {
        guard windows.isEmpty else {
            FileLogger.shared.log(.debug, category: "Overlay", "show skipped: overlay already visible")
            return .deferred(nil)
        }
        guard !SystemStateService.isScreenLocked() else {
            FileLogger.shared.log(.info, category: "Overlay", "deferred: screen locked")
            return .deferred(nil)
        }
        guard !SystemStateService.frontmostAppIsFullscreen() else {
            FileLogger.shared.log(.info, category: "Overlay", "deferred: fullscreen app active")
            return .deferred(.untilFullscreenEnds)
        }
        let frontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if scheduler.currentSettings.blockedBundleIDs.contains(frontmostID) {
            FileLogger.shared.log(.info, category: "Overlay", "deferred: blocked app \(frontmostID)")
            return .deferred(.untilAppChanges(bundleID: frontmostID))
        }
        FileLogger.shared.log(.info, category: "Overlay", "showing break=\(breakType.rawValue) duration=\(duration)s screens=\(NSScreen.screens.count)")
        let customType = scheduler.currentCustomBreakType
        playBreakSound(customType?.soundName)
        for screen in NSScreen.screens {
            let win = LockOutOverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            win.enforcementMode = scheduler.currentSettings.breakEnforcementMode // #14
            win.showTime = Date() // #14
            win.onEscape = { [weak self] in
                guard let self else { return }
                self.scheduler.skip(repository: self.repo, cloudSync: self.cloudSync)
                self.dismiss()
            }
            win.level = .screenSaver
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.isOpaque = false
            win.backgroundColor = .clear
            let view = BreakOverlayView(
                breakType: breakType,
                duration: duration,
                minDisplaySeconds: minDisplaySeconds,
                scheduledAt: scheduledAt,
                scheduler: scheduler,
                repository: repo,
                cloudSync: cloudSync
            ) { [weak self] in self?.dismiss() }
            let hosting = NSHostingView(rootView: view)
            let effectView = NSVisualEffectView(frame: screen.frame)
            effectView.material = Self.materialForString(customType?.overlayBlurMaterial ?? "hudWindow")
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            hosting.autoresizingMask = [.width, .height]
            hosting.frame = effectView.bounds
            effectView.addSubview(hosting)
            win.contentView = effectView
            win.alphaValue = 0
            win.orderFront(nil)
            win.makeKey()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                win.animator().alphaValue = 1
            }
            windows.append(win)
        }
        return .shown
    }

    private func playBreakSound(_ soundName: String?) {
        // silence.aiff = no-op placeholder; nil/unset defaults to chime
        let name = soundName == "silence" ? nil : (soundName ?? "chime")
        guard let name else { return }
        let url = Bundle.main.url(forResource: name, withExtension: "aiff")
            ?? Bundle.main.url(forResource: "chime", withExtension: "aiff")
        guard let url else {
            FileLogger.shared.log(.warn, category: "Overlay", "sound file missing for \(name), using system fallback")
            DiagnosticsStore.shared.record(level: .warning, category: "Overlay", message: "sound file missing for \(name)")
            NSSound(named: NSSound.Name("Glass"))?.play() // fallback
            return
        }
        // AVAudioPlayer respects system mute state automatically
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            audioPlayer = player
            player.play()
        } catch {
            FileLogger.shared.log(.warn, category: "Overlay", "failed to play sound \(name): \(error)")
            DiagnosticsStore.shared.record(
                level: .warning,
                category: "Overlay",
                message: "failed to play sound \(name): \(error.localizedDescription)"
            )
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }

    private static func materialForString(_ s: String) -> NSVisualEffectView.Material {
        switch s {
        case "ultraThin": return .underWindowBackground
        case "thin": return .underPageBackground
        case "medium": return .contentBackground
        default: return .hudWindow
        }
    }

    func dismiss() {
        FileLogger.shared.log(.info, category: "Overlay", "dismissed")
        let current = windows
        windows.removeAll()
        for win in current {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.3
                win.animator().alphaValue = 0
            }, completionHandler: {
                win.orderOut(nil)
            })
        }
    }
}
