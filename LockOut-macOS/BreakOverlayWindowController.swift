import AppKit
import SwiftUI
import LockOutCore

final class BreakOverlayWindowController {
    private var windows: [NSWindow] = []
    private var scheduler: BreakScheduler { AppDelegate.shared.scheduler }
    private var repo: BreakHistoryRepository { AppDelegate.shared.repository }

    func show(breakType: BreakType, duration: Int) {
        guard !isScreenLocked() else {
            scheduler.markCompleted(repository: repo)
            return
        }
        guard !frontmostAppIsFullscreen() else {
            scheduler.markCompleted(repository: repo)
            return
        }
        NSSound(named: NSSound.Name("Glass"))?.play()
        dismiss()
        for screen in NSScreen.screens {
            let win = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            win.level = .screenSaver
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.isOpaque = false
            win.backgroundColor = .clear
            let view = BreakOverlayView(breakType: breakType, duration: duration) { [weak self] in
                self?.dismiss()
            }
            win.contentView = NSHostingView(rootView: view)
            win.alphaValue = 0
            win.orderFront(nil)
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

    private func isScreenLocked() -> Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    private func frontmostAppIsFullscreen() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let pid = app.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.contains { info in
            (info[kCGWindowOwnerPID as String] as? Int32) == pid &&
            (info[kCGWindowLayer as String] as? Int32) == 0 &&
            (info[kCGWindowIsOnscreen as String] as? Bool) == true
        }
    }
}
