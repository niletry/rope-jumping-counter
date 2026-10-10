import XCTest
@testable import RopeCore

final class WorkoutModelsTests: XCTestCase {
    func testFreeModeNormalizesToSingleGroupWithoutRest() {
        let config = WorkoutConfig(mode: .free, targetCountPerGroup: 0, durationPerGroupSec: 1, groups: 5, restSec: 30).normalized()
        XCTAssertEqual(config.groups, 1)
        XCTAssertEqual(config.restSec, 0)
        XCTAssertEqual(config.targetCountPerGroup, 1)
        XCTAssertEqual(config.durationPerGroupSec, 5)
    }

    func testPoseFrameSubscriptIsNilOutOfRange() {
        let frame = PoseFrame(timestampMs: 0, landmarks: [PosePoint(x: 0.1, y: 0.2, z: 0, visibility: 1, presence: 1)], imageWidth: 540, imageHeight: 960)
        XCTAssertEqual(frame[0]?.x, 0.1)
        XCTAssertNil(frame[33])
    }

    func testJumpDetectionDefaultsJumpCountFromFlag() {
        XCTAssertEqual(JumpDetection(jumpDetected: true, state: .ready, quality: 1, guidance: "", normalizedLift: 0).jumpCount, 1)
        XCTAssertEqual(JumpDetection(jumpDetected: false, state: .ready, quality: 1, guidance: "", normalizedLift: 0).jumpCount, 0)
    }

    func testWorkoutRecordRoundTripsThroughJSON() throws {
        let record = WorkoutRecord(id: 7, startedAtEpochMs: 1_700_000_000_000, mode: .fixedCount, totalCount: 120, completedGroups: 2, plannedGroups: 3, activeDurationMs: 65_000, completed: false)
        let data = try JSONEncoder().encode(record)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutRecord.self, from: data), record)
    }
}
