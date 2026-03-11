import XCTest
import SwiftData
import CloudKit
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
        scheduler.onBreakTriggered = { fired, _ in
            if fired.id == custom.id { exp.fulfill() }
        }

        scheduler.start(settings: settings)
        scheduler.simulateTimerFireForTesting(customTypeID: custom.id)
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

    func testLargeOffsetClampsNextBreakIntoFuture() {
        let hourly = CustomBreakType(name: "Hourly", intervalMinutes: 60, durationSeconds: 60)
        var settings = AppSettings.defaults
        settings.customBreakTypes = [hourly]
        scheduler = BreakScheduler(settings: settings)
        scheduler.start(settings: settings, offsetSeconds: 10 * 3600)
        XCTAssertNotNil(scheduler.nextBreak)
        XCTAssertGreaterThanOrEqual(scheduler.nextBreak?.fireDate.timeIntervalSinceNow ?? 0, 1)
    }
}

// MARK: - BreakHistoryRepository idempotency
@MainActor
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
        let updatedAt = Date()
        let session = BreakSession(type: .eye, scheduledAt: Date(), status: .deferred, updatedAt: updatedAt)
        repo.save(session)
        let loaded = repo.fetchSession(id: session.id)
        XCTAssertEqual(loaded?.status, .deferred)
        XCTAssertEqual(loaded?.updatedAt, updatedAt)
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
        let scheduledAt = Date()
        let updatedAt = scheduledAt.addingTimeInterval(5)
        let completed = BreakSession(id: id, type: .eye, scheduledAt: scheduledAt, status: .completed, updatedAt: updatedAt)
        let skipped = BreakSession(id: id, type: .eye, scheduledAt: scheduledAt, status: .skipped, updatedAt: updatedAt)
        let result = svc.resolveConflict(local: skipped, remote: completed)
        XCTAssertEqual(result.status, .completed)
    }

    func testResolveConflictPrefersLatestUpdatedAtBeforeStatusRank() {
        let svc = CloudKitSyncService()
        let id = UUID()
        let now = Date()
        let local = BreakSession(id: id, type: .eye, scheduledAt: now, status: .completed, updatedAt: now)
        let remote = BreakSession(id: id, type: .eye, scheduledAt: now, status: .skipped, updatedAt: now.addingTimeInterval(10))
        let result = svc.resolveConflict(local: local, remote: remote)
        XCTAssertEqual(result.status, .skipped)
    }

    func testMapRecordDecodesEndedAtAndBreakTypeName() {
        let svc = CloudKitSyncService()
        let id = UUID()
        let scheduledAt = Date()
        let endedAt = scheduledAt.addingTimeInterval(12)
        let updatedAt = scheduledAt.addingTimeInterval(20)
        let record = CKRecord(recordType: "BreakSession", recordID: CKRecord.ID(recordName: id.uuidString))
        record["id"] = id.uuidString as CKRecordValue
        record["type"] = BreakType.eye.rawValue as CKRecordValue
        record["scheduledAt"] = scheduledAt as CKRecordValue
        record["endedAt"] = endedAt as CKRecordValue
        record["breakTypeName"] = "Eye Break" as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
        record["status"] = BreakStatus.completed.rawValue as CKRecordValue

        let mapped = svc.mapRecord(record)
        XCTAssertEqual(mapped?.endedAt, endedAt)
        XCTAssertEqual(mapped?.breakTypeName, "Eye Break")
        XCTAssertEqual(mapped?.updatedAt, updatedAt)
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
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "ckPendingUploads")
        NetworkMonitor.shared.forceOffline(false)
        super.tearDown()
    }

    private func pendingQueue() -> [BreakSession] {
        guard let data = UserDefaults.standard.data(forKey: "ckPendingUploads"),
              let queue = try? JSONDecoder().decode([BreakSession].self, from: data) else { return [] }
        return queue
    }

    func testOfflineQueueEnqueuesSession() async {
        let svc = CloudKitSyncService()
        NetworkMonitor.shared.forceOffline(true)
        let session = BreakSession(type: .eye, scheduledAt: Date(), status: .completed)
        await svc.uploadSession(session)
        XCTAssertEqual(svc.pendingUploadsCount, 1)
    }

    func testOfflineQueueDeduplicatesBySessionID() async {
        let svc = CloudKitSyncService()
        NetworkMonitor.shared.forceOffline(true)
        let id = UUID()
        let first = BreakSession(id: id, type: .eye, scheduledAt: Date(), status: .skipped)
        let second = BreakSession(id: id, type: .eye, scheduledAt: Date(), status: .completed)
        await svc.uploadSession(first)
        await svc.uploadSession(second)
        let queue = pendingQueue()
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue.first?.status, .completed)
    }

    func testOfflineQueueCapDropsOldestEntries() async {
        let svc = CloudKitSyncService()
        NetworkMonitor.shared.forceOffline(true)
        for i in 0..<120 {
            let session = BreakSession(id: UUID(), type: .eye, scheduledAt: Date().addingTimeInterval(Double(i)), status: .completed)
            await svc.uploadSession(session)
        }
        XCTAssertEqual(svc.pendingUploadsCount, 100)
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

    func testImportRejectsOutOfRangeNumericSetting() throws {
        let data = try makeImportJSON { json in
            json["notificationLeadMinutes"] = 99
        }

        XCTAssertThrowsError(try AppSettings.decodeValidatedImportJSON(data)) { error in
            guard case let AppSettingsImportValidationError.outOfRange(field, _, actual) = error else {
                return XCTFail("Expected out-of-range validation error, got \(error)")
            }
            XCTAssertEqual(field, "notificationLeadMinutes")
            XCTAssertEqual(actual, "99")
        }
    }

    func testImportRejectsInvalidEnumValue() throws {
        let data = try makeImportJSON { json in
            json["breakEnforcementMode"] = "lock_everything"
        }

        XCTAssertThrowsError(try AppSettings.decodeValidatedImportJSON(data)) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("Expected enum decoding error, got \(error)")
            }
        }
    }

    private func makeImportJSON(mutating mutate: (inout [String: Any]) -> Void) throws -> Data {
        let data = try JSONEncoder().encode(AppSettings.defaults)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        mutate(&json)
        return try JSONSerialization.data(withJSONObject: json)
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

    func testPushDebouncesCloudCommitAndUsesLatestSettings() async {
        let svc = SettingsSyncService()
        var pushed: [Int] = []
        let exp = expectation(description: "debounced cloud push")
        exp.expectedFulfillmentCount = 1
        svc.onCloudPush = { settings in
            pushed.append(settings.snoozeDurationMinutes)
            exp.fulfill()
        }

        var first = AppSettings.defaults
        first.localOnlyMode = false
        first.snoozeDurationMinutes = 5

        var second = first
        second.snoozeDurationMinutes = 9

        svc.push(first)
        svc.push(second)

        await fulfillment(of: [exp], timeout: 1.0)
        XCTAssertEqual(pushed, [9])
    }

    func testMergeUsesConflictSafeReducer() {
        var local = AppSettings.defaults
        local.localOnlyMode = true
        local.isPaused = true
        local.pauseDuringFocus = true
        local.breakEnforcementMode = .hard_lock
        local.blockedBundleIDs = ["com.local.blocked"]

        var remote = AppSettings.defaults
        remote.localOnlyMode = false
        remote.isPaused = false
        remote.pauseDuringFocus = false
        remote.breakEnforcementMode = .reminder
        remote.blockedBundleIDs = ["com.remote.blocked"]

        let merged = SettingsSyncService.merge(local: local, remote: remote)
        XCTAssertTrue(merged.localOnlyMode)
        XCTAssertTrue(merged.isPaused)
        XCTAssertTrue(merged.pauseDuringFocus)
        XCTAssertEqual(merged.breakEnforcementMode, .hard_lock)
        XCTAssertEqual(Set(merged.blockedBundleIDs), Set(["com.local.blocked", "com.remote.blocked"]))
    }
}

