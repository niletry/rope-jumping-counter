package com.yzrun.ropecounter.counter

import com.yzrun.ropecounter.vision.JumpDetection
import com.yzrun.ropecounter.vision.MotionState
import com.yzrun.ropecounter.vision.PoseFrame
import kotlin.math.abs
import kotlin.math.hypot

/**
 * Detects a two-foot jump from normalized pose landmarks.
 *
 * The detector intentionally does not try to see the rope. It combines ankle and hip lift,
 * normalized by torso length, then applies hysteresis and timing constraints. Keeping this class
 * free of Android/MediaPipe types makes it deterministic and unit-testable.
 */
class JumpDetector(private val p: Params = Params()) {
    private var state = MotionState.CALIBRATING
    private var calibrationSamples = 0
    private var baselineLeftAnkleY = 0f
    private var baselineRightAnkleY = 0f
    private var baselineAnkleY = 0f
    private var baselineHipY = 0f
    private var baselineTorsoLength = 0f
    private val calibrationWindow = ArrayList<Sample>()
    private var smoothedLift = 0f
    private var previousLift = 0f
    private var previousLeftAnkleLift = 0f
    private var previousRightAnkleLift = 0f
    private var cycleFloorLift = 0f
    private var landingMinimumLift = Float.POSITIVE_INFINITY
    private var previousTimestampMs = 0L
    private var takeoffTimestampMs = 0L
    private var takeoffLift = 0f
    private var lastJumpTimestampMs = Long.MIN_VALUE / 2
    private var peakLift = 0f
    private var lostSinceMs = 0L

    fun reset() {
        state = MotionState.CALIBRATING
        calibrationSamples = 0
        baselineLeftAnkleY = 0f
        baselineRightAnkleY = 0f
        baselineAnkleY = 0f
        baselineHipY = 0f
        baselineTorsoLength = 0f
        calibrationWindow.clear()
        smoothedLift = 0f
        previousLift = 0f
        previousLeftAnkleLift = 0f
        previousRightAnkleLift = 0f
        cycleFloorLift = 0f
        landingMinimumLift = Float.POSITIVE_INFINITY
        previousTimestampMs = 0L
        takeoffTimestampMs = 0L
        takeoffLift = 0f
        lastJumpTimestampMs = Long.MIN_VALUE / 2
        peakLift = 0f
        lostSinceMs = 0L
    }

    fun process(frame: PoseFrame): JumpDetection {
        val measurements = measurements(frame)
        if (measurements == null) {
            if (lostSinceMs == 0L) lostSinceMs = frame.timestampMs
            if (frame.timestampMs - lostSinceMs > p.LOST_RESET_MS) {
                state = MotionState.LOST
            }
            return result(0, 0f, "请保持全身入镜", smoothedLift)
        }
        lostSinceMs = 0L

        if (state == MotionState.LOST) {
            state = MotionState.CALIBRATING
            calibrationSamples = 0
            calibrationWindow.clear()
        }

        if (state == MotionState.CALIBRATING) {
            calibrationWindow.add(Sample(frame.timestampMs, measurements))
            calibrationSamples = calibrationWindow.size
            if (calibrationSamples < p.REQUIRED_CALIBRATION_SAMPLES) {
                return result(0, measurements.quality, "正在校准，请继续跳", 0f)
            }
            finishCalibration()
            // Replay the frames that were used for calibration through the state machine so a jump
            // that happened while we were still calibrating is counted instead of lost.
            var jumps = 0
            calibrationWindow.forEach { if (track(it.measurements, it.timestampMs)) jumps++ }
            calibrationWindow.clear()
            return result(jumps, measurements.quality, guidance(), smoothedLift)
        }

        val detected = track(measurements, frame.timestampMs)
        return result(if (detected) 1 else 0, measurements.quality, guidance(), smoothedLift)
    }

    private fun guidance(): String = when (state) {
        MotionState.READY -> "可以开始"
        MotionState.RISING,
        MotionState.AIRBORNE,
        MotionState.LANDING,
        -> "计数中"
        else -> "正在校准，请继续跳"
    }

