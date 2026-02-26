import AppKit
import SwiftUI
import LockOutCore

final class BreakOverlayWindowController {
    private var windows: [NSWindow] = []
    private let scheduler: BreakScheduler
    private let repo: BreakHistoryRepository

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
        NSSound(named: NSSound.Name("Glass"))?.play()
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
            win.contentView = NSHostingView(rootView: view)
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
