package com.yzrun.ropecounter.ui

import android.app.Application
import android.os.SystemClock
import androidx.camera.core.CameraSelector
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.yzrun.ropecounter.counter.JumpDetector
import com.yzrun.ropecounter.counter.WorkoutEngine
import com.yzrun.ropecounter.data.SessionHistoryStore
import com.yzrun.ropecounter.data.WorkoutConfig
import com.yzrun.ropecounter.data.WorkoutMode
import com.yzrun.ropecounter.data.WorkoutPhase
import com.yzrun.ropecounter.data.WorkoutRecord
import com.yzrun.ropecounter.vision.PoseFrame
import com.yzrun.ropecounter.vision.MotionState
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class RopeCounterViewModel(application: Application) : AndroidViewModel(application) {
    private val historyStore = SessionHistoryStore(application)
    private val feedback = FeedbackPlayer(application)
    private val detector = JumpDetector()
    private var engine: WorkoutEngine? = null
    private var sessionStartedAtEpochMs = 0L
    private var sessionSaved = false
    private var lastGuidancePrompt: String? = null
    private var lastGuidancePromptAtMs = Long.MIN_VALUE / 2

    private val _state = MutableStateFlow(
        AppUiState(history = historyStore.load()),
    )
    val state: StateFlow<AppUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            while (isActive) {
                updateClock()
                delay(100)
            }
        }
    }

    fun updateConfig(config: WorkoutConfig) {
        _state.update { it.copy(config = config) }
    }

    fun startWorkout() {
        val now = SystemClock.elapsedRealtime()
        val config = _state.value.config.normalized()
        detector.reset()
        engine = WorkoutEngine(config, now)
        sessionStartedAtEpochMs = System.currentTimeMillis()
        sessionSaved = false
        lastGuidancePrompt = null
        lastGuidancePromptAtMs = Long.MIN_VALUE / 2
        feedback.stopSpeech()
        _state.update {
            it.copy(
                screen = AppScreen.WORKOUT,
                config = config,
                workout = engine?.tick(now),
                poseFrame = null,
                detection = null,
                errorMessage = null,
            )
        }
    }

    fun onPoseFrame(frame: PoseFrame) {
        viewModelScope.launch {
            val currentWorkout = _state.value.workout
            val shouldDetect = currentWorkout?.phase == WorkoutPhase.PREPARING ||
                currentWorkout?.phase == WorkoutPhase.ARMED ||
                currentWorkout?.phase == WorkoutPhase.ACTIVE
            if (!shouldDetect) {
                _state.update { it.copy(poseFrame = frame) }
                return@launch
            }

            val detection = detector.process(frame)
            val now = SystemClock.elapsedRealtime()
            announceGuidance(detection.guidance, now)
            var snapshot = currentWorkout
            if (
                currentWorkout?.phase == WorkoutPhase.PREPARING &&
                detection.state == MotionState.READY
            ) {
                snapshot = engine?.markPoseReady(now)
                feedback.phaseChanged()
            } else if (
                currentWorkout?.phase == WorkoutPhase.ARMED &&
                detection.state in setOf(MotionState.CALIBRATING, MotionState.LOST)
            ) {
                snapshot = engine?.requirePosePreparation(now)
            } else if (
                detection.jumpDetected &&
                (currentWorkout?.phase == WorkoutPhase.ACTIVE || currentWorkout?.phase == WorkoutPhase.ARMED)
            ) {
                // Calibration replay can report more than one jump in a single frame.
                repeat(detection.jumpCount) { snapshot = engine?.recordJump(now) }
                if (currentWorkout.phase == WorkoutPhase.ARMED) feedback.speakStart()
                feedback.jump()
            }
            _state.update {
                it.copy(
                    poseFrame = frame,
                    detection = detection,
                    workout = snapshot,
                )
            }
            maybeSaveCompleted(snapshot)
        }
    }

    fun togglePause() {
        val snapshot = engine?.togglePause(SystemClock.elapsedRealtime()) ?: return
        _state.update { it.copy(workout = snapshot) }
    }

    fun finishWorkout() {
        val snapshot = engine?.finishEarly(SystemClock.elapsedRealtime()) ?: return
        _state.update { it.copy(workout = snapshot) }
        maybeSaveCompleted(snapshot)
    }

    fun returnToSetup() {
        engine = null
        detector.reset()
        feedback.stopSpeech()
        _state.update {
            it.copy(
                screen = AppScreen.SETUP,
                workout = null,
                poseFrame = null,
                detection = null,
                errorMessage = null,
                history = historyStore.load(),
            )
        }
    }

    fun openHistory() {
        _state.update { it.copy(screen = AppScreen.HISTORY, history = historyStore.load()) }
    }

    fun clearHistory() {
        historyStore.clear()
        _state.update { it.copy(history = emptyList()) }
    }

    fun switchCamera() {
        _state.update {
            it.copy(
                lensFacing = if (it.lensFacing == CameraSelector.LENS_FACING_BACK) {
                    CameraSelector.LENS_FACING_FRONT
                } else {
                    CameraSelector.LENS_FACING_BACK
                },
                poseFrame = null,
                detection = null,
            )
        }
        detector.reset()
    }

    fun setReplayDir(dir: String?) {
        _state.update { it.copy(replayDir = dir) }
    }

    fun showError(message: String) {
        _state.update { it.copy(errorMessage = message) }
    }

    fun dismissError() {
        _state.update { it.copy(errorMessage = null) }
    }

    private fun updateClock() {
        val currentEngine = engine ?: return
        val previous = _state.value.workout
        val updated = currentEngine.tick(SystemClock.elapsedRealtime())
        if (previous?.phase != updated.phase) {
            if (updated.phase in setOf(WorkoutPhase.ACTIVE, WorkoutPhase.REST, WorkoutPhase.COMPLETE)) {
                feedback.phaseChanged()
            }
        }
        _state.update { it.copy(workout = updated) }
        maybeSaveCompleted(updated)
    }

    private fun announceGuidance(guidance: String, nowMs: Long) {
        val prompt = when {
            guidance.startsWith("请保持全身入镜") -> "请保持全身入镜"
            guidance.startsWith("请站稳") -> "请站稳"
            else -> null
        } ?: return

        val changed = prompt != lastGuidancePrompt
        val reminderDue = nowMs - lastGuidancePromptAtMs >= GUIDANCE_REMINDER_MS
        if (changed || reminderDue) {
            feedback.speakGuidance(prompt)
            lastGuidancePrompt = prompt
            lastGuidancePromptAtMs = nowMs
        }
    }

    private fun maybeSaveCompleted(snapshot: com.yzrun.ropecounter.data.WorkoutSnapshot?) {
        if (snapshot?.phase != WorkoutPhase.COMPLETE || sessionSaved) return
        sessionSaved = true
        val completedGroups = if (!snapshot.endedEarly) {
            snapshot.config.groups
        } else {
            (snapshot.currentGroup - 1).coerceAtLeast(0)
        }
        historyStore.prepend(
            WorkoutRecord(
                id = sessionStartedAtEpochMs,
                startedAtEpochMs = sessionStartedAtEpochMs,
                mode = snapshot.config.mode,
                totalCount = snapshot.totalCount,
                completedGroups = completedGroups,
                plannedGroups = snapshot.config.groups,
                activeDurationMs = snapshot.totalActiveMs,
                completed = !snapshot.endedEarly || snapshot.config.mode == WorkoutMode.FREE,
            ),
        )
        _state.update { it.copy(history = historyStore.load()) }
    }

    override fun onCleared() {
        feedback.release()
        super.onCleared()
    }

    private companion object {
        const val GUIDANCE_REMINDER_MS = 5_000L
    }
}
