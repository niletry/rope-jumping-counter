import XCTest
@testable import RopeCore

/// Ported one-to-one from the Android WorkoutEngineTest.
final class WorkoutEngineTests: XCTestCase {
    func testFixedCountRunsGroupsAndRest() {
        let engine = WorkoutEngine(
            config: WorkoutConfig(mode: .fixedCount, targetCountPerGroup: 2, groups: 2, restSec: 10),
            startedAtMs: 0
        )

        XCTAssertEqual(engine.tick(3_000).phase, .preparing)
        _ = engine.markPoseReady(3_000)
        // No countdown: the engine waits for the first jump, which starts and counts the group.
        XCTAssertEqual(engine.tick(6_000).phase, .armed)
        let started = engine.recordJump(6_200)
        XCTAssertEqual(started.phase, .active)
        XCTAssertEqual(started.totalCount, 1)
        let resting = engine.recordJump(6_500)
        XCTAssertEqual(resting.phase, .rest)
        XCTAssertEqual(resting.currentGroup, 2)
        XCTAssertEqual(resting.totalCount, 2)
        XCTAssertEqual(resting.totalActiveMs, 300)

        XCTAssertEqual(engine.tick(16_500).phase, .armed)
        XCTAssertEqual(engine.tick(19_500).phase, .armed)
        _ = engine.recordJump(19_800)
        let complete = engine.recordJump(20_100)
        XCTAssertEqual(complete.phase, .complete)
        XCTAssertEqual(complete.totalCount, 4)
        XCTAssertEqual(complete.totalActiveMs, 600)
    }

    func testPauseDoesNotConsumeTimedGroup() {
        let engine = WorkoutEngine(
            config: WorkoutConfig(mode: .fixedTime, durationPerGroupSec: 10, groups: 1),
            startedAtMs: 0
        )

        _ = engine.markPoseReady(0)
        _ = engine.recordJump(3_000)
        _ = engine.togglePause(8_000)
        XCTAssertEqual(engine.tick(30_000).phase, .paused)
        _ = engine.togglePause(30_000)
        XCTAssertEqual(engine.tick(34_999).phase, .active)
        XCTAssertEqual(engine.tick(35_000).phase, .complete)
    }

    func testArmedWaitsForFirstJumpAndClockStartsThere() {
        let engine = WorkoutEngine(config: WorkoutConfig(mode: .free), startedAtMs: 0)

        XCTAssertEqual(engine.tick(20_000).phase, .preparing)
        XCTAssertEqual(engine.markPoseReady(20_000).phase, .armed)
        XCTAssertEqual(engine.tick(60_000).phase, .armed)
        XCTAssertEqual(engine.tick(60_000).totalActiveMs, 0)
        let first = engine.recordJump(61_000)
        XCTAssertEqual(first.phase, .active)
        XCTAssertEqual(first.totalCount, 1)
        XCTAssertEqual(engine.tick(63_000).totalActiveMs, 2_000)
    }

    func testLosingPoseWhileArmedReturnsToPreparation() {
        let engine = WorkoutEngine(config: WorkoutConfig(mode: .free), startedAtMs: 0)

        _ = engine.markPoseReady(1_000)
        XCTAssertEqual(engine.tick(2_000).phase, .armed)
        XCTAssertEqual(engine.requirePosePreparation(2_000).phase, .preparing)
        XCTAssertEqual(engine.tick(20_000).phase, .preparing)
    }

    func testFinishEarlyFromPauseCountsActiveTimeUpToThePause() {
        let engine = WorkoutEngine(config: WorkoutConfig(mode: .free), startedAtMs: 0)
        _ = engine.markPoseReady(0)
        _ = engine.recordJump(1_000)
        _ = engine.togglePause(4_000)
        let done = engine.finishEarly(9_000)
        XCTAssertEqual(done.phase, .complete)
        XCTAssertTrue(done.endedEarly)
        XCTAssertEqual(done.totalActiveMs, 3_000)
    }
}
