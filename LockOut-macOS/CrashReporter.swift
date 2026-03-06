import Foundation

// #29: basic crash/exception logging to file
// no remote telemetry — writes to the existing FileLogger
enum CrashReporter {
    private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        NSSetUncaughtExceptionHandler { exception in
            let log = FileLogger.shared
            log.log(.error, category: "CRASH", "Uncaught exception: \(exception.name.rawValue)")
            log.log(.error, category: "CRASH", "Reason: \(exception.reason ?? "nil")")
            log.log(.error, category: "CRASH", "Stack: \(exception.callStackSymbols.joined(separator: "\n"))")
        }
        // POSIX signal handlers for common crash signals
        for sig: Int32 in [SIGABRT, SIGSEGV, SIGBUS, SIGFPE, SIGILL, SIGTRAP] {
            signal(sig) { signum in
                let log = FileLogger.shared
                log.log(.error, category: "CRASH", "Fatal signal \(signum) received")
                signal(signum, SIG_DFL)
                raise(signum)
            }
        }
        FileLogger.shared.log(.info, category: "CrashReporter", "installed")
    }
}
