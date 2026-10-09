package com.yzrun.ropecounter.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Cameraswitch
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yzrun.ropecounter.camera.CameraPoseView
import com.yzrun.ropecounter.camera.ReplayPoseView
import com.yzrun.ropecounter.data.WorkoutMode
import com.yzrun.ropecounter.data.WorkoutPhase
import com.yzrun.ropecounter.data.WorkoutSnapshot
import com.yzrun.ropecounter.vision.PoseFrame

@Composable
fun WorkoutScreen(
    state: AppUiState,
    onPoseFrame: (PoseFrame) -> Unit,
    onSwitchCamera: () -> Unit,
    onTogglePause: () -> Unit,
    onFinish: () -> Unit,
    onDone: () -> Unit,
    onError: (String) -> Unit,
) {
    val workout = state.workout ?: return
    var showEndDialog by remember { mutableStateOf(false) }
    BackHandler(enabled = workout.phase != WorkoutPhase.COMPLETE) { showEndDialog = true }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        val analyzeFrames = workout.phase != WorkoutPhase.COMPLETE &&
            workout.phase != WorkoutPhase.PAUSED &&
            workout.phase != WorkoutPhase.REST
        if (state.replayDir != null) {
            ReplayPoseView(
                replayDir = state.replayDir,
                analyzeFrames = analyzeFrames,
                poseFrame = state.poseFrame,
                onPoseFrame = onPoseFrame,
                onError = onError,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            CameraPoseView(
                lensFacing = state.lensFacing,
                analyzeFrames = analyzeFrames,
                poseFrame = state.poseFrame,
                onPoseFrame = onPoseFrame,
                onError = onError,
                modifier = Modifier.fillMaxSize(),
            )
        }

        Text(
            text = workout.totalCount.toString(),
            modifier = Modifier
                .align(Alignment.TopEnd)
                .statusBarsPadding()
                .padding(top = 10.dp, end = 20.dp),
            color = MaterialTheme.colorScheme.primary,
            fontSize = 72.sp,
            lineHeight = 76.sp,
            fontWeight = FontWeight.Black,
            style = TextStyle(
                shadow = Shadow(
                    color = Color.Black.copy(alpha = 0.85f),
                    offset = Offset(0f, 3f),
                    blurRadius = 10f,
                ),
            ),
        )

        MinimalBottomControls(
            workout = workout,
            guidance = state.detection?.guidance,
            onSwitchCamera = onSwitchCamera,
            onTogglePause = onTogglePause,
            onEnd = { showEndDialog = true },
            modifier = Modifier.align(Alignment.BottomCenter),
        )

        if (workout.phase == WorkoutPhase.COMPLETE) {
            Box(Modifier.align(Alignment.Center)) {
                CompletionCard(workout, onDone)
            }
        }
    }

    if (showEndDialog) {
        AlertDialog(
            onDismissRequest = { showEndDialog = false },
            title = { Text("结束本次训练？") },
            text = { Text("当前计数和训练时长会保存到本地记录。") },
            confirmButton = {
                TextButton(
                    onClick = {
                        showEndDialog = false
                        onFinish()
                    },
                ) { Text("结束") }
            },
            dismissButton = {
                TextButton(onClick = { showEndDialog = false }) { Text("继续") }
            },
        )
    }
}

@Composable
private fun MinimalBottomControls(
    workout: WorkoutSnapshot,
    guidance: String?,
    onSwitchCamera: () -> Unit,
    onTogglePause: () -> Unit,
    onEnd: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (workout.phase == WorkoutPhase.COMPLETE) return

    Column(
        modifier = modifier
            .navigationBarsPadding()
            .padding(12.dp)
            .fillMaxWidth()
            .background(Color.Black.copy(alpha = 0.58f), RoundedCornerShape(18.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    text = statusText(workout, guidance),
                    color = if (
                        workout.phase == WorkoutPhase.ACTIVE &&
                        statusText(workout, guidance) == "计数中"
                    ) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        Color.White
                    },
                    fontWeight = FontWeight.SemiBold,
                    style = MaterialTheme.typography.bodyMedium,
                )
                Text(
                    text = detailText(workout),
                    color = Color.White.copy(alpha = 0.68f),
                    style = MaterialTheme.typography.labelSmall,
                )
            }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                FilledTonalIconButton(onClick = onSwitchCamera, modifier = Modifier.size(42.dp)) {
                    Icon(Icons.Rounded.Cameraswitch, contentDescription = "切换摄像头")
                }
                FilledTonalIconButton(
                    onClick = onTogglePause,
                    enabled = workout.phase != WorkoutPhase.PREPARING,
                    modifier = Modifier.size(42.dp),
                ) {
                    Icon(
                        if (workout.phase == WorkoutPhase.PAUSED) {
                            Icons.Rounded.PlayArrow
                        } else {
                            Icons.Rounded.Pause
                        },
                        contentDescription = if (workout.phase == WorkoutPhase.PAUSED) "继续" else "暂停",
                    )
                }
                FilledTonalIconButton(onClick = onEnd, modifier = Modifier.size(42.dp)) {
                    Icon(Icons.Rounded.Close, contentDescription = "结束训练")
                }
            }
        }

        val progress = progress(workout)
        if (progress != null) {
            Spacer(Modifier.height(8.dp))
            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth().height(3.dp),
            )
        }
    }
}

