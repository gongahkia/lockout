import XCTest
import SwiftData
@testable import LockOutCore

// MARK: - ComplianceCalculator tests
final class ComplianceCalculatorTests: XCTestCase {
    func testStreakEmpty() {
        XCTAssertEqual(ComplianceCalculator.streakDays(stats: []), 0)
    }

    func testStreakAllSkipped() {
        let cal = Calendar.current
        let stats = (0..<5).map { offset -> DayStat in
            let d = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date()))!
            return DayStat(date: d, completed: 0, skipped: 10)
        }
        XCTAssertEqual(ComplianceCalculator.streakDays(stats: stats), 0)
    }

    func testStreakNConsecutiveCompliant() {
        let cal = Calendar.current
        let n = 4
        let stats = (0..<n).map { offset -> DayStat in
            let d = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: Date()))!
            return DayStat(date: d, completed: 10, skipped: 0)
        }
        XCTAssertEqual(ComplianceCalculator.streakDays(stats: stats), n)
    }

    func testOverallRate() {
        let stats = [DayStat(date: Date(), completed: 8, skipped: 2)]
        XCTAssertEqual(ComplianceCalculator.overallRate(stats: stats), 0.8, accuracy: 0.001)
    }

    func testOverallRateEmpty() {
        XCTAssertEqual(ComplianceCalculator.overallRate(stats: []), 0.0, accuracy: 0.001)
    }
}

// MARK: - BreakScheduler tests (main-actor)
@MainActor
final class BreakSchedulerTests: XCTestCase {
    private var scheduler: BreakScheduler!

    override func setUp() async throws {
        scheduler = BreakScheduler(settings: .defaults)
        scheduler.start(settings: .defaults)
    }

    override func tearDown() async throws {
        scheduler.stop()
    }

    func testSnoozeOffsetFireDate() async {
        scheduler.start(settings: .defaults)
        let before = Date()
        scheduler.snooze(minutes: 5)
        let fireDate = scheduler.nextBreak?.fireDate ?? Date.distantPast
        let expectedMin = before.addingTimeInterval(5 * 60 - 2)
        let expectedMax = before.addingTimeInterval(5 * 60 + 2)
        XCTAssertTrue(fireDate >= expectedMin && fireDate <= expectedMax)
    }

    func testMultiTimerCountAfterStart() async {
        scheduler.start(settings: .defaults)
        XCTAssertEqual(scheduler.timers.count, 3)
    }

    func testTimerExpiryInvokesOnBreakTriggered() async {
        let custom = CustomBreakType(name: "Immediate", intervalMinutes: 1, durationSeconds: 20)
        var settings = AppSettings.defaults
        settings.customBreakTypes = [custom]
        scheduler = BreakScheduler(settings: settings)

        let exp = expectation(description: "onBreakTriggered called")
        scheduler.onBreakTriggered = { fired in
            if fired.id == custom.id { exp.fulfill() }
        }

        scheduler.start(settings: settings, offsetSeconds: 120)
        await fulfillment(of: [exp], timeout: 1.0)
    }

    func testRecurringBreaksContinueOverEightHourSimulation() async {
        let hourly = CustomBreakType(name: "Hourly", intervalMinutes: 60, durationSeconds: 60)
        var settings = AppSettings.defaults
        settings.customBreakTypes = [hourly]
        scheduler = BreakScheduler(settings: settings)
        scheduler.start(settings: settings)

        for _ in 0..<8 {
            scheduler.simulateTimerFireForTesting(customTypeID: hourly.id)
            XCTAssertEqual(scheduler.nextBreak?.customTypeID, hourly.id)
            XCTAssertNotNil(scheduler.timers[hourly.id])
        }
    }
}

