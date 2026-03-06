import AppKit
import LockOutCore

final class LockOutOverlayWindow: NSWindow {
    var onEscape: (() -> Void)?
    var enforcementMode: BreakEnforcementMode = .reminder // #14
    var showTime: Date = Date() // #14: track when overlay appeared
    private static let emergencyEscapeSeconds: TimeInterval = 30 // #14: always allow escape after 30s

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard event.keyCode == 53 else { super.keyDown(with: event); return }
        // #14: always allow escape after emergency timeout, regardless of enforcement
        let elapsed = Date().timeIntervalSince(showTime)
        switch enforcementMode {
        case .reminder:
            onEscape?()
        case .soft_lock:
            if elapsed >= Self.emergencyEscapeSeconds { onEscape?() } // allow after timeout
        case .hard_lock:
            if elapsed >= Self.emergencyEscapeSeconds { onEscape?() } // emergency escape
        }
    }
}