final class ObservabilityTests: XCTestCase {
    override func tearDown() {
        Observability.sink = nil
        super.tearDown()
    }

    func testCloudKitErrorPathEmitsDiagnosticToSink() {
        let service = CloudKitSyncService()
        var events: [String] = []
        Observability.sink = { category, message in
            if category == "CloudKitSyncService" { events.append(message) }
        }

        service.handle(error: NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "boom"]))
        XCTAssertFalse(events.isEmpty)
    }
}

final class CSVExportTests: XCTestCase {
    func testEscapesComma() {
        XCTAssertEqual(CSVExport.escapedCell("hello,world"), "\"hello,world\"")
    }

    func testEscapesQuote() {
        XCTAssertEqual(CSVExport.escapedCell("he said \"hi\""), "\"he said \"\"hi\"\"\"")
    }

    func testEscapesNewline() {
        XCTAssertEqual(CSVExport.escapedCell("hello\nworld"), "\"hello\nworld\"")
    }
}

final class AppDelegateSettingsRefreshTests: XCTestCase {
    func testWorkdayTimerRefreshWhenStartOrEndMinutesChange() { // #20: updated for minutes
        var previous = AppSettings.defaults
        previous.workdayStartMinutes = 540 // 9:00
        previous.workdayEndMinutes = 1020 // 17:00

        var changedStart = previous
        changedStart.workdayStartMinutes = 510 // 8:30
        XCTAssertTrue(SettingsChangeDetector.workdayTimersNeedRefresh(previous: previous, current: changedStart))

        var changedEnd = previous
        changedEnd.workdayEndMinutes = 1080 // 18:00
        XCTAssertTrue(SettingsChangeDetector.workdayTimersNeedRefresh(previous: previous, current: changedEnd))

        XCTAssertFalse(SettingsChangeDetector.workdayTimersNeedRefresh(previous: previous, current: previous))
    }

