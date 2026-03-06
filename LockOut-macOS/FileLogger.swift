import Foundation
import os

final class FileLogger {
    static let shared = FileLogger()
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
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let fileName = "lockout-\(Self.dateStamp()).log"
        logURL = logsDir.appendingPathComponent(fileName)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: logURL)
        fileHandle?.seekToEndOfFile()
        pruneOldLogs(in: logsDir, keep: 7)
    }

    deinit { fileHandle?.closeFile() }

    func log(_ level: Level, category: String, _ message: String, file: String = #fileID, line: Int = #line) {
        let ts = dateFormatter.string(from: Date())
        let entry = "[\(ts)] [\(level.rawValue)] [\(category)] \(message) (\(file):\(line))\n"
        queue.async { [weak self] in
            guard let data = entry.data(using: .utf8) else { return }
            self?.fileHandle?.write(data)
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
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else { return }
            for file in files where file.pathExtension == "log" {
                guard let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
                      let created = attrs.creationDate, created < cutoff else { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
