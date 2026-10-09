package com.yzrun.ropecounter.counter

import com.yzrun.ropecounter.data.WorkoutConfig
import com.yzrun.ropecounter.data.WorkoutMode
import com.yzrun.ropecounter.data.WorkoutPhase
import com.yzrun.ropecounter.data.WorkoutSnapshot
import kotlin.math.ceil

class WorkoutEngine(
    config: WorkoutConfig,
    startedAtMs: Long,
) {
    private val config = config.normalized()
    private var phase = WorkoutPhase.PREPARING
    private var phaseStartMs = startedAtMs
    private var pausedAtMs = 0L
    private var pausedFrom: WorkoutPhase? = null
    private var activeBeforeCurrentPhaseMs = 0L
    private var currentGroup = 1
    private var totalCount = 0
    private var groupCount = 0
    private var endedEarly = false

    fun tick(nowMs: Long): WorkoutSnapshot {
        when (phase) {
            WorkoutPhase.PREPARING -> Unit

            // ARMED has no timer: the group starts on the first jump (see recordJump).
            WorkoutPhase.ARMED -> Unit

            WorkoutPhase.ACTIVE -> {
                if (
                    config.mode == WorkoutMode.FIXED_TIME &&
                    nowMs - phaseStartMs >= config.durationPerGroupSec * 1_000L
                ) {
                    finishGroup(nowMs)
                }
            }

            WorkoutPhase.REST -> {
                if (nowMs - phaseStartMs >= config.restSec * 1_000L) {
                    phase = WorkoutPhase.ARMED
                    phaseStartMs = nowMs
                }
            }

            WorkoutPhase.PAUSED,
            WorkoutPhase.COMPLETE,
            -> Unit
        }
        return snapshot(nowMs)
    }

    fun markPoseReady(nowMs: Long): WorkoutSnapshot {
        if (phase == WorkoutPhase.PREPARING) {
            phase = WorkoutPhase.ARMED
            phaseStartMs = nowMs
        }
        return snapshot(nowMs)
    }

    fun requirePosePreparation(nowMs: Long): WorkoutSnapshot {
        if (phase == WorkoutPhase.ARMED) {
            phase = WorkoutPhase.PREPARING
            phaseStartMs = nowMs
        }
        return snapshot(nowMs)
    }

    fun recordJump(nowMs: Long): WorkoutSnapshot {
        tick(nowMs)
        if (phase == WorkoutPhase.ARMED) {
            // The first jump starts the clock and is itself counted.
            phase = WorkoutPhase.ACTIVE
            phaseStartMs = nowMs
        }
        if (phase != WorkoutPhase.ACTIVE) return snapshot(nowMs)

        totalCount += 1
        groupCount += 1
        if (
            config.mode == WorkoutMode.FIXED_COUNT &&
            groupCount >= config.targetCountPerGroup
        ) {
            finishGroup(nowMs)
        }
        return snapshot(nowMs)
    }

    fun togglePause(nowMs: Long): WorkoutSnapshot {
        if (phase == WorkoutPhase.PAUSED) {
            val restored = pausedFrom ?: WorkoutPhase.ARMED
            phaseStartMs += (nowMs - pausedAtMs).coerceAtLeast(0L)
            phase = restored
            pausedFrom = null
        } else if (phase != WorkoutPhase.COMPLETE) {
            pausedFrom = phase
            pausedAtMs = nowMs
            phase = WorkoutPhase.PAUSED
        }
        return snapshot(nowMs)
    }

    fun finishEarly(nowMs: Long): WorkoutSnapshot {
        if (phase != WorkoutPhase.COMPLETE) {
            val effectivePhase = if (phase == WorkoutPhase.PAUSED) pausedFrom else phase
            val effectiveNow = if (phase == WorkoutPhase.PAUSED) pausedAtMs else nowMs
            if (effectivePhase == WorkoutPhase.ACTIVE) {
                activeBeforeCurrentPhaseMs += (effectiveNow - phaseStartMs).coerceAtLeast(0L)
            }
            phase = WorkoutPhase.COMPLETE
            phaseStartMs = nowMs
            endedEarly = true
            pausedFrom = null
        }
        return snapshot(nowMs)
    }

    private fun finishGroup(nowMs: Long) {
        activeBeforeCurrentPhaseMs += (nowMs - phaseStartMs).coerceAtLeast(0L)
        if (currentGroup >= config.groups || config.mode == WorkoutMode.FREE) {
            phase = WorkoutPhase.COMPLETE
            phaseStartMs = nowMs
            return
        }

        currentGroup += 1
        groupCount = 0
        phase = if (config.restSec == 0) WorkoutPhase.ARMED else WorkoutPhase.REST
        phaseStartMs = nowMs
    }

    private fun snapshot(nowMs: Long): WorkoutSnapshot {
        val referenceNow = if (phase == WorkoutPhase.PAUSED) pausedAtMs else nowMs
        val effectivePhase = if (phase == WorkoutPhase.PAUSED) pausedFrom else phase
        val groupElapsed = if (effectivePhase == WorkoutPhase.ACTIVE) {
            (referenceNow - phaseStartMs).coerceAtLeast(0L)
        } else {
            0L
        }
        val totalActive = activeBeforeCurrentPhaseMs + groupElapsed

        val remainingSec = when (effectivePhase) {
            WorkoutPhase.REST -> remainingSeconds(
                config.restSec * 1_000L - (referenceNow - phaseStartMs),
            )

            WorkoutPhase.ACTIVE -> if (config.mode == WorkoutMode.FIXED_TIME) {
                remainingSeconds(config.durationPerGroupSec * 1_000L - groupElapsed)
            } else {
                null
            }

            WorkoutPhase.PREPARING,
            WorkoutPhase.ARMED,
            WorkoutPhase.PAUSED,
            WorkoutPhase.COMPLETE,
            null,
            -> null
        }

        return WorkoutSnapshot(
            config = config,
            phase = phase,
            currentGroup = currentGroup,
            totalCount = totalCount,
            groupCount = groupCount,
            totalActiveMs = totalActive,
            groupElapsedMs = groupElapsed,
            phaseRemainingSec = remainingSec,
            pausedFrom = pausedFrom,
            endedEarly = endedEarly,
        )
    }

    private fun remainingSeconds(milliseconds: Long): Int =
        ceil(milliseconds.coerceAtLeast(0L) / 1_000.0).toInt()
}