    /** Runs one frame through the jump state machine. Returns true when a jump is completed. */
    private fun track(measurements: Measurements, timestampMs: Long): Boolean {
        // Do not compare the current position with the initial framing here. A jumper naturally
        // drifts sideways and toward/away from the camera. The per-cycle floor below absorbs that
        // accumulated translation, while the current torso length keeps jump amplitude normalized.
        val torso = measurements.torsoLength.coerceAtLeast(p.MIN_TORSO_LENGTH)
        val leftAnkleLift = (baselineLeftAnkleY - measurements.leftAnkleY) / torso
        val rightAnkleLift = (baselineRightAnkleY - measurements.rightAnkleY) / torso
        val rawLift = p.ANKLE_WEIGHT * (leftAnkleLift + rightAnkleLift) / 2f +
            p.HIP_WEIGHT * (baselineHipY - measurements.hipY) / torso
        previousLift = smoothedLift
        smoothedLift += p.SMOOTHING_ALPHA * (rawLift - smoothedLift)

        val deltaMs = (timestampMs - previousTimestampMs).coerceIn(1L, 100L)
        val velocity = (smoothedLift - previousLift) * 1_000f / deltaMs
        val leftAnkleVelocity = (leftAnkleLift - previousLeftAnkleLift) * 1_000f / deltaMs
        val rightAnkleVelocity = (rightAnkleLift - previousRightAnkleLift) * 1_000f / deltaMs
        val feetRisingTogether = leftAnkleVelocity > p.MIN_SINGLE_FOOT_RISING_VELOCITY &&
            rightAnkleVelocity > p.MIN_SINGLE_FOOT_RISING_VELOCITY &&
            (leftAnkleVelocity + rightAnkleVelocity) / 2f > p.MIN_FEET_RISING_VELOCITY &&
            abs(leftAnkleVelocity - rightAnkleVelocity) < p.feetVelocityTolerance((leftAnkleVelocity + rightAnkleVelocity) / 2f)
        previousLeftAnkleLift = leftAnkleLift
        previousRightAnkleLift = rightAnkleLift
        previousTimestampMs = timestampMs
        var detected = false

        when (state) {
            MotionState.READY -> {
                updateGroundBaseline(measurements)
                if (velocity <= p.RISING_VELOCITY) {
                    cycleFloorLift += p.CYCLE_FLOOR_ALPHA * (smoothedLift - cycleFloorLift)
                }
                if (
                    feetRisingTogether &&
                    smoothedLift - cycleFloorLift > p.RISING_LIFT &&
                    velocity > p.RISING_VELOCITY
                ) {
                    state = MotionState.RISING
                    takeoffTimestampMs = timestampMs
                    takeoffLift = cycleFloorLift
                    peakLift = smoothedLift
                }
            }

            MotionState.RISING -> {
                peakLift = maxOf(peakLift, smoothedLift)
                when {
                    peakLift - takeoffLift >= p.AIRBORNE_LIFT -> state = MotionState.AIRBORNE
                    velocity < p.LANDING_VELOCITY -> {
                        state = MotionState.READY
                        cycleFloorLift = smoothedLift
                    }
                    timestampMs - takeoffTimestampMs > p.MAX_JUMP_MS -> {
                        state = MotionState.READY
                        cycleFloorLift = smoothedLift
                    }
                }
            }

            MotionState.AIRBORNE -> {
                peakLift = maxOf(peakLift, smoothedLift)
                if (velocity < p.LANDING_VELOCITY) {
                    val risingDuration = timestampMs - takeoffTimestampMs
                    detected = risingDuration in p.MIN_RISING_MS..p.MAX_RISING_MS &&
                        peakLift - takeoffLift >= p.MIN_RISE_AMPLITUDE &&
                        timestampMs - lastJumpTimestampMs >= p.REFRACTORY_MS
                    if (detected) lastJumpTimestampMs = timestampMs
                    state = MotionState.LANDING
                    landingMinimumLift = smoothedLift
                }
            }

            MotionState.LANDING -> {
                landingMinimumLift = minOf(landingMinimumLift, smoothedLift)
                val jumpDuration = timestampMs - takeoffTimestampMs
                if (
                    feetRisingTogether &&
                    smoothedLift - landingMinimumLift > p.RISING_LIFT &&
                    velocity > p.RISING_VELOCITY
                ) {
                    cycleFloorLift = landingMinimumLift
                    state = MotionState.RISING
                    takeoffTimestampMs = timestampMs
                    takeoffLift = cycleFloorLift
                    peakLift = smoothedLift
                } else if (
                    jumpDuration >= p.MIN_LANDING_SETTLE_MS &&
                    abs(velocity) <= p.MAX_SETTLED_VELOCITY
                ) {
                    state = MotionState.READY
                    cycleFloorLift = smoothedLift
                    updateGroundBaseline(measurements)
                } else if (jumpDuration > p.MAX_JUMP_MS) {
                    state = MotionState.READY
                    cycleFloorLift = landingMinimumLift
                }
            }

            else -> Unit
        }

        return detected
    }