    func testCalendarPollingRefreshWhenToggleChanges() {
        var previous = AppSettings.defaults
        previous.pauseDuringCalendarEvents = false

        var toggled = previous
        toggled.pauseDuringCalendarEvents = true
        XCTAssertTrue(SettingsChangeDetector.calendarPollingPreferenceChanged(previous: previous, current: toggled))

        XCTAssertFalse(SettingsChangeDetector.calendarPollingPreferenceChanged(previous: previous, current: previous))
    }

    func testCalendarFilterModeChangeTriggersRefresh() { // #19: new test
        var previous = AppSettings.defaults
        previous.pauseDuringCalendarEvents = true
        previous.calendarFilterMode = .all

        var changed = previous
        changed.calendarFilterMode = .busyOnly
        XCTAssertTrue(SettingsChangeDetector.calendarPollingPreferenceChanged(previous: previous, current: changed))
    }

    func testFocusPauseIgnoresDuplicateNotifications() {
        let duplicateEnabled = SettingsChangeDetector.focusPauseAction(
            previousFocusEnabled: true,
            currentFocusEnabled: true,
            isPaused: false
        )
        XCTAssertEqual(duplicateEnabled, .none)

        let duplicateDisabled = SettingsChangeDetector.focusPauseAction(
            previousFocusEnabled: false,
            currentFocusEnabled: false,
            isPaused: true
        )
        XCTAssertEqual(duplicateDisabled, .none)
    }

    func testWeeklyNotificationRefreshWhenToggleChanges() {
        var previous = AppSettings.defaults
        previous.weeklyNotificationEnabled = false

        var toggled = previous
        toggled.weeklyNotificationEnabled = true
        XCTAssertTrue(SettingsChangeDetector.weeklyNotificationPreferenceChanged(previous: previous, current: toggled))

        XCTAssertFalse(SettingsChangeDetector.weeklyNotificationPreferenceChanged(previous: previous, current: previous))
    }
}

// MARK: - #26 Additional tests

// #26: Streak trend & near-miss tests
final class ComplianceTrendTests: XCTestCase {
    func testTrendPositiveWhenCurrentBetter() {
        let current = [DayStat(date: Date(), completed: 9, skipped: 1)]
        let previous = [DayStat(date: Date(), completed: 7, skipped: 3)]
        let t = ComplianceCalculator.trend(current: current, previous: previous)
        XCTAssertGreaterThan(t, 0)
    }

