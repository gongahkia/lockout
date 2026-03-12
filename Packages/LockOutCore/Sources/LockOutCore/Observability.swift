import Foundation

public enum Observability {
    public enum Level: String { case debug, info, warn, error }
    public typealias Sink = (_ category: String, _ message: String) -> Void
    public typealias LevelSink = (_ level: Level, _ category: String, _ message: String) -> Void
    private final class Storage: @unchecked Sendable {
        let lock = NSLock()
        var sink: Sink?
        var levelSink: LevelSink?
    }

    private static let storage = Storage()

    public static var sink: Sink? {
        get {
            storage.lock.lock()
            defer { storage.lock.unlock() }
            return storage.sink
        }
        set {
            storage.lock.lock()
            storage.sink = newValue
            storage.lock.unlock()
        }
    }

    public static var levelSink: LevelSink? {
        get {
            storage.lock.lock()
            defer { storage.lock.unlock() }
            return storage.levelSink
        }
        set {
            storage.lock.lock()
            storage.levelSink = newValue
            storage.lock.unlock()
        }
    }

    public static func emit(category: String, message: String, level: Level = .info) {
        let currentSink: Sink?
        let currentLevelSink: LevelSink?
        storage.lock.lock()
        currentSink = storage.sink
        currentLevelSink = storage.levelSink
        storage.lock.unlock()
        currentSink?(category, message)
        currentLevelSink?(level, category, message)
    }
}
