import Foundation
import AppKit
import CoreGraphics

public enum SystemStateService {
    public static func isScreenLocked() -> Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    public static func frontmostAppIsFullscreen() -> Bool {
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
