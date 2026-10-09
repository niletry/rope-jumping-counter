package com.yzrun.ropecounter.counter

import com.yzrun.ropecounter.vision.PoseFrame
import com.yzrun.ropecounter.vision.PosePoint
import com.yzrun.ropecounter.vision.MotionState
import org.junit.Assert.assertEquals
import org.junit.Test

class JumpDetectorTest {
    @Test
    fun oneTakeoffAndLanding_countsExactlyOnce() {
        val detector = JumpDetector()
        var timestamp = 0L
        repeat(28) {
            detector.process(frame(timestamp, 0f))
            timestamp += 33
        }

        var jumps = 0
        val verticalOffsets = listOf(
            0.005f,
            0.015f,
            0.030f,
            0.045f,
            0.050f,
            0.045f,
            0.030f,
            0.015f,
            0.004f,
            0f,
            0f,
            0f,
            0f,
            0f,
        )
        verticalOffsets.forEach { offset ->
            if (detector.process(frame(timestamp, offset)).jumpDetected) jumps += 1
            timestamp += 33
        }

        assertEquals(1, jumps)
    }

    @Test
    fun smallBodySway_isIgnored() {
        val detector = JumpDetector()
        var timestamp = 0L
        repeat(28) {
            detector.process(frame(timestamp, 0f))
            timestamp += 33
        }

        var jumps = 0
        repeat(60) { index ->
            val offset = if (index % 2 == 0) 0.003f else -0.003f
            if (detector.process(frame(timestamp, offset)).jumpDetected) jumps += 1
            timestamp += 33
        }

        assertEquals(0, jumps)
    }

    @Test
    fun missingPose_clearsTrackingAndRequestsRecalibration() {
        val detector = JumpDetector()
        var timestamp = 0L
        repeat(28) {
            detector.process(frame(timestamp, 0f))
            timestamp += 33
        }

        var result = detector.process(PoseFrame(timestamp, emptyList(), 540, 960))
        repeat(32) {
            timestamp += 33
            result = detector.process(PoseFrame(timestamp, emptyList(), 540, 960))
        }

        assertEquals(MotionState.LOST, result.state)
    }

    @Test
    fun walkingTowardCamera_doesNotCount() {
        val detector = JumpDetector()
        var timestamp = 0L
        repeat(24) {
            detector.process(frame(timestamp, 0f))
            timestamp += 33
        }

        var jumps = 0
        listOf(1.05f, 1.10f, 1.16f, 1.22f, 1.28f).forEach { scale ->
            if (detector.process(frame(timestamp, 0f, scale)).jumpDetected) jumps += 1
            timestamp += 33
        }

        assertEquals(0, jumps)
    }

    @Test
    fun repeatedFastJumps_countWithoutReturningToOriginalGroundLine() {
        val detector = JumpDetector()
        var timestamp = 0L
        repeat(24) {
            detector.process(frame(timestamp, 0f))
            timestamp += 33
        }

        var jumps = 0
        repeat(5) {
            listOf(
                0.015f,
                0.025f,
                0.042f,
                0.055f,
                0.048f,
                0.032f,
                0.020f,
                0.016f,
                0.015f,
            ).forEach { offset ->
                if (detector.process(frame(timestamp, offset)).jumpDetected) jumps += 1
                timestamp += 33
            }
        }

        assertEquals(5, jumps)
    }

    @Test
    fun repeatedJumps_withAProgressivelyShiftedGroundLine_keepCounting() {
        val detector = JumpDetector()
        var timestamp = 0L
        repeat(24) {
            detector.process(frame(timestamp, 0f))
            timestamp += 33
        }

        var jumps = 0
        repeat(7) { jumpIndex ->
            val floor = jumpIndex * 0.009f
            listOf(
                floor,
                floor + 0.008f,
                floor + 0.020f,
                floor + 0.036f,
                floor + 0.050f,
                floor + 0.042f,
                floor + 0.026f,
                floor + 0.010f,
                floor,
            ).forEach { offset ->
                if (detector.process(frame(timestamp, offset)).jumpDetected) jumps += 1
                timestamp += 33
            }
        }

        assertEquals(7, jumps)
    }