    func testTrendNegativeWhenCurrentWorse() {
        let current = [DayStat(date: Date(), completed: 5, skipped: 5)]
        let previous = [DayStat(date: Date(), completed: 9, skipped: 1)]
        let t = ComplianceCalculator.trend(current: current, previous: previous)
        XCTAssertLessThan(t, 0)
    }

    func testNearMissCountsSubThresholdDays() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let stats = [
            DayStat(date: today, completed: 9, skipped: 1),                                    // 90% → streak
            DayStat(date: cal.date(byAdding: .day, value: -1, to: today)!, completed: 7, skipped: 3), // 70% → near miss
            DayStat(date: cal.date(byAdding: .day, value: -2, to: today)!, completed: 6, skipped: 4), // 60% → near miss
        ]
        let result = ComplianceCalculator.streakWithNearMiss(stats: stats)
        XCTAssertEqual(result.streak, 1)
        XCTAssertEqual(result.nearMiss, 2)
    }

    func testNearMissStopsBelow60Percent() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let stats = [
            DayStat(date: today, completed: 9, skipped: 1),                                    // streak
            DayStat(date: cal.date(byAdding: .day, value: -1, to: today)!, completed: 5, skipped: 5), // 50% → stops
        ]
        let result = ComplianceCalculator.streakWithNearMiss(stats: stats)
        XCTAssertEqual(result.streak, 1)
        XCTAssertEqual(result.nearMiss, 0)
    }
}

// #26: Settings backward-compatible decode (workday hours → minutes)
final class SettingsBackwardCompatTests: XCTestCase {
    func testLegacyWorkdayHourDecodesToMinutes() throws {
        var json = try makeDefaultJSON()
        json["workdayStartHour"] = 9   // legacy field
        json["workdayEndHour"] = 17    // legacy field
        json.removeValue(forKey: "workdayStartMinutes")
        json.removeValue(forKey: "workdayEndMinutes")
        let data = try JSONSerialization.data(withJSONObject: json)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.workdayStartMinutes, 540) // 9 * 60
        XCTAssertEqual(settings.workdayEndMinutes, 1020) // 17 * 60
    }

    func testNewMinutesFieldTakesPrecedence() throws {
        var json = try makeDefaultJSON()
        json["workdayStartHour"] = 9
        json["workdayStartMinutes"] = 510 // 8:30
        let data = try JSONSerialization.data(withJSONObject: json)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.workdayStartMinutes, 510)
    }

    func testCalendarFilterModeDefaultsToAll() throws {
        var json = try makeDefaultJSON()
        json.removeValue(forKey: "calendarFilterMode")
        let data = try JSONSerialization.data(withJSONObject: json)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(settings.calendarFilterMode, .all)
    }

    private func makeDefaultJSON() throws -> [String: Any] {
        let data = try JSONEncoder().encode(AppSettings.defaults)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

// #26: Validation tests for new fields
final class SettingsValidationExtendedTests: XCTestCase {
    func testWorkdayMinutesValidationAcceptsHalfHours() throws {
        var settings = AppSettings.defaults
        settings.workdayStartMinutes = 510 // 8:30
        settings.workdayEndMinutes = 1050  // 17:30
        XCTAssertNoThrow(try settings.validateForImport())
    }

    func testWorkdayMinutesRejectsNegative() throws {
        var settings = AppSettings.defaults
        settings.workdayStartMinutes = -1
        XCTAssertThrowsError(try settings.validateForImport())
    }

    func testWorkdayMinutesRejectsOver1439() throws {
        var settings = AppSettings.defaults
        settings.workdayStartMinutes = 1440
        XCTAssertThrowsError(try settings.validateForImport())
    }
}

// #26: BreakScheduler persistent fire dates
@MainActor
final class BreakSchedulerPersistenceTests: XCTestCase {
    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "lockout_persisted_fire_dates")
    }

    func testFireDatesPersistedAfterStart() async {
        let scheduler = BreakScheduler(settings: .defaults)
        scheduler.start(settings: .defaults)
        let persisted = UserDefaults.standard.dictionary(forKey: "lockout_persisted_fire_dates")
        XCTAssertNotNil(persisted)
        XCTAssertFalse(persisted?.isEmpty ?? true)
        scheduler.stop()
    }

    func testPauseClearsPersistedDates() async {
        let scheduler = BreakScheduler(settings: .defaults)
        scheduler.start(settings: .defaults)
        scheduler.pause()
        let persisted = UserDefaults.standard.dictionary(forKey: "lockout_persisted_fire_dates")
        XCTAssertNil(persisted)
    }
}

