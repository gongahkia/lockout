import Foundation
import os

final class FileLogger {
    static let shared = FileLogger()

    private static let bootstrapLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.lockout",
        category: "FileLogger"
    )

    private let queue = DispatchQueue(label: "com.lockout.filelogger", qos: .utility)
    private let fileHandle: FileHandle?
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    let logURL: URL

    private init() {
        let logsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/LockOut", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        } catch {
            Self.bootstrapLogger.error("failed to create logs directory: \(String(describing: error), privacy: .public)")
        }

        let preferredURL = logsDir.appendingPathComponent("lockout-\(Self.dateStamp()).log")
        if !FileManager.default.fileExists(atPath: preferredURL.path) {
            if !FileManager.default.createFile(atPath: preferredURL.path, contents: Data()) {
                Self.bootstrapLogger.error("failed to create log file at preferred path: \(preferredURL.path, privacy: .public)")
            }
        }

        let resolvedURL: URL
        if FileManager.default.fileExists(atPath: preferredURL.path) {
            resolvedURL = preferredURL
        } else {
            let fallbackURL = FileManager.default.temporaryDirectory.appendingPathComponent("lockout-\(Self.dateStamp()).log")
            if !FileManager.default.fileExists(atPath: fallbackURL.path) {
                _ = FileManager.default.createFile(atPath: fallbackURL.path, contents: Data())
            }
            resolvedURL = fallbackURL
            Self.bootstrapLogger.error("using fallback log file path: \(fallbackURL.path, privacy: .public)")
        }
        logURL = resolvedURL

        do {
            let handle = try FileHandle(forWritingTo: logURL)
            handle.seekToEndOfFile()
            fileHandle = handle
        } catch {
            Self.bootstrapLogger.error("failed to open log file handle: \(String(describing: error), privacy: .public)")
            fileHandle = nil
        }

        pruneOldLogs(in: logsDir, keep: 7)
    }

    deinit {
        do {
            try fileHandle?.close()
        } catch {
            Self.bootstrapLogger.error("failed to close log file handle: \(String(describing: error), privacy: .public)")
        }
    }

    func log(_ level: Level, category: String, _ message: String, file: String = #fileID, line: Int = #line) {
        let ts = dateFormatter.string(from: Date())
        let entry = "[\(ts)] [\(level.rawValue)] [\(category)] \(message) (\(file):\(line))\n"
        queue.async { [weak self] in
            guard let data = entry.data(using: .utf8) else { return }
            guard let self else { return }
            guard let handle = self.fileHandle else {
                Self.bootstrapLogger.error("missing file handle for log entry: \(entry, privacy: .public)")
                return
            }
            do {
                try handle.write(contentsOf: data)
            } catch {
                Self.bootstrapLogger.error("failed writing log entry: \(String(describing: error), privacy: .public)")
            }
        }
    }

    enum Level: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

    private static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private func pruneOldLogs(in dir: URL, keep days: Int) {
        queue.async {
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let files: [URL]
            do {
                files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])
            } catch {
                Self.bootstrapLogger.error("failed listing log directory: \(String(describing: error), privacy: .public)")
                return
            }

            for file in files where file.pathExtension == "log" {
                do {
                    let attrs = try file.resourceValues(forKeys: [.creationDateKey])
                    guard let created = attrs.creationDate, created < cutoff else { continue }
                    try FileManager.default.removeItem(at: file)
                } catch {
                    Self.bootstrapLogger.error("failed pruning log file \(file.path, privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
        }
    }
}
