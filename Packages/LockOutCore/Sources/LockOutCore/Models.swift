import Foundation
import SwiftData

// MARK: - Enums
public enum BreakType: String, Codable, CaseIterable, Sendable {
    case eye    // 20-20-20 rule
    case micro
    case long
}

public enum BreakStatus: String, Codable, Sendable {
    case completed, skipped, snoozed
}

// MARK: - Value types
public struct BreakSession: Codable, Sendable {
    public let id: UUID
    public let type: BreakType
    public let scheduledAt: Date
    public var endedAt: Date?
    public var status: BreakStatus

    public init(id: UUID = UUID(), type: BreakType, scheduledAt: Date, endedAt: Date? = nil, status: BreakStatus) {
        self.id = id
        self.type = type
        self.scheduledAt = scheduledAt
        self.endedAt = endedAt
        self.status = status
    }
}

// MARK: - SwiftData persistence
@Model
public final class BreakSessionRecord {
    @Attribute(.unique) public var id: UUID
    public var type: String         // raw BreakType
    public var scheduledAt: Date
    public var endedAt: Date?
    public var status: String       // raw BreakStatus

    public init(from session: BreakSession) {
        self.id = session.id
        self.type = session.type.rawValue
        self.scheduledAt = session.scheduledAt
        self.endedAt = session.endedAt
        self.status = session.status.rawValue
    }

    public func toBreakSession() -> BreakSession? {
        guard let t = BreakType(rawValue: type),
              let s = BreakStatus(rawValue: status) else { return nil }
        return BreakSession(id: id, type: t, scheduledAt: scheduledAt, endedAt: endedAt, status: s)
    }
}