private fun statusText(workout: WorkoutSnapshot, guidance: String?): String = when (workout.phase) {
    WorkoutPhase.PREPARING -> guidance ?: "请全身入镜并站稳"
    WorkoutPhase.ARMED -> "跳起来就开始计数"
    WorkoutPhase.ACTIVE -> guidance?.takeIf { it.startsWith("请") } ?: "计数中"
    WorkoutPhase.REST -> "休息 ${workout.phaseRemainingSec ?: 0} 秒"
    WorkoutPhase.PAUSED -> "已暂停"
    WorkoutPhase.COMPLETE -> "训练完成"
}

private fun detailText(workout: WorkoutSnapshot): String {
    val group = if (workout.config.mode == WorkoutMode.FREE) {
        ""
    } else {
        "第 ${workout.currentGroup}/${workout.config.groups} 组 · "
    }
    val target = when (workout.config.mode) {
        WorkoutMode.FIXED_COUNT -> "本组 ${workout.groupCount}/${workout.config.targetCountPerGroup} · "
        WorkoutMode.FIXED_TIME -> {
            val activelyTiming = workout.phase == WorkoutPhase.ACTIVE ||
                (workout.phase == WorkoutPhase.PAUSED && workout.pausedFrom == WorkoutPhase.ACTIVE)
            val remaining = if (activelyTiming) {
                workout.phaseRemainingSec ?: workout.config.durationPerGroupSec
            } else {
                workout.config.durationPerGroupSec
            }
            "本组剩余 $remaining 秒 · "
        }
        WorkoutMode.FREE -> ""
    }
    return "$group$target${formatClock(workout.totalActiveMs)}"
}

private fun progress(workout: WorkoutSnapshot): Float? = when (workout.config.mode) {
    WorkoutMode.FIXED_COUNT -> workout.groupCount.toFloat() / workout.config.targetCountPerGroup
    WorkoutMode.FIXED_TIME -> workout.groupElapsedMs.toFloat() / (workout.config.durationPerGroupSec * 1_000f)
    WorkoutMode.FREE -> null
}?.coerceIn(0f, 1f)

@Composable
private fun CompletionCard(workout: WorkoutSnapshot, onDone: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(28.dp)
            .background(MaterialTheme.colorScheme.surface, RoundedCornerShape(28.dp))
            .padding(28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            if (workout.endedEarly) "训练已结束" else "训练完成",
            fontSize = 26.sp,
            fontWeight = FontWeight.Bold,
        )
        Spacer(Modifier.height(14.dp))
        Text(
            workout.totalCount.toString(),
            color = MaterialTheme.colorScheme.primary,
            fontSize = 60.sp,
            fontWeight = FontWeight.Black,
        )
        Text("累计次数 · ${formatClock(workout.totalActiveMs)}")
        Spacer(Modifier.height(22.dp))
        Button(onClick = onDone, modifier = Modifier.fillMaxWidth()) { Text("完成") }
    }
}

fun formatClock(milliseconds: Long): String {
    val totalSeconds = (milliseconds / 1_000L).coerceAtLeast(0L)
    val hours = totalSeconds / 3_600
    val minutes = (totalSeconds % 3_600) / 60
    val seconds = totalSeconds % 60
    return if (hours > 0) {
        "%d:%02d:%02d".format(hours, minutes, seconds)
    } else {
        "%02d:%02d".format(minutes, seconds)
    }
}
