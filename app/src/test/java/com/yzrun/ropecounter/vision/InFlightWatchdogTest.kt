package com.yzrun.ropecounter.vision

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class InFlightWatchdogTest {
    private val watchdog = InFlightWatchdog(timeoutMs = 3_000)

    @Test
    fun `idle watchdog is never stalled`() {
        assertFalse(watchdog.isStalled(nowMs = 100_000))
    }

    @Test
    fun `a frame answered within the timeout is not a stall`() {
        watchdog.submitted(nowMs = 1_000)
        watchdog.answered()
        assertFalse(watchdog.isStalled(nowMs = 10_000))
    }

    @Test
    fun `a frame still unanswered after the timeout is a stall`() {
        watchdog.submitted(nowMs = 1_000)
        assertFalse(watchdog.isStalled(nowMs = 3_999))
        assertTrue(watchdog.isStalled(nowMs = 4_001))
    }

    @Test
    fun `the oldest unanswered frame decides the stall, not the newest`() {
        watchdog.submitted(nowMs = 1_000)
        watchdog.submitted(nowMs = 3_900)
        assertTrue(watchdog.isStalled(nowMs = 4_100))
    }

    @Test
    fun `reset forgets everything in flight`() {
        watchdog.submitted(nowMs = 1_000)
        watchdog.reset()
        assertFalse(watchdog.isStalled(nowMs = 100_000))
    }
}