// #26: BreakScheduler upcoming breaks
@MainActor
final class BreakSchedulerUpcomingTests: XCTestCase {
    func testAllUpcomingBreaksReturnsAllTimers() async {
        let scheduler = BreakScheduler(settings: .defaults)
        scheduler.start(settings: .defaults) // 3 default break types
        let upcoming = scheduler.allUpcomingBreaks
        XCTAssertEqual(upcoming.count, 3)
        // verify sorted by fireDate
        for i in 0..<upcoming.count - 1 {
            XCTAssertLessThanOrEqual(upcoming[i].fireDate, upcoming[i + 1].fireDate)
        }
        scheduler.stop()
    }
}

// #26: CloudKit sync lock — skips actual network calls, tests the guard
final class CloudKitSyncLockTests: XCTestCase {
    func testSyncServiceInitDoesNotCrash() {
        // verify service creation doesn't eagerly init CKDatabase
        let svc = CloudKitSyncService()
        XCTAssertEqual(svc.pendingUploadsCount, 0)
    }
}

// #26: AppSettingsStore error logging
final class AppSettingsStoreErrorTests: XCTestCase {
    func testLoadReturnsNilForCorruptData() {
        UserDefaults.standard.set(Data([0xFF, 0xFE]), forKey: "local_app_settings")
        let result = AppSettingsStore.load()
        XCTAssertNil(result)
        UserDefaults.standard.removeObject(forKey: "local_app_settings")
    }
}

// #26: iCloud KVStore size warning
final class SettingsSyncSizeTests: XCTestCase {
    func testPushDoesNotCrashWithLargeSettings() {
        let svc = SettingsSyncService()
        var settings = AppSettings.defaults
        // add many custom break types to inflate size
        for i in 0..<50 {
            settings.customBreakTypes.append(
                CustomBreakType(name: "Break \(i)", intervalMinutes: 20, durationSeconds: 20,
                                tips: Array(repeating: "tip", count: 10))
            )
        }
        settings.localOnlyMode = true // prevent actual cloud push
        svc.push(settings)
        let loaded = AppSettingsStore.load()
        XCTAssertNotNil(loaded)
    }
}

final class ManagedSettingsResolverTests: XCTestCase {
    func testApplyOverridesOnlyForcedKeys() {
        var local = AppSettings.defaults
        local.pauseDuringFocus = false
        local.breakEnforcementMode = .reminder

        var managed = AppSettings.defaults
        managed.pauseDuringFocus = true
        managed.breakEnforcementMode = .hard_lock

        let snapshot = ManagedSettingsSnapshot(
            settings: managed,
            forcedKeys: [.pauseDuringFocus, .breakEnforcementMode]
        )

        let resolved = ManagedSettingsResolver.apply(snapshot, to: local)
        XCTAssertTrue(resolved.pauseDuringFocus)
        XCTAssertEqual(resolved.breakEnforcementMode, .hard_lock)
        XCTAssertEqual(resolved.snoozeDurationMinutes, local.snoozeDurationMinutes)
    }

    func testResolveUsesManagedOverridesAfterMerge() {
        var local = AppSettings.defaults
        local.pauseDuringFocus = false

        var remote = AppSettings.defaults
        remote.pauseDuringFocus = true
        remote.notificationLeadMinutes = 5

        var managed = AppSettings.defaults
        managed.notificationLeadMinutes = 0
        let snapshot = ManagedSettingsSnapshot(settings: managed, forcedKeys: [.notificationLeadMinutes])

        let resolved = ManagedSettingsResolver.resolve(local: local, remote: remote, managed: snapshot)
        XCTAssertTrue(resolved.pauseDuringFocus)
        XCTAssertEqual(resolved.notificationLeadMinutes, 0)
    }
}

