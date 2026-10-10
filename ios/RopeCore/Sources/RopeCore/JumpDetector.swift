import Foundation

/// Detects a two-foot jump from normalized pose landmarks.
///
/// A line-by-line port of the Android `JumpDetector.kt`. It combines ankle and hip lift,
/// normalized by torso length, then applies hysteresis and timing constraints. Keeping this class
/// free of UIKit/MediaPipe types makes it deterministic and unit-testable on macOS.
public final class JumpDetector {
    /// Tunable thresholds. Defaults are the production values; the replay harness overrides them.
    public struct Params: Sendable {
        public var requiredCalibrationSamples: Int = 20
        public var minPointVisibility: Float = 0.25
        public var minAverageQuality: Float = 0.48
        public var minTorsoLength: Float = 0.08
        public var ankleWeight: Float = 0.72
        public var hipWeight: Float = 0.28
        public var smoothingAlpha: Float = 0.52
        public var baselineAlpha: Float = 0.025
        public var cycleFloorAlpha: Float = 0.18
        public var minFeetRisingVelocity: Float = 0.06
        public var maxFeetVelocityDifference: Float = 1.20
        public var feetVelocityDifferenceRatio: Float = 0.35
        public var risingLift: Float = 0.022
        public var risingVelocity: Float = 0.08
        public var airborneLift: Float = 0.050
        public var groundedLift: Float = 0.018
        public var minRisingMs: Int64 = 45
        public var maxRisingMs: Int64 = 500
        public var minRiseAmplitude: Float = 0.018
        public var minLandingSettleMs: Int64 = 250
        public var maxSettledVelocity: Float = 0.08
        public var maxJumpMs: Int64 = 850
        public var refractoryMs: Int64 = 180
        public var lostResetMs: Int64 = 900
        public var minSingleFootRisingVelocity: Float = -0.25
        public var landingVelocity: Float = -0.06

        public init() {}

        /// Both feet must rise together. The tolerance grows with the rise speed because landmark
        /// jitter scales with motion blur, so a fixed gap would reject the highest, fastest jumps.
        public func feetVelocityTolerance(_ averageVelocity: Float) -> Float {
            max(maxFeetVelocityDifference, feetVelocityDifferenceRatio * averageVelocity)
        }
    }

    private let p: Params
    private var state = MotionState.calibrating
    private var calibrationSamples = 0
    private var baselineLeftAnkleY: Float = 0
    private var baselineRightAnkleY: Float = 0
    private var baselineAnkleY: Float = 0
    private var baselineHipY: Float = 0
    private var baselineTorsoLength: Float = 0
    private var calibrationWindow: [Sample] = []
    private var smoothedLift: Float = 0
    private var previousLift: Float = 0
    private var previousLeftAnkleLift: Float = 0
    private var previousRightAnkleLift: Float = 0
    private var cycleFloorLift: Float = 0
    private var landingMinimumLift: Float = .infinity
    private var previousTimestampMs: Int64 = 0
    private var takeoffTimestampMs: Int64 = 0
    private var takeoffLift: Float = 0
    private var lastJumpTimestampMs: Int64 = Int64.min / 2
    private var peakLift: Float = 0
    private var lostSinceMs: Int64 = 0

    public init(params: Params = Params()) {
        self.p = params
    }

    public func reset() {
        state = .calibrating
        calibrationSamples = 0
        baselineLeftAnkleY = 0
        baselineRightAnkleY = 0
        baselineAnkleY = 0
        baselineHipY = 0
        baselineTorsoLength = 0
        calibrationWindow.removeAll()
        smoothedLift = 0
        previousLift = 0
        previousLeftAnkleLift = 0
        previousRightAnkleLift = 0
        cycleFloorLift = 0
        landingMinimumLift = .infinity
        previousTimestampMs = 0
        takeoffTimestampMs = 0
        takeoffLift = 0
        lastJumpTimestampMs = Int64.min / 2
        peakLift = 0
        lostSinceMs = 0
    }

    public func process(_ frame: PoseFrame) -> JumpDetection {
        guard let measurements = measurements(frame) else {
            if lostSinceMs == 0 { lostSinceMs = frame.timestampMs }
            if frame.timestampMs - lostSinceMs > p.lostResetMs {
                state = .lost
            }
            return result(0, 0, "请保持全身入镜", smoothedLift)
        }
        lostSinceMs = 0

        if state == .lost {
            state = .calibrating
            calibrationSamples = 0
            calibrationWindow.removeAll()
        }

        if state == .calibrating {
            calibrationWindow.append(Sample(timestampMs: frame.timestampMs, measurements: measurements))
            calibrationSamples = calibrationWindow.count
            if calibrationSamples < p.requiredCalibrationSamples {
                return result(0, measurements.quality, "正在校准，请继续跳", 0)
            }
            finishCalibration()
            // Replay the frames that were used for calibration through the state machine so a jump
            // that happened while we were still calibrating is counted instead of lost.
            var jumps = 0
            for sample in calibrationWindow where track(sample.measurements, sample.timestampMs) {
                jumps += 1
            }
            calibrationWindow.removeAll()
            return result(jumps, measurements.quality, guidance(), smoothedLift)
        }

        let detected = track(measurements, frame.timestampMs)
        return result(detected ? 1 : 0, measurements.quality, guidance(), smoothedLift)
    }

