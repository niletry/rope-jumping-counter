package com.yzrun.ropecounter.vision

/**
 * Notices when the landmarker has silently stopped answering. MediaPipe's live-stream mode does
 * not always report a graph failure through the error listener (a GPU inference error, for
 * instance, only surfaces when the graph is closed), so a frame that stays unanswered for longer
 * than [timeoutMs] is treated as a dead landmarker. Thread-safe.
 */
class InFlightWatchdog(private val timeoutMs: Long) {
    private val lock = Any()
    private var oldestUnansweredMs: Long? = null
    private var unanswered = 0

    fun submitted(nowMs: Long) = synchronized(lock) {
        if (unanswered == 0) oldestUnansweredMs = nowMs
        unanswered++
    }

    fun answered() = synchronized(lock) {
        if (unanswered > 0) unanswered--
        if (unanswered == 0) oldestUnansweredMs = null
    }

    fun reset() = synchronized(lock) {
        unanswered = 0
        oldestUnansweredMs = null
    }

    fun isStalled(nowMs: Long): Boolean = synchronized(lock) {
        val oldest = oldestUnansweredMs ?: return false
        nowMs - oldest > timeoutMs
    }
}
