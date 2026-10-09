package com.yzrun.ropecounter.data

enum class WorkoutMode(val title: String, val subtitle: String) {
    FIXED_COUNT("定数跳", "每组完成指定次数"),
    FIXED_TIME("定时跳", "每组持续指定时间"),
    FREE("自由跳绳", "持续到主动结束"),
}

data class WorkoutConfig(
    val mode: WorkoutMode = WorkoutMode.FIXED_COUNT,
    val targetCountPerGroup: Int = 100,
    val durationPerGroupSec: Int = 60,
    val groups: Int = 3,
    val restSec: Int = 60,
) {
    fun normalized(): WorkoutConfig = copy(
        targetCountPerGroup = targetCountPerGroup.coerceIn(1, 9_999),
        durationPerGroupSec = durationPerGroupSec.coerceIn(5, 3_600),
        groups = if (mode == WorkoutMode.FREE) 1 else groups.coerceIn(1, 99),
        restSec = if (mode == WorkoutMode.FREE) 0 else restSec.coerceIn(0, 1_800),
    )
}

enum class WorkoutPhase {
    PREPARING,
    /** Calibrated; timing and counting start with the first detected jump. */
    ARMED,
    ACTIVE,
    REST,
    PAUSED,
    COMPLETE,
}

data class WorkoutSnapshot(
    val config: WorkoutConfig,
    val phase: WorkoutPhase,
    val currentGroup: Int,
    val totalCount: Int,
    val groupCount: Int,
    val totalActiveMs: Long,
    val groupElapsedMs: Long,
    val phaseRemainingSec: Int?,
    val pausedFrom: WorkoutPhase? = null,
    val endedEarly: Boolean = false,
)

data class WorkoutRecord(
    val id: Long,
    val startedAtEpochMs: Long,
    val mode: WorkoutMode,
    val totalCount: Int,
    val completedGroups: Int,
    val plannedGroups: Int,
    val activeDurationMs: Long,
    val completed: Boolean,
)