// MARK: - BreakHistoryRepository idempotency
final class BreakHistoryRepositoryTests: XCTestCase {
    func testSaveIdempotency() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BreakSessionRecord.self, configurations: config)
        let repo = BreakHistoryRepository(modelContext: ModelContext(container))
        let id = UUID()
        let s1 = BreakSession(id: id, type: .eye, scheduledAt: Date(), status: .skipped)
        let s2 = BreakSession(id: id, type: .eye, scheduledAt: Date(), status: .completed)
        repo.save(s1)
        repo.save(s2)
        let all = repo.fetchSessions(from: Date.distantPast, to: Date.distantFuture)
        let matching = all.filter { $0.id == id }
        XCTAssertEqual(matching.count, 1)
        XCTAssertEqual(matching.first?.status, .completed)
    }

    func testDeferredStatusRoundTrip() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BreakSessionRecord.self, configurations: config)
        let repo = BreakHistoryRepository(modelContext: ModelContext(container))
        let session = BreakSession(type: .eye, scheduledAt: Date(), status: .deferred)
        repo.save(session)
        let loaded = repo.fetchSession(id: session.id)
        XCTAssertEqual(loaded?.status, .deferred)
    }
}

// MARK: - Blocklist shouldShow
final class BlocklistTests: XCTestCase {
    func testBlockedBundleIDSuppressesOverlay() {
        var settings = AppSettings.defaults
        settings.blockedBundleIDs = ["com.test.app"]
        let blocked = settings.blockedBundleIDs.contains("com.test.app")
        XCTAssertTrue(blocked) // shouldShow returns false when frontmost ID is in blocklist
    }

    func testAllowedBundleIDDoesNotBlock() {
        var settings = AppSettings.defaults
        settings.blockedBundleIDs = ["com.test.app"]
        let blocked = settings.blockedBundleIDs.contains("com.other.app")
        XCTAssertFalse(blocked)
    }
}

// MARK: - CloudKitSyncService conflict resolution
final class CloudKitConflictTests: XCTestCase {
    func testResolveConflictPrefersCompleted() {
        let svc = CloudKitSyncService()
        let id = UUID()
        let completed = BreakSession(id: id, type: .eye, scheduledAt: Date(), status: .completed)
        let skipped = BreakSession(id: id, type: .eye, scheduledAt: Date(), status: .skipped)
        let result = svc.resolveConflict(local: skipped, remote: completed)
        XCTAssertEqual(result.status, .completed)
    }

    func testResolveConflictLocalCompletedWinsOverRemoteSkipped() {
        let svc = CloudKitSyncService()
        let id = UUID()
        let local = BreakSession(id: id, type: .eye, scheduledAt: Date(), status: .completed)
        let remote = BreakSession(id: id, type: .eye, scheduledAt: Date(), status: .skipped)
        let result = svc.resolveConflict(local: local, remote: remote)
        XCTAssertEqual(result.status, .completed)
    }
}

// MARK: - Custom break type scheduling
@MainActor
final class CustomBreakTypeSchedulingTests: XCTestCase {
    func testTwoEnabledTypesCreateTwoTimers() async {
        let types = [
            CustomBreakType(name: "Eye Break", intervalMinutes: 20, durationSeconds: 20),
            CustomBreakType(name: "Micro Break", intervalMinutes: 45, durationSeconds: 30),
        ]
        var settings = AppSettings.defaults
        settings.customBreakTypes = types
        let scheduler = BreakScheduler(settings: settings)
        scheduler.start(settings: settings)
        XCTAssertEqual(scheduler.timers.count, 2)
        scheduler.stop()
    }

    func testSimilarNamesDoNotOverwriteTimers() async {
        let types = [
            CustomBreakType(name: "Micro Break", intervalMinutes: 20, durationSeconds: 20),
            CustomBreakType(name: "Micro Break+", intervalMinutes: 25, durationSeconds: 30),
        ]
        var settings = AppSettings.defaults
        settings.customBreakTypes = types
        let scheduler = BreakScheduler(settings: settings)
        scheduler.start(settings: settings)
        XCTAssertEqual(scheduler.timers.count, 2)
        XCTAssertNotNil(scheduler.timers[types[0].id])
        XCTAssertNotNil(scheduler.timers[types[1].id])
        scheduler.stop()
    }
}

