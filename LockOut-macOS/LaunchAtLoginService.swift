import ServiceManagement
import os

private let logger = Logger(subsystem: "com.yourapp.lockout", category: "LaunchAtLoginService")

enum LaunchAtLoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func enable() {
        do {
            try SMAppService.mainApp.register()
        } catch {
            logger.error("register failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func disable() {
        do {
            try SMAppService.mainApp.unregister()
        } catch {
            logger.error("unregister failed: \(String(describing: error), privacy: .public)")
        }
    }
}
