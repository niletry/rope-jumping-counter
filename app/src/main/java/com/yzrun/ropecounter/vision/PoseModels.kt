package com.yzrun.ropecounter.vision

data class PosePoint(
    val x: Float,
    val y: Float,
    val z: Float,
    val visibility: Float,
    val presence: Float,
)

data class PoseFrame(
    val timestampMs: Long,
    val landmarks: List<PosePoint>,
    val imageWidth: Int,
    val imageHeight: Int,
) {
    operator fun get(index: Int): PosePoint? = landmarks.getOrNull(index)
}

enum class MotionState {
    CALIBRATING,
    READY,
    RISING,
    AIRBORNE,
    LANDING,
    LOST,
}

data class JumpDetection(
    val jumpDetected: Boolean,
    val state: MotionState,
    val quality: Float,
    val guidance: String,
    val normalizedLift: Float,
    /** Jumps completed in this frame; can exceed 1 right after calibration replays buffered frames. */
    val jumpCount: Int = if (jumpDetected) 1 else 0,
)