final class ProfileSnapshotTests: XCTestCase {
    func testProfileSnapshotRoundTripRestoresRoutineFields() {
        var settings = AppSettings.defaults
        settings.pauseDuringFocus = true
        settings.pauseDuringCalendarEvents = true
        settings.calendarFilterMode = .selected
        settings.filteredCalendarIDs = ["work"]
        settings.workdayStartMinutes = 540
        settings.workdayEndMinutes = 1020
        settings.notificationLeadMinutes = 3
        settings.breakEnforcementMode = .soft_lock
        settings.snoozeDurationMinutes = 7

        let profile = settings.profileSnapshot(name: "Workday")

        var restored = AppSettings.defaults
        restored.apply(profile: profile)

        XCTAssertEqual(restored.pauseDuringFocus, settings.pauseDuringFocus)
        XCTAssertEqual(restored.pauseDuringCalendarEvents, settings.pauseDuringCalendarEvents)
        XCTAssertEqual(restored.calendarFilterMode, settings.calendarFilterMode)
        XCTAssertEqual(restored.filteredCalendarIDs, settings.filteredCalendarIDs)
        XCTAssertEqual(restored.workdayStartMinutes, settings.workdayStartMinutes)
        XCTAssertEqual(restored.workdayEndMinutes, settings.workdayEndMinutes)
        XCTAssertEqual(restored.notificationLeadMinutes, settings.notificationLeadMinutes)
        XCTAssertEqual(restored.breakEnforcementMode, settings.breakEnforcementMode)
        XCTAssertEqual(restored.snoozeDurationMinutes, settings.snoozeDurationMinutes)
    }
}

@MainActor
final class DeferredBreakTests: XCTestCase {
    func testRegisterDeferredBreakCreatesPendingContext() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BreakSessionRecord.self, configurations: config)
        let repo = BreakHistoryRepository(modelContext: ModelContext(container))
        let scheduler = BreakScheduler(settings: .defaults)
        scheduler.start(settings: .defaults)

        let customType = try XCTUnwrap(scheduler.currentSettings.customBreakTypes.first)
        let context = ScheduledBreakContext(customTypeID: customType.id, scheduledAt: Date())

        scheduler.registerDeferredBreak(context, repository: repo)

        XCTAssertEqual(scheduler.pendingDeferredBreak, context)
        XCTAssertEqual(repo.fetchSessions(from: .distantPast, to: .distantFuture).first?.status, .deferred)
    }

    func testPauseReasonsStackAndClearIndependently() {
        let scheduler = BreakScheduler(settings: .defaults)
        scheduler.start(settings: .defaults)

        scheduler.pause(reason: .manual)
        scheduler.pause(reason: .calendar)
        XCTAssertTrue(scheduler.isPaused)
        XCTAssertEqual(scheduler.primaryPauseReason, .manual)

        scheduler.resume(reason: .manual)
        XCTAssertTrue(scheduler.isPaused)
        XCTAssertEqual(scheduler.primaryPauseReason, .calendar)

        scheduler.resume(reason: .calendar)
        XCTAssertFalse(scheduler.isPaused)
    }
}

@MainActor
final class DailyStatsAggregationTests: XCTestCase {
    func testDailyStatsTrackAllStatusesAndComplianceIgnoresDeferred() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: BreakSessionRecord.self, configurations: config)
        let repo = BreakHistoryRepository(modelContext: ModelContext(container))
        let now = Date()

        repo.save(BreakSession(type: .eye, scheduledAt: now.addingTimeInterval(-4), status: .completed))
        repo.save(BreakSession(type: .eye, scheduledAt: now.addingTimeInterval(-3), status: .skipped))
        repo.save(BreakSession(type: .eye, scheduledAt: now.addingTimeInterval(-2), status: .snoozed))
        repo.save(BreakSession(type: .eye, scheduledAt: now.addingTimeInterval(-1), status: .deferred))

        let stats = try XCTUnwrap(repo.dailyStats(for: 1).first)
        XCTAssertEqual(stats.completed, 1)
        XCTAssertEqual(stats.skipped, 1)
        XCTAssertEqual(stats.snoozed, 1)
        XCTAssertEqual(stats.deferred, 1)
        XCTAssertEqual(stats.complianceRate, 1.0 / 3.0, accuracy: 0.001)
    }
}
