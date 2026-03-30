import XCTest
@testable import LockOutCore

final class DiagnosticsStoreTests: XCTestCase {
    func testRecordAndReadBackDiagnosticsEvents() {
        let store = makeStore()
        store.clear()

        store.record(level: .info, category: "test", message: "first")
        store.record(level: .error, category: "test", message: "second")

        let events = store.recentEvents(limit: 10)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.first?.message, "first")
        XCTAssertEqual(events.last?.message, "second")
    }

    func testCountsByLevelReflectStoredEvents() {
        let store = makeStore()
        store.clear()

        store.record(level: .warning, category: "sync", message: "warn-1")
        store.record(level: .warning, category: "sync", message: "warn-2")
        store.record(level: .error, category: "sync", message: "error-1")

        let counts = store.countsByLevel(limit: 20)
        XCTAssertEqual(counts[.warning], 2)
        XCTAssertEqual(counts[.error], 1)
    }

    func testStoreAppliesEventRetentionCap() {
        let store = makeStore()
        store.clear()

        for index in 0..<520 {
            store.record(level: .debug, category: "cap", message: "event-\(index)")
        }

        let events = store.recentEvents(limit: 600)
        XCTAssertEqual(events.count, 500)
        XCTAssertEqual(events.first?.message, "event-20")
        XCTAssertEqual(events.last?.message, "event-519")
    }

    private func makeStore() -> DiagnosticsStore {
        let suiteName = "lockout.tests.diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return DiagnosticsStore(defaults: defaults)
    }
}