    /**
     * Calibration does not require the jumper to stand still. The detector collects a short window
     * of valid frames and takes the lowest observed ankle/hip positions as the ground line, so it
     * can join mid-session while the person is already jumping or the camera is hand-held. The
     * per-cycle floor tracking in the state machine absorbs any residual offset.
     */
    private fun finishCalibration() {
        val first = calibrationWindow.first()
        baselineLeftAnkleY = calibrationWindow.maxOf { it.measurements.leftAnkleY }
        baselineRightAnkleY = calibrationWindow.maxOf { it.measurements.rightAnkleY }
        baselineAnkleY = calibrationWindow.maxOf { it.measurements.ankleY }
        baselineHipY = calibrationWindow.maxOf { it.measurements.hipY }
        baselineTorsoLength = calibrationWindow.map { it.measurements.torsoLength }.sorted()
            .let { it[it.size / 2] }

        // Seed the motion trackers from the first buffered frame so replaying the window does not
        // start with a spurious velocity spike relative to zero-initialised state.
        val torso = first.measurements.torsoLength.coerceAtLeast(p.MIN_TORSO_LENGTH)
        previousLeftAnkleLift = (baselineLeftAnkleY - first.measurements.leftAnkleY) / torso
        previousRightAnkleLift = (baselineRightAnkleY - first.measurements.rightAnkleY) / torso
        smoothedLift = p.ANKLE_WEIGHT * (previousLeftAnkleLift + previousRightAnkleLift) / 2f +
            p.HIP_WEIGHT * (baselineHipY - first.measurements.hipY) / torso
        previousLift = smoothedLift
        previousTimestampMs = first.timestampMs
        cycleFloorLift = 0f
        landingMinimumLift = Float.POSITIVE_INFINITY
        state = MotionState.READY
    }

    private fun updateGroundBaseline(measurements: Measurements) {
        if (abs(smoothedLift - cycleFloorLift) > p.GROUNDED_LIFT) return
        baselineLeftAnkleY += p.BASELINE_ALPHA * (measurements.leftAnkleY - baselineLeftAnkleY)
        baselineRightAnkleY += p.BASELINE_ALPHA * (measurements.rightAnkleY - baselineRightAnkleY)
        baselineAnkleY += p.BASELINE_ALPHA * (measurements.ankleY - baselineAnkleY)
        baselineHipY += p.BASELINE_ALPHA * (measurements.hipY - baselineHipY)
        baselineTorsoLength += p.BASELINE_ALPHA * (measurements.torsoLength - baselineTorsoLength)
    }

