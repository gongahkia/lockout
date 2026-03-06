import Foundation

public enum Observability {
    public enum Level: String { case debug, info, warn, error }
    public typealias Sink = (_ category: String, _ message: String) -> Void
    public typealias LevelSink = (_ level: Level, _ category: String, _ message: String) -> Void
    public static var sink: Sink?
    public static var levelSink: LevelSink?

    public static func emit(category: String, message: String, level: Level = .info) {
        sink?(category, message)
        levelSink?(level, category, message)
    }
}