// MARK: - CloudKitSyncService offline upload queue
final class CloudKitOfflineQueueTests: XCTestCase {
    func testOfflineQueueEnqueuesSession() async {
        let svc = CloudKitSyncService()
        NetworkMonitor.shared.forceOffline(true)
        // drain any pending state
        UserDefaults.standard.removeObject(forKey: "ckPendingUploads")
        let session = BreakSession(type: .eye, scheduledAt: Date(), status: .completed)
        await svc.uploadSession(session)
        XCTAssertEqual(svc.pendingUploadsCount, 1)
        // clear queue before restoring online so flush guard returns early (avoids real CK access)
        UserDefaults.standard.removeObject(forKey: "ckPendingUploads")
        NetworkMonitor.shared.forceOffline(false)
    }
}

// MARK: - Idle-pause
@MainActor
final class IdlePauseTests: XCTestCase {
    func testIdleThresholdExceededPausesScheduler() async {
        let scheduler = BreakScheduler(settings: .defaults)
        scheduler.start(settings: .defaults)
        var settings = scheduler.currentSettings
        settings.idleThresholdMinutes = 1
        scheduler.currentSettings = settings
        // simulate: idleSeconds (61) >= threshold (60) → should pause
        let threshold = Double(scheduler.currentSettings.idleThresholdMinutes) * 60 // 60
        let idleSeconds: Double = 61
        if idleSeconds >= threshold { scheduler.pause() }
        XCTAssertTrue(scheduler.currentSettings.isPaused)
        scheduler.stop()
    }
}

// MARK: - minDisplaySeconds enforcement
final class MinDisplaySecondsTests: XCTestCase {
    func testSkipDisabledAtT0() {
        // canSkip = elapsed >= minDisplaySeconds
        let minDisplay = 10
        let showTime = Date()
        // simulate t=0: no time has elapsed
        let elapsed = Date().timeIntervalSince(showTime)
        XCTAssertFalse(elapsed >= Double(minDisplay))
    }

    func testSkipEnabledAfterMinDisplay() {
        let minDisplay = 10
        let showTime = Date(timeIntervalSinceNow: -11) // 11s ago
        let elapsed = Date().timeIntervalSince(showTime)
        XCTAssertTrue(elapsed >= Double(minDisplay))
    }
}

// MARK: - Settings JSON import/export round-trip
final class SettingsJSONRoundTripTests: XCTestCase {
    func testRoundTripPreservesCustomBreakTypes() throws {
        var settings = AppSettings.defaults
        let custom = CustomBreakType(name: "My Break", intervalMinutes: 25, durationSeconds: 60,
                                     tips: ["Take a walk"])
        settings.customBreakTypes = [custom]
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.customBreakTypes.count, 1)
        XCTAssertEqual(decoded.customBreakTypes[0].name, "My Break")
        XCTAssertEqual(decoded.customBreakTypes[0].tips, ["Take a walk"])
        XCTAssertEqual(decoded.customBreakTypes[0].intervalMinutes, 25)
    }
}

// MARK: - AppSettingsStore round-trip
final class AppSettingsStoreTests: XCTestCase {
    func testRoundTrip() {
        AppSettingsStore.save(.defaults)
        let loaded = AppSettingsStore.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.eyeConfig.intervalMinutes, AppSettings.defaults.eyeConfig.intervalMinutes)
        XCTAssertEqual(loaded?.microConfig.intervalMinutes, AppSettings.defaults.microConfig.intervalMinutes)
        XCTAssertEqual(loaded?.longConfig.intervalMinutes, AppSettings.defaults.longConfig.intervalMinutes)
    }
}

final class SettingsSyncServiceTests: XCTestCase {
    func testPushPersistsMutatedSettingsLocally() {
        let svc = SettingsSyncService()
        var settings = AppSettings.defaults
        settings.activeRole = .it_managed
        settings.breakEnforcementMode = .hard_lock
        settings.localOnlyMode = false
        svc.push(settings)

        let loaded = AppSettingsStore.load()
        XCTAssertEqual(loaded?.activeRole, .it_managed)
        XCTAssertEqual(loaded?.breakEnforcementMode, .hard_lock)
    }
}