    private func guidance() -> String {
        switch state {
        case .ready: return "可以开始"
        case .rising, .airborne, .landing: return "计数中"
        default: return "正在校准，请继续跳"
        }
    }

    /// Runs one frame through the jump state machine. Returns true when a jump is completed.
    private func track(_ measurements: Measurements, _ timestampMs: Int64) -> Bool {
        // Do not compare the current position with the initial framing here. A jumper naturally
        // drifts sideways and toward/away from the camera. The per-cycle floor below absorbs that
        // accumulated translation, while the current torso length keeps jump amplitude normalized.
        let torso = max(measurements.torsoLength, p.minTorsoLength)
        let leftAnkleLift = (baselineLeftAnkleY - measurements.leftAnkleY) / torso
        let rightAnkleLift = (baselineRightAnkleY - measurements.rightAnkleY) / torso
        let rawLift = p.ankleWeight * (leftAnkleLift + rightAnkleLift) / 2 +
            p.hipWeight * (baselineHipY - measurements.hipY) / torso
        previousLift = smoothedLift
        smoothedLift += p.smoothingAlpha * (rawLift - smoothedLift)

        let deltaMs = min(max(timestampMs - previousTimestampMs, 1), 100)
        let velocity = (smoothedLift - previousLift) * 1_000 / Float(deltaMs)
        let leftAnkleVelocity = (leftAnkleLift - previousLeftAnkleLift) * 1_000 / Float(deltaMs)
        let rightAnkleVelocity = (rightAnkleLift - previousRightAnkleLift) * 1_000 / Float(deltaMs)
        let averageFeetVelocity = (leftAnkleVelocity + rightAnkleVelocity) / 2
        let feetRisingTogether = leftAnkleVelocity > p.minSingleFootRisingVelocity &&
            rightAnkleVelocity > p.minSingleFootRisingVelocity &&
            averageFeetVelocity > p.minFeetRisingVelocity &&
            abs(leftAnkleVelocity - rightAnkleVelocity) < p.feetVelocityTolerance(averageFeetVelocity)
        previousLeftAnkleLift = leftAnkleLift
        previousRightAnkleLift = rightAnkleLift
        previousTimestampMs = timestampMs
        var detected = false

        switch state {
        case .ready:
            updateGroundBaseline(measurements)
            if velocity <= p.risingVelocity {
                cycleFloorLift += p.cycleFloorAlpha * (smoothedLift - cycleFloorLift)
            }
            if feetRisingTogether &&
                smoothedLift - cycleFloorLift > p.risingLift &&
                velocity > p.risingVelocity {
                state = .rising
                takeoffTimestampMs = timestampMs
                takeoffLift = cycleFloorLift
                peakLift = smoothedLift
            }

        case .rising:
            peakLift = max(peakLift, smoothedLift)
            if peakLift - takeoffLift >= p.airborneLift {
                state = .airborne
            } else if velocity < p.landingVelocity {
                state = .ready
                cycleFloorLift = smoothedLift
            } else if timestampMs - takeoffTimestampMs > p.maxJumpMs {
                state = .ready
                cycleFloorLift = smoothedLift
            }

        case .airborne:
            peakLift = max(peakLift, smoothedLift)
            if velocity < p.landingVelocity {
                let risingDuration = timestampMs - takeoffTimestampMs
                detected = (p.minRisingMs...p.maxRisingMs).contains(risingDuration) &&
                    peakLift - takeoffLift >= p.minRiseAmplitude &&
                    timestampMs - lastJumpTimestampMs >= p.refractoryMs
                if detected { lastJumpTimestampMs = timestampMs }
                state = .landing
                landingMinimumLift = smoothedLift
            }

        case .landing:
            landingMinimumLift = min(landingMinimumLift, smoothedLift)
            let jumpDuration = timestampMs - takeoffTimestampMs
            if feetRisingTogether &&
                smoothedLift - landingMinimumLift > p.risingLift &&
                velocity > p.risingVelocity {
                cycleFloorLift = landingMinimumLift
                state = .rising
                takeoffTimestampMs = timestampMs
                takeoffLift = cycleFloorLift
                peakLift = smoothedLift
            } else if jumpDuration >= p.minLandingSettleMs &&
                abs(velocity) <= p.maxSettledVelocity {
                state = .ready
                cycleFloorLift = smoothedLift
                updateGroundBaseline(measurements)
            } else if jumpDuration > p.maxJumpMs {
                state = .ready
                cycleFloorLift = landingMinimumLift
            }

        case .calibrating, .lost:
            break
        }

        return detected
    }

