import Foundation

public enum AgentDeveloperPreset: String, CaseIterable, Codable, Sendable {
    case sprintCoding
    case evalRuns
    case incidentResponse

    public var profileName: String {
        switch self {
        case .sprintCoding:
            return "Agent Sprint Coding"
        case .evalRuns:
            return "Agent Eval Runs"
        case .incidentResponse:
            return "Agent Incident Response"
        }
    }

    public var summary: String {
        switch self {
        case .sprintCoding:
            return "Fast feedback loops with tighter break cadence for long coding sessions."
        case .evalRuns:
            return "Long-running evaluation sessions with calendar and focus-aware pauses."
        case .incidentResponse:
            return "Lower-friction cadence for on-call and incident mitigation windows."
        }
    }

    fileprivate func makeProfile() -> AppProfile {
        switch self {
        case .sprintCoding:
            return AppProfile(
                name: profileName,
                customBreakTypes: [
                    CustomBreakType(name: "Eye Break", intervalMinutes: 20, durationSeconds: 25, minDisplaySeconds: 8, tips: ["Look away from terminals and notebooks"], snoozeMinutes: 3),
                    CustomBreakType(name: "Micro Break", intervalMinutes: 40, durationSeconds: 45, minDisplaySeconds: 10, tips: ["Drop shoulders and relax hands"], snoozeMinutes: 3),
                    CustomBreakType(name: "Reset Break", intervalMinutes: 90, durationSeconds: 420, minDisplaySeconds: 20, tips: ["Walk and hydrate before the next agent run"], snoozeMinutes: 5),
                ],
                blockedBundleIDs: [],
                idleThresholdMinutes: 5,
                pauseDuringFocus: false,
                pauseDuringCalendarEvents: false,
                calendarFilterMode: .busyOnly,
                filteredCalendarIDs: [],
                workdayStartMinutes: 9 * 60,
                workdayEndMinutes: 19 * 60,
                notificationLeadMinutes: 1,
                breakEnforcementMode: .soft_lock,
                snoozeDurationMinutes: 3
            )
        case .evalRuns:
            return AppProfile(
                name: profileName,
                customBreakTypes: [
                    CustomBreakType(name: "Eye Break", intervalMinutes: 25, durationSeconds: 20, minDisplaySeconds: 8, tips: ["Reset visual focus between eval batches"], snoozeMinutes: 5),
                    CustomBreakType(name: "Micro Break", intervalMinutes: 55, durationSeconds: 45, minDisplaySeconds: 10, tips: ["Stand and stretch while dashboards refresh"], snoozeMinutes: 5),
                    CustomBreakType(name: "Long Break", intervalMinutes: 120, durationSeconds: 600, minDisplaySeconds: 20, tips: ["Step away to avoid monitoring fatigue"], snoozeMinutes: 10),
                ],
                blockedBundleIDs: [],
                idleThresholdMinutes: 6,
                pauseDuringFocus: true,
                pauseDuringCalendarEvents: true,
                calendarFilterMode: .busyOnly,
                filteredCalendarIDs: [],
                workdayStartMinutes: 8 * 60,
                workdayEndMinutes: 19 * 60,
                notificationLeadMinutes: 2,
                breakEnforcementMode: .reminder,
                snoozeDurationMinutes: 5
            )
        case .incidentResponse:
            return AppProfile(
                name: profileName,
                customBreakTypes: [
                    CustomBreakType(name: "Eye Break", intervalMinutes: 30, durationSeconds: 20, minDisplaySeconds: 5, tips: ["Pause and re-scan assumptions"], snoozeMinutes: 10),
                    CustomBreakType(name: "Micro Break", intervalMinutes: 60, durationSeconds: 30, minDisplaySeconds: 8, tips: ["Do one deep breath before the next response"], snoozeMinutes: 10),
                    CustomBreakType(name: "Long Break", intervalMinutes: 150, durationSeconds: 480, minDisplaySeconds: 15, tips: ["Take a short reset to preserve decision quality"], snoozeMinutes: 15),
                ],
                blockedBundleIDs: [],
                idleThresholdMinutes: 8,
                pauseDuringFocus: false,
                pauseDuringCalendarEvents: true,
                calendarFilterMode: .busyOnly,
                filteredCalendarIDs: [],
                workdayStartMinutes: nil,
                workdayEndMinutes: nil,
                notificationLeadMinutes: 0,
                breakEnforcementMode: .reminder,
                snoozeDurationMinutes: 10
            )
        }
    }

    fileprivate func makeStarterRule(profileID: UUID, priority: Int) -> AutoProfileRule {
        let triggers: [ProfileTrigger]
        switch self {
        case .sprintCoding:
            triggers = [
                .frontmostApp(bundleIDs: [
                    "com.apple.Terminal",
                    "com.googlecode.iterm2",
                    "com.microsoft.VSCode",
                    "com.jetbrains.intellij",
                    "com.jetbrains.PyCharm",
                    "com.apple.dt.Xcode",
                ]),
            ]
        case .evalRuns:
            triggers = [
                .focusMode,
                .externalDisplayConnected,
            ]
        case .incidentResponse:
            triggers = [
                .calendarMatch,
            ]
        }
        return AutoProfileRule(
            enabled: false,
            priority: priority,
            profileID: profileID,
            triggers: triggers
        )
    }
}

public struct AgentDeveloperBootstrapResult: Equatable, Sendable {
    public var addedProfiles: [String]
    public var addedRules: Int
    public var skippedProfiles: [String]

    public init(addedProfiles: [String] = [], addedRules: Int = 0, skippedProfiles: [String] = []) {
        self.addedProfiles = addedProfiles
        self.addedRules = addedRules
        self.skippedProfiles = skippedProfiles
    }

    public var isNoOp: Bool {
        addedProfiles.isEmpty && addedRules == 0
    }
}

public enum AgentDeveloperPresets {
    public static func bootstrap(into settings: inout AppSettings) -> AgentDeveloperBootstrapResult {
        let existingProfileNames = Set(settings.profiles.map { $0.name.lowercased() })
        var result = AgentDeveloperBootstrapResult()
        var nextPriority = (settings.autoProfileRules.map(\.priority).max() ?? 0) + AgentDeveloperPreset.allCases.count

        for preset in AgentDeveloperPreset.allCases {
            if existingProfileNames.contains(preset.profileName.lowercased()) {
                result.skippedProfiles.append(preset.profileName)
                continue
            }

            let profile = preset.makeProfile()
            settings.profiles.append(profile)
            result.addedProfiles.append(profile.name)

            let rule = preset.makeStarterRule(profileID: profile.id, priority: nextPriority)
            settings.autoProfileRules.append(rule)
            nextPriority -= 1
            result.addedRules += 1
        }

        settings.autoProfileRules.sort { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.priority > rhs.priority
        }

        return result
    }
}
