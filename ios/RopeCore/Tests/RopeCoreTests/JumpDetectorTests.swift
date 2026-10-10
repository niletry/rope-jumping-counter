import XCTest
@testable import RopeCore

/// Ported one-to-one from the Android JumpDetectorTest so both detectors are held to the same cases.
final class JumpDetectorTests: XCTestCase {
    func testOneTakeoffAndLandingCountsExactlyOnce() {
        let detector = JumpDetector()
        var timestamp: Int64 = 0
        for _ in 0..<28 {
            _ = detector.process(frame(timestamp, 0))
            timestamp += 33
        }

        var jumps = 0
        let offsets: [Float] = [0.005, 0.015, 0.030, 0.045, 0.050, 0.045, 0.030, 0.015, 0.004, 0, 0, 0, 0, 0]
        for offset in offsets {
            if detector.process(frame(timestamp, offset)).jumpDetected { jumps += 1 }
            timestamp += 33
        }
        XCTAssertEqual(jumps, 1)
    }

    func testSmallBodySwayIsIgnored() {
        let detector = JumpDetector()
        var timestamp: Int64 = 0
        for _ in 0..<28 {
            _ = detector.process(frame(timestamp, 0))
            timestamp += 33
        }

        var jumps = 0
        for index in 0..<60 {
            let offset: Float = index % 2 == 0 ? 0.003 : -0.003
            if detector.process(frame(timestamp, offset)).jumpDetected { jumps += 1 }
            timestamp += 33
        }
        XCTAssertEqual(jumps, 0)
    }

    func testMissingPoseClearsTrackingAndRequestsRecalibration() {
        let detector = JumpDetector()
        var timestamp: Int64 = 0
        for _ in 0..<28 {
            _ = detector.process(frame(timestamp, 0))
            timestamp += 33
        }

        var result = detector.process(PoseFrame(timestampMs: timestamp, landmarks: [], imageWidth: 540, imageHeight: 960))
        for _ in 0..<32 {
            timestamp += 33
            result = detector.process(PoseFrame(timestampMs: timestamp, landmarks: [], imageWidth: 540, imageHeight: 960))
        }
        XCTAssertEqual(result.state, .lost)
    }

    func testAllZeroLandmarksAskForFullBody() {
        let detector = JumpDetector()
        let zeros = Array(repeating: PosePoint(x: 0, y: 0, z: 0, visibility: 0, presence: 0), count: 33)
        let result = detector.process(PoseFrame(timestampMs: 0, landmarks: zeros, imageWidth: 540, imageHeight: 960))
        XCTAssertEqual(result.guidance, "请保持全身入镜")
        XCTAssertFalse(result.jumpDetected)
    }

    func testWalkingTowardCameraDoesNotCount() {
        let detector = JumpDetector()
        var timestamp: Int64 = 0
        for _ in 0..<24 {
            _ = detector.process(frame(timestamp, 0))
            timestamp += 33
        }

        var jumps = 0
        for scale: Float in [1.05, 1.10, 1.16, 1.22, 1.28] {
            if detector.process(frame(timestamp, 0, scale: scale)).jumpDetected { jumps += 1 }
            timestamp += 33
        }
        XCTAssertEqual(jumps, 0)
    }

    func testRepeatedFastJumpsCountWithoutReturningToOriginalGroundLine() {
        let detector = JumpDetector()
        var timestamp: Int64 = 0
        for _ in 0..<24 {
            _ = detector.process(frame(timestamp, 0))
            timestamp += 33
        }

        var jumps = 0
        for _ in 0..<5 {
            for offset: Float in [0.015, 0.025, 0.042, 0.055, 0.048, 0.032, 0.020, 0.016, 0.015] {
                if detector.process(frame(timestamp, offset)).jumpDetected { jumps += 1 }
                timestamp += 33
            }
        }
        XCTAssertEqual(jumps, 5)
    }