    @Test
    fun largeLandingPositionChanges_doNotInterruptCounting() {
        val detector = JumpDetector()
        var timestamp = 0L
        repeat(24) {
            detector.process(frame(timestamp, 0f))
            timestamp += 33
        }

        val landingPositions = listOf(
            Triple(-0.18f, 0.00f, 0.82f),
            Triple(0.16f, 0.025f, 1.18f),
            Triple(-0.22f, -0.030f, 1.35f),
            Triple(0.20f, 0.045f, 0.88f),
            Triple(-0.12f, -0.020f, 1.25f),
            Triple(0.10f, 0.030f, 0.95f),
        )
        var jumps = 0
        landingPositions.forEach { (horizontalShift, groundShift, scale) ->
            repeat(4) {
                detector.process(
                    frame(timestamp, groundShift, scale, horizontalShift),
                )
                timestamp += 33
            }
            listOf(0.008f, 0.022f, 0.042f, 0.060f, 0.050f, 0.030f, 0.012f, 0f)
                .forEach { jumpLift ->
                    if (
                        detector.process(
                            frame(timestamp, groundShift + jumpLift, scale, horizontalShift),
                        ).jumpDetected
                    ) {
                        jumps += 1
                    }
                    timestamp += 33
                }
        }

        assertEquals(landingPositions.size, jumps)
    }

    @Test
    fun alreadyJumpingAtStart_startsCountingWithoutStandingStill() {
        val detector = JumpDetector()
        var timestamp = 0L
        val cycle = listOf(0f, 0.012f, 0.030f, 0.048f, 0.055f, 0.045f, 0.025f, 0.008f, 0f, 0f)
        var jumps = 0
        repeat(10) {
            cycle.forEach { offset ->
                // Hand-held camera: add a slow drift to every landmark.
                val drift = 0.004f * (timestamp / 33 % 7)
                if (detector.process(frame(timestamp, offset, horizontalShift = drift)).jumpDetected) jumps += 1
                timestamp += 33
            }
        }

        // The first cycles are consumed by calibration; every later cycle must be counted.
        assert(jumps >= 7) { "expected at least 7 jumps, got $jumps" }
    }

    @Test
    fun jumpDuringCalibrationWindow_isCountedAfterReplay() {
        val detector = JumpDetector()
        var timestamp = 0L
        val cycle = listOf(0f, 0.012f, 0.030f, 0.048f, 0.055f, 0.045f, 0.025f, 0.008f, 0f, 0f)
        var jumps = 0
        // Three jumps starting at frame 0. The first one completes inside the 20-frame
        // calibration window and must be recovered when the window is replayed.
        repeat(3) {
            cycle.forEach { offset ->
                jumps += detector.process(frame(timestamp, offset)).jumpCount
                timestamp += 33
            }
        }
        assertEquals(3, jumps)
    }

    private fun frame(
        timestampMs: Long,
        shiftUp: Float,
        scale: Float = 1f,
        horizontalShift: Float = 0f,
    ): PoseFrame {
        val points = MutableList(33) { PosePoint(0.5f, 0.5f, 0f, 1f, 1f) }
        points[11] = PosePoint(0.42f + horizontalShift, 0.55f - 0.25f * scale - shiftUp, 0f, 1f, 1f)
        points[12] = PosePoint(0.58f + horizontalShift, 0.55f - 0.25f * scale - shiftUp, 0f, 1f, 1f)
        points[23] = PosePoint(0.45f + horizontalShift, 0.55f - shiftUp, 0f, 1f, 1f)
        points[24] = PosePoint(0.55f + horizontalShift, 0.55f - shiftUp, 0f, 1f, 1f)
        points[25] = PosePoint(0.46f + horizontalShift, 0.55f + 0.17f * scale - shiftUp, 0f, 1f, 1f)
        points[26] = PosePoint(0.54f + horizontalShift, 0.55f + 0.17f * scale - shiftUp, 0f, 1f, 1f)
        points[27] = PosePoint(0.46f + horizontalShift, 0.55f + 0.35f * scale - shiftUp, 0f, 1f, 1f)
        points[28] = PosePoint(0.54f + horizontalShift, 0.55f + 0.35f * scale - shiftUp, 0f, 1f, 1f)
        return PoseFrame(timestampMs, points, 540, 960)
    }
}
