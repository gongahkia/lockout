import Foundation

public enum DiagnosticsLevel: String, Codable, CaseIterable, Sendable {
    case debug
    case info
    case warning
    case error

    public init(from level: Observability.Level) {
        switch level {
        case .debug:
            self = .debug
        case .info:
            self = .info
        case .warn:
            self = .warning
        case .error:
            self = .error
        }
    }
}

public struct DiagnosticsEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var level: DiagnosticsLevel
    public var category: String
    public var message: String
    public var metadata: [String: String]

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: DiagnosticsLevel,
        category: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
    }
}

public final class DiagnosticsStore: @unchecked Sendable {
    public static let shared = DiagnosticsStore()

    private static let eventsKey = "lockout_diagnostics_events"
    private static let maxEvents = 500

    private let lock = NSLock()
    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func record(
        level: DiagnosticsLevel,
        category: String,
        message: String,
        metadata: [String: String] = [:],
        now: Date = Date()
    ) {
        lock.lock()
        defer { lock.unlock() }

        var events = loadEventsLocked()
        events.append(
            DiagnosticsEvent(
                timestamp: now,
                level: level,
                category: category,
                message: message,
                metadata: metadata
            )
        )
        if events.count > Self.maxEvents {
            events.removeFirst(events.count - Self.maxEvents)
        }
        persistEventsLocked(events)
    }

    public func recentEvents(limit: Int = 200) -> [DiagnosticsEvent] {
        lock.lock()
        defer { lock.unlock() }
        let events = loadEventsLocked()
        let clampedLimit = max(0, limit)
        if clampedLimit == 0 { return [] }
        return Array(events.suffix(clampedLimit))
    }

    public func countsByLevel(limit: Int = 200) -> [DiagnosticsLevel: Int] {
        let events = recentEvents(limit: limit)
        return events.reduce(into: [DiagnosticsLevel: Int]()) { map, event in
            map[event.level, default: 0] += 1
        }
    }

    public func clear() {
        lock.lock()
        defaults.removeObject(forKey: Self.eventsKey)
        lock.unlock()
    }

    private func loadEventsLocked() -> [DiagnosticsEvent] {
        guard let data = defaults.data(forKey: Self.eventsKey) else { return [] }
        do {
            return try decoder.decode([DiagnosticsEvent].self, from: data)
        } catch {
            defaults.removeObject(forKey: Self.eventsKey)
            NSLog("LockOut Diagnostics decode failed: \(String(describing: error))")
            return []
        }
    }

    private func persistEventsLocked(_ events: [DiagnosticsEvent]) {
        do {
            defaults.set(try encoder.encode(events), forKey: Self.eventsKey)
        } catch {
            NSLog("LockOut Diagnostics encode failed: \(String(describing: error))")
        }
    }
}