    func testRepeatedJumpsWithAProgressivelyShiftedGroundLineKeepCounting() {
        let detector = JumpDetector()
        var timestamp: Int64 = 0
        for _ in 0..<24 {
            _ = detector.process(frame(timestamp, 0))
            timestamp += 33
        }

        var jumps = 0
        for jumpIndex in 0..<7 {
            let floor = Float(jumpIndex) * 0.009
            for offset in [floor, floor + 0.008, floor + 0.020, floor + 0.036, floor + 0.050, floor + 0.042, floor + 0.026, floor + 0.010, floor] {
                if detector.process(frame(timestamp, offset)).jumpDetected { jumps += 1 }
                timestamp += 33
            }
        }
        XCTAssertEqual(jumps, 7)
    }

    func testLargeLandingPositionChangesDoNotInterruptCounting() {
        let detector = JumpDetector()
        var timestamp: Int64 = 0
        for _ in 0..<24 {
            _ = detector.process(frame(timestamp, 0))
            timestamp += 33
        }

        let landingPositions: [(Float, Float, Float)] = [
            (-0.18, 0.00, 0.82), (0.16, 0.025, 1.18), (-0.22, -0.030, 1.35),
            (0.20, 0.045, 0.88), (-0.12, -0.020, 1.25), (0.10, 0.030, 0.95),
        ]
        var jumps = 0
        for (horizontalShift, groundShift, scale) in landingPositions {
            for _ in 0..<4 {
                _ = detector.process(frame(timestamp, groundShift, scale: scale, horizontalShift: horizontalShift))
                timestamp += 33
            }
            for jumpLift: Float in [0.008, 0.022, 0.042, 0.060, 0.050, 0.030, 0.012, 0] {
                if detector.process(frame(timestamp, groundShift + jumpLift, scale: scale, horizontalShift: horizontalShift)).jumpDetected {
                    jumps += 1
                }
                timestamp += 33
            }
        }
        XCTAssertEqual(jumps, landingPositions.count)
    }

    func testAlreadyJumpingAtStartStartsCountingWithoutStandingStill() {
        let detector = JumpDetector()
        var timestamp: Int64 = 0
        let cycle: [Float] = [0, 0.012, 0.030, 0.048, 0.055, 0.045, 0.025, 0.008, 0, 0]
        var jumps = 0
        for _ in 0..<10 {
            for offset in cycle {
                // Hand-held camera: add a slow drift to every landmark.
                let drift = 0.004 * Float(timestamp / 33 % 7)
                if detector.process(frame(timestamp, offset, horizontalShift: drift)).jumpDetected { jumps += 1 }
                timestamp += 33
            }
        }
        // The first cycles are consumed by calibration; every later cycle must be counted.
        XCTAssertGreaterThanOrEqual(jumps, 7, "expected at least 7 jumps, got \(jumps)")
    }

    func testJumpDuringCalibrationWindowIsCountedAfterReplay() {
        let detector = JumpDetector()
        var timestamp: Int64 = 0
        let cycle: [Float] = [0, 0.012, 0.030, 0.048, 0.055, 0.045, 0.025, 0.008, 0, 0]
        var jumps = 0
        // Three jumps starting at frame 0. The first one completes inside the 20-frame
        // calibration window and must be recovered when the window is replayed.
        for _ in 0..<3 {
            for offset in cycle {
                jumps += detector.process(frame(timestamp, offset)).jumpCount
                timestamp += 33
            }
        }
        XCTAssertEqual(jumps, 3)
    }

    private func frame(_ timestampMs: Int64, _ shiftUp: Float, scale: Float = 1, horizontalShift: Float = 0) -> PoseFrame {
        var points = Array(repeating: PosePoint(x: 0.5, y: 0.5, z: 0, visibility: 1, presence: 1), count: 33)
        func p(_ x: Float, _ y: Float) -> PosePoint { PosePoint(x: x + horizontalShift, y: y - shiftUp, z: 0, visibility: 1, presence: 1) }
        points[11] = p(0.42, 0.55 - 0.25 * scale)
        points[12] = p(0.58, 0.55 - 0.25 * scale)
        points[23] = p(0.45, 0.55)
        points[24] = p(0.55, 0.55)
        points[25] = p(0.46, 0.55 + 0.17 * scale)
        points[26] = p(0.54, 0.55 + 0.17 * scale)
        points[27] = p(0.46, 0.55 + 0.35 * scale)
        points[28] = p(0.54, 0.55 + 0.35 * scale)
        return PoseFrame(timestampMs: timestampMs, landmarks: points, imageWidth: 540, imageHeight: 960)
    }
}
