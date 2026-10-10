package com.yzrun.ropecounter.ui

import androidx.camera.core.CameraSelector
import com.yzrun.ropecounter.data.WorkoutConfig
import com.yzrun.ropecounter.data.WorkoutRecord
import com.yzrun.ropecounter.data.WorkoutSnapshot
import com.yzrun.ropecounter.vision.JumpDetection
import com.yzrun.ropecounter.vision.PoseFrame

enum class AppScreen {
    SETUP,
    WORKOUT,
    HISTORY,
}

data class AppUiState(
    val screen: AppScreen = AppScreen.SETUP,
    val config: WorkoutConfig = WorkoutConfig(),
    val workout: WorkoutSnapshot? = null,
    val poseFrame: PoseFrame? = null,
    val detection: JumpDetection? = null,
    val lensFacing: Int = CameraSelector.LENS_FACING_FRONT,
    val errorMessage: String? = null,
    val history: List<WorkoutRecord> = emptyList(),
    val replayDir: String? = null,
    val customVoices: Set<VoicePrompt> = emptySet(),
    val recording: VoicePrompt? = null,
    val countBeepEnabled: Boolean = false,
    /** Draw the camera picture behind the skeleton; off shows the skeleton alone on black. */
    val showPreview: Boolean = true,
)