    private fun measurements(frame: PoseFrame): Measurements? {
        val leftShoulder = frame[LEFT_SHOULDER] ?: return null
        val rightShoulder = frame[RIGHT_SHOULDER] ?: return null
        val leftHip = frame[LEFT_HIP] ?: return null
        val rightHip = frame[RIGHT_HIP] ?: return null
        val leftKnee = frame[LEFT_KNEE] ?: return null
        val rightKnee = frame[RIGHT_KNEE] ?: return null
        val leftAnkle = frame[LEFT_ANKLE] ?: return null
        val rightAnkle = frame[RIGHT_ANKLE] ?: return null

        val points = listOf(
            leftShoulder,
            rightShoulder,
            leftHip,
            rightHip,
            leftKnee,
            rightKnee,
            leftAnkle,
            rightAnkle,
        )
        val quality = points.map { minOf(it.visibility, it.presence) }.average().toFloat()
        if (quality < p.MIN_AVERAGE_QUALITY || points.any { it.visibility < p.MIN_POINT_VISIBILITY }) {
            return null
        }

        val shoulderX = (leftShoulder.x + rightShoulder.x) / 2f
        val shoulderY = (leftShoulder.y + rightShoulder.y) / 2f
        val hipX = (leftHip.x + rightHip.x) / 2f
        val hipY = (leftHip.y + rightHip.y) / 2f
        val torsoLength = hypot(shoulderX - hipX, shoulderY - hipY)
        if (torsoLength < p.MIN_TORSO_LENGTH) return null

        return Measurements(
            leftAnkleY = leftAnkle.y,
            rightAnkleY = rightAnkle.y,
            ankleY = (leftAnkle.y + rightAnkle.y) / 2f,
            hipY = hipY,
            torsoLength = torsoLength,
            quality = quality,
        )
    }

    private fun result(
        jumpCount: Int,
        quality: Float,
        guidance: String,
        lift: Float,
    ) = JumpDetection(jumpCount > 0, state, quality, guidance, lift, jumpCount)

    private data class Sample(val timestampMs: Long, val measurements: Measurements)

    private data class Measurements(
        val leftAnkleY: Float,
        val rightAnkleY: Float,
        val ankleY: Float,
        val hipY: Float,
        val torsoLength: Float,
        val quality: Float,
    )

    /** Tunable thresholds. Defaults are the production values; the replay harness overrides them. */
    data class Params(
        val REQUIRED_CALIBRATION_SAMPLES: Int = 20,
        val MIN_POINT_VISIBILITY: Float = 0.25f,
        val MIN_AVERAGE_QUALITY: Float = 0.48f,
        val MIN_TORSO_LENGTH: Float = 0.08f,
        val ANKLE_WEIGHT: Float = 0.72f,
        val HIP_WEIGHT: Float = 0.28f,
        val SMOOTHING_ALPHA: Float = 0.52f,
        val BASELINE_ALPHA: Float = 0.025f,
        val CYCLE_FLOOR_ALPHA: Float = 0.18f,
        val MIN_FEET_RISING_VELOCITY: Float = 0.06f,
        val MAX_FEET_VELOCITY_DIFFERENCE: Float = 1.20f,
        val FEET_VELOCITY_DIFFERENCE_RATIO: Float = 0.35f,
        val RISING_LIFT: Float = 0.022f,
        val RISING_VELOCITY: Float = 0.08f,
        val AIRBORNE_LIFT: Float = 0.050f,
        val GROUNDED_LIFT: Float = 0.018f,
        val MIN_RISING_MS: Long = 45L,
        val MAX_RISING_MS: Long = 500L,
        val MIN_RISE_AMPLITUDE: Float = 0.018f,
        val MIN_LANDING_SETTLE_MS: Long = 250L,
        val MAX_SETTLED_VELOCITY: Float = 0.08f,
        val MAX_JUMP_MS: Long = 850L,
        val REFRACTORY_MS: Long = 180L,
        val LOST_RESET_MS: Long = 900L,
        val MIN_SINGLE_FOOT_RISING_VELOCITY: Float = -0.25f,
        val LANDING_VELOCITY: Float = -0.06f,
    ) {
        /**
         * Both feet must rise together. The tolerance grows with the rise speed because landmark
         * jitter scales with motion blur, so a fixed gap would reject the highest, fastest jumps.
         */
        fun feetVelocityTolerance(averageVelocity: Float): Float =
            maxOf(MAX_FEET_VELOCITY_DIFFERENCE, FEET_VELOCITY_DIFFERENCE_RATIO * averageVelocity)
    }

    private companion object {
        const val LEFT_SHOULDER = 11
        const val RIGHT_SHOULDER = 12
        const val LEFT_HIP = 23
        const val RIGHT_HIP = 24
        const val LEFT_KNEE = 25
        const val RIGHT_KNEE = 26
        const val LEFT_ANKLE = 27
        const val RIGHT_ANKLE = 28
    }
}
