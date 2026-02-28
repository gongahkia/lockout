import Foundation
import SwiftData

// MARK: - Custom break type
public struct CustomBreakType: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var intervalMinutes: Int
    public var durationSeconds: Int
    public var minDisplaySeconds: Int
    public var enabled: Bool
    public var soundName: String?
    public var message: String?
    public var tips: [String]
    public var overlayOpacity: Double
    public var overlayColorHex: String
    public var snoozeMinutes: Int
    public var overlayBlurMaterial: String  // ultraThin | thin | medium | hudWindow

    public init(id: UUID = UUID(), name: String, intervalMinutes: Int, durationSeconds: Int,
                minDisplaySeconds: Int = 5, enabled: Bool = true, soundName: String? = nil,
                message: String? = nil, tips: [String] = [], overlayOpacity: Double = 0.85,
                overlayColorHex: String = "#000000", snoozeMinutes: Int = 5,
                overlayBlurMaterial: String = "hudWindow") {
        self.id = id; self.name = name; self.intervalMinutes = intervalMinutes
        self.durationSeconds = durationSeconds; self.minDisplaySeconds = minDisplaySeconds
        self.enabled = enabled; self.soundName = soundName; self.message = message
        self.tips = tips; self.overlayOpacity = overlayOpacity
        self.overlayColorHex = overlayColorHex; self.snoozeMinutes = snoozeMinutes
        self.overlayBlurMaterial = overlayBlurMaterial
    }
}

// MARK: - Enums
public enum BreakType: String, Codable, CaseIterable, Sendable {
    case eye    // 20-20-20 rule
    case micro
    case long
}

public enum BreakStatus: String, Codable, Sendable {
    case completed, skipped, snoozed, deferred
}

// MARK: - Value types
public struct BreakSession: Codable, Sendable {
    public let id: UUID
    public let type: BreakType
    public let scheduledAt: Date
    public var endedAt: Date?
    public var status: BreakStatus
    public var breakTypeName: String?

    public init(id: UUID = UUID(), type: BreakType, scheduledAt: Date, endedAt: Date? = nil, status: BreakStatus, breakTypeName: String? = nil) {
        self.id = id
        self.type = type
        self.scheduledAt = scheduledAt
        self.endedAt = endedAt
        self.status = status
        self.breakTypeName = breakTypeName
    }
}

// MARK: - SwiftData persistence
@Model
public final class BreakSessionRecord {
    @Attribute(.unique) public var id: UUID
    public var type: String         // raw BreakType (legacy compat)
    public var breakTypeName: String // custom break type name
    public var scheduledAt: Date
    public var endedAt: Date?
    public var status: String       // raw BreakStatus

    public init(from session: BreakSession) {
        self.id = session.id
        self.type = session.type.rawValue
        self.breakTypeName = session.breakTypeName ?? session.type.rawValue
        self.scheduledAt = session.scheduledAt
        self.endedAt = session.endedAt
        self.status = session.status.rawValue
    }

    public func toBreakSession() -> BreakSession? {
        guard let t = BreakType(rawValue: type),
              let s = BreakStatus(rawValue: status) else { return nil }
        return BreakSession(id: id, type: t, scheduledAt: scheduledAt, endedAt: endedAt, status: s, breakTypeName: breakTypeName)
    }
}
