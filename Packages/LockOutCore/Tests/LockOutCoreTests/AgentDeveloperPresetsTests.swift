import XCTest
@testable import LockOutCore

final class AgentDeveloperPresetsTests: XCTestCase {
    func testBootstrapAddsProfilesAndDisabledStarterRules() {
        var settings = AppSettings.defaults

        let result = AgentDeveloperPresets.bootstrap(into: &settings)

        XCTAssertEqual(result.addedProfiles.count, AgentDeveloperPreset.allCases.count)
        XCTAssertEqual(result.addedRules, AgentDeveloperPreset.allCases.count)
        XCTAssertEqual(settings.profiles.count, AgentDeveloperPreset.allCases.count)
        XCTAssertEqual(settings.autoProfileRules.count, AgentDeveloperPreset.allCases.count)
        XCTAssertTrue(settings.autoProfileRules.allSatisfy { !$0.enabled })
    }

    func testBootstrapIsIdempotentWhenRunTwice() {
        var settings = AppSettings.defaults

        _ = AgentDeveloperPresets.bootstrap(into: &settings)
        let second = AgentDeveloperPresets.bootstrap(into: &settings)

        XCTAssertTrue(second.isNoOp)
        XCTAssertEqual(second.skippedProfiles.count, AgentDeveloperPreset.allCases.count)
        XCTAssertEqual(settings.profiles.count, AgentDeveloperPreset.allCases.count)
        XCTAssertEqual(settings.autoProfileRules.count, AgentDeveloperPreset.allCases.count)
    }

    func testBootstrapRulesRemainPrioritySortedDescending() {
        var settings = AppSettings.defaults
        settings.autoProfileRules = [
            AutoProfileRule(enabled: true, priority: 2, profileID: UUID(), triggers: [.focusMode]),
            AutoProfileRule(enabled: true, priority: 9, profileID: UUID(), triggers: [.calendarMatch]),
        ]

        _ = AgentDeveloperPresets.bootstrap(into: &settings)

        let sorted = settings.autoProfileRules.map(\.priority)
        XCTAssertEqual(sorted, sorted.sorted(by: >))
    }

    func testOnboardingAgentPresetEquivalentActivatesSeededProfile() {
        var settings = AppSettings.defaults
        settings.activeRole = .developer

        let result = AgentDeveloperPresets.bootstrap(into: &settings)
        XCTAssertFalse(result.addedProfiles.isEmpty)

        guard let firstProfileName = result.addedProfiles.first,
              let profile = settings.profiles.first(where: { $0.name == firstProfileName }) else {
            return XCTFail("Expected onboarding-equivalent bootstrap profile to exist")
        }

        settings.apply(profile: profile)
        settings.activeProfileId = profile.id

        XCTAssertEqual(settings.activeRole, .developer)
        XCTAssertEqual(settings.activeProfileId, profile.id)
        XCTAssertEqual(
            settings.profiles.first(where: { $0.id == settings.activeProfileId })?.name,
            firstProfileName
        )
    }
}
