import XCTest
@testable import LookAwayCore

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
}
