import XCTest
@testable import RopeCore

final class SessionHistoryStoreTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func record(_ id: Int64) -> WorkoutRecord {
        WorkoutRecord(id: id, startedAtEpochMs: id, mode: .free, totalCount: Int(id), completedGroups: 1, plannedGroups: 1, activeDurationMs: 1_000, completed: true)
    }

    func testEmptyStoreLoadsNothing() {
        XCTAssertEqual(SessionHistoryStore(directory: dir).load(), [])
    }

    func testPrependPutsNewestFirstAndPersists() {
        let store = SessionHistoryStore(directory: dir)
        store.prepend(record(1))
        store.prepend(record(2))
        XCTAssertEqual(store.load().map(\.id), [2, 1])
        XCTAssertEqual(SessionHistoryStore(directory: dir).load().map(\.id), [2, 1])
    }

    func testKeepsAtMostOneHundredRecords() {
        let store = SessionHistoryStore(directory: dir)
        for i in 1...105 { store.prepend(record(Int64(i))) }
        let loaded = store.load()
        XCTAssertEqual(loaded.count, 100)
        XCTAssertEqual(loaded.first?.id, 105)
    }

    func testClearRemovesEverything() {
        let store = SessionHistoryStore(directory: dir)
        store.prepend(record(1))
        store.clear()
        XCTAssertEqual(store.load(), [])
    }

    func testCorruptFileLoadsAsEmpty() throws {
        try "not json".write(to: dir.appendingPathComponent("workout_history.json"), atomically: true, encoding: .utf8)
        XCTAssertEqual(SessionHistoryStore(directory: dir).load(), [])
    }
}