    /// Calibration does not require the jumper to stand still. The detector collects a short window
    /// of valid frames and takes the lowest observed ankle/hip positions as the ground line, so it
    /// can join mid-session while the person is already jumping or the camera is hand-held. The
    /// per-cycle floor tracking in the state machine absorbs any residual offset.
    private func finishCalibration() {
        let first = calibrationWindow[0]
        baselineLeftAnkleY = calibrationWindow.map { $0.measurements.leftAnkleY }.max()!
        baselineRightAnkleY = calibrationWindow.map { $0.measurements.rightAnkleY }.max()!
        baselineAnkleY = calibrationWindow.map { $0.measurements.ankleY }.max()!
        baselineHipY = calibrationWindow.map { $0.measurements.hipY }.max()!
        let torsos = calibrationWindow.map { $0.measurements.torsoLength }.sorted()
        baselineTorsoLength = torsos[torsos.count / 2]

        // Seed the motion trackers from the first buffered frame so replaying the window does not
        // start with a spurious velocity spike relative to zero-initialised state.
        let torso = max(first.measurements.torsoLength, p.minTorsoLength)
        previousLeftAnkleLift = (baselineLeftAnkleY - first.measurements.leftAnkleY) / torso
        previousRightAnkleLift = (baselineRightAnkleY - first.measurements.rightAnkleY) / torso
        smoothedLift = p.ankleWeight * (previousLeftAnkleLift + previousRightAnkleLift) / 2 +
            p.hipWeight * (baselineHipY - first.measurements.hipY) / torso
        previousLift = smoothedLift
        previousTimestampMs = first.timestampMs
        cycleFloorLift = 0
        landingMinimumLift = .infinity
        state = .ready
    }

    private func updateGroundBaseline(_ measurements: Measurements) {
        if abs(smoothedLift - cycleFloorLift) > p.groundedLift { return }
        baselineLeftAnkleY += p.baselineAlpha * (measurements.leftAnkleY - baselineLeftAnkleY)
        baselineRightAnkleY += p.baselineAlpha * (measurements.rightAnkleY - baselineRightAnkleY)
        baselineAnkleY += p.baselineAlpha * (measurements.ankleY - baselineAnkleY)
        baselineHipY += p.baselineAlpha * (measurements.hipY - baselineHipY)
        baselineTorsoLength += p.baselineAlpha * (measurements.torsoLength - baselineTorsoLength)
    }

    private func measurements(_ frame: PoseFrame) -> Measurements? {
        guard let leftShoulder = frame[Self.leftShoulder],
              let rightShoulder = frame[Self.rightShoulder],
              let leftHip = frame[Self.leftHip],
              let rightHip = frame[Self.rightHip],
              let leftKnee = frame[Self.leftKnee],
              let rightKnee = frame[Self.rightKnee],
              let leftAnkle = frame[Self.leftAnkle],
              let rightAnkle = frame[Self.rightAnkle] else { return nil }

        let points = [leftShoulder, rightShoulder, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle]
        // Kotlin averages in Double; mirror that so the quality gate rounds identically.
        let quality = Float(points.map { Double(min($0.visibility, $0.presence)) }.reduce(0, +) / Double(points.count))
        if quality < p.minAverageQuality || points.contains(where: { $0.visibility < p.minPointVisibility }) {
            return nil
        }

        let shoulderX = (leftShoulder.x + rightShoulder.x) / 2
        let shoulderY = (leftShoulder.y + rightShoulder.y) / 2
        let hipX = (leftHip.x + rightHip.x) / 2
        let hipY = (leftHip.y + rightHip.y) / 2
        let torsoLength = Float(hypot(Double(shoulderX - hipX), Double(shoulderY - hipY)))
        if torsoLength < p.minTorsoLength { return nil }

        return Measurements(
            leftAnkleY: leftAnkle.y,
            rightAnkleY: rightAnkle.y,
            ankleY: (leftAnkle.y + rightAnkle.y) / 2,
            hipY: hipY,
            torsoLength: torsoLength,
            quality: quality
        )
    }

    private func result(_ jumpCount: Int, _ quality: Float, _ guidance: String, _ lift: Float) -> JumpDetection {
        JumpDetection(jumpDetected: jumpCount > 0, state: state, quality: quality, guidance: guidance, normalizedLift: lift, jumpCount: jumpCount)
    }

    private struct Sample {
        let timestampMs: Int64
        let measurements: Measurements
    }

    private struct Measurements {
        let leftAnkleY: Float
        let rightAnkleY: Float
        let ankleY: Float
        let hipY: Float
        let torsoLength: Float
        let quality: Float
    }

    private static let leftShoulder = 11
    private static let rightShoulder = 12
    private static let leftHip = 23
    private static let rightHip = 24
    private static let leftKnee = 25
    private static let rightKnee = 26
    private static let leftAnkle = 27
    private static let rightAnkle = 28
}
