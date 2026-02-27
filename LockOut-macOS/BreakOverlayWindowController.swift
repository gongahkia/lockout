import AppKit
import SwiftUI
import AVFoundation
import LockOutCore

final class BreakOverlayWindowController {
    private var windows: [NSWindow] = []
    private let scheduler: BreakScheduler
    private let repo: BreakHistoryRepository
    private var audioPlayer: AVAudioPlayer?

    init(scheduler: BreakScheduler, repository: BreakHistoryRepository) {
        self.scheduler = scheduler
        self.repo = repository
    }

    func show(breakType: BreakType, duration: Int, minDisplaySeconds: Int = 5) {
        guard windows.isEmpty else { return }
        guard !SystemStateService.isScreenLocked() else {
            scheduler.markCompleted(repository: repo)
            return
        }
        guard !SystemStateService.frontmostAppIsFullscreen() else {
            scheduler.markCompleted(repository: repo)
            return
        }
        let frontmostID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if scheduler.currentSettings.blockedBundleIDs.contains(frontmostID) {
            scheduler.markCompleted(repository: repo)
            return
        }
        playBreakSound(customType?.soundName)
        let customType = scheduler.currentCustomBreakType
        for screen in NSScreen.screens {
            let win = LockOutOverlayWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            win.onEscape = { [weak self] in
                guard let self else { return }
                self.scheduler.skip(repository: self.repo)
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
                scheduler: scheduler,
                repository: repo
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
    }

    private func playBreakSound(_ soundName: String?) {
        // silence.aiff = no-op placeholder; nil/unset defaults to chime
        let name = soundName == "silence" ? nil : (soundName ?? "chime")
        guard let name else { return }
        let url = Bundle.main.url(forResource: name, withExtension: "aiff")
            ?? Bundle.main.url(forResource: "chime", withExtension: "aiff")
        guard let url else {
            NSSound(named: NSSound.Name("Glass"))?.play() // fallback
            return
        }
        // AVAudioPlayer respects system mute state automatically
        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.play()
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
