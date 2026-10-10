package com.yzrun.ropecounter.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.TextButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Switch
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.Remove
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yzrun.ropecounter.data.WorkoutConfig
import com.yzrun.ropecounter.data.WorkoutMode

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SetupScreen(
    config: WorkoutConfig,
    historyCount: Int,
    onConfigChange: (WorkoutConfig) -> Unit,
    onStart: () -> Unit,
    onHistory: () -> Unit,
    customVoices: Set<VoicePrompt> = emptySet(),
    recording: VoicePrompt? = null,
    onStartRecording: (VoicePrompt) -> Unit = {},
    onStopRecording: () -> Unit = {},
    onResetVoice: (VoicePrompt) -> Unit = {},
    onPreviewVoice: (VoicePrompt) -> Unit = {},
    countBeepEnabled: Boolean = false,
    onCountBeepChange: (Boolean) -> Unit = {},
    showPreview: Boolean = true,
    onShowPreviewChange: (Boolean) -> Unit = {},
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Column {
                        Text("智能跳绳", fontWeight = FontWeight.Bold)
                        Text(
                            "离线 AI 自动计数",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
                actions = {
                    IconButton(onClick = onHistory) {
                        Icon(Icons.Outlined.History, contentDescription = "训练历史")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                ),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 12.dp),
        ) {
            Text("选择训练模式", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(12.dp))
            WorkoutMode.entries.forEach { mode ->
                ModeCard(
                    mode = mode,
                    selected = config.mode == mode,
                    onClick = { onConfigChange(config.copy(mode = mode)) },
                )
                Spacer(Modifier.height(10.dp))
            }

            if (config.mode != WorkoutMode.FREE) {
                Spacer(Modifier.height(8.dp))
                Text("训练设置", style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(10.dp))
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                    Column(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                        if (config.mode == WorkoutMode.FIXED_COUNT) {
                            NumberStepper(
                                label = "每组次数",
                                value = config.targetCountPerGroup,
                                valueText = "${config.targetCountPerGroup} 次",
                                step = 10,
                                range = 10..9_999,
                                onChange = { onConfigChange(config.copy(targetCountPerGroup = it)) },
                            )
                        } else {
                            NumberStepper(
                                label = "每组时长",
                                value = config.durationPerGroupSec,
                                valueText = formatShortDuration(config.durationPerGroupSec),
                                step = 15,
                                range = 15..3_600,
                                onChange = { onConfigChange(config.copy(durationPerGroupSec = it)) },
                            )
                        }
                        NumberStepper(
                            label = "训练组数",
                            value = config.groups,
                            valueText = "${config.groups} 组",
                            step = 1,
                            range = 1..99,
                            onChange = { onConfigChange(config.copy(groups = it)) },
                        )
                        NumberStepper(
                            label = "组间休息",
                            value = config.restSec,
                            valueText = formatShortDuration(config.restSec),
                            step = 15,
                            range = 0..1_800,
                            onChange = { onConfigChange(config.copy(restSec = it)) },
                        )
                    }
                }
            }

            Spacer(Modifier.height(18.dp))
            Text("语音鼓励", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(10.dp))
            VoicePromptCard(
                customVoices = customVoices,
                recording = recording,
                onStartRecording = onStartRecording,
                onStopRecording = onStopRecording,
                onResetVoice = onResetVoice,
                onPreviewVoice = onPreviewVoice,
                countBeepEnabled = countBeepEnabled,
                onCountBeepChange = onCountBeepChange,
                showPreview = showPreview,
                onShowPreviewChange = onShowPreviewChange,
            )

            Spacer(Modifier.height(18.dp))
            Card(
                colors = CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f),
                ),
            ) {
                Column(Modifier.padding(16.dp)) {
                    Text("拍摄提示", fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(6.dp))
                    Text(
                        "固定手机并让全身进入画面，直接开跳即可，从第一跳开始计时计数。视频只在设备上实时处理，不会保存或上传。",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            Spacer(Modifier.height(22.dp))
            Button(
                onClick = onStart,
                modifier = Modifier.fillMaxWidth().height(56.dp),
            ) {
                Text("开始训练", fontSize = 17.sp, fontWeight = FontWeight.Bold)
            }
            if (historyCount > 0) {
                Text(
                    "已保存 $historyCount 次本地训练记录",
                    modifier = Modifier.align(Alignment.CenterHorizontally).padding(top = 10.dp),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun VoicePromptCard(
    customVoices: Set<VoicePrompt>,
    recording: VoicePrompt?,
    onStartRecording: (VoicePrompt) -> Unit,
    onStopRecording: () -> Unit,
    onResetVoice: (VoicePrompt) -> Unit,
    onPreviewVoice: (VoicePrompt) -> Unit,
    countBeepEnabled: Boolean,
    onCountBeepChange: (Boolean) -> Unit,
    showPreview: Boolean,
    onShowPreviewChange: (Boolean) -> Unit,
) {
    val context = LocalContext.current
    var pendingPrompt by remember { mutableStateOf<VoicePrompt?>(null) }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted ->
        val prompt = pendingPrompt
        pendingPrompt = null
        if (granted && prompt != null) onStartRecording(prompt)
    }

    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
        Column(Modifier.padding(horizontal = 16.dp, vertical = 10.dp)) {
            Text(
                "可以录一句自己的话代替默认提示音，最长 3 秒。",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            VoicePrompt.entries.forEach { prompt ->
                val isRecording = recording == prompt
                val isCustom = prompt in customVoices
                Row(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(prompt.label, fontWeight = FontWeight.Medium)
                        Text(
                            when {
                                isRecording -> "录音中…"
                                isCustom -> "已使用你的录音"
                                else -> prompt.hint
                            },
                            style = MaterialTheme.typography.labelSmall,
                            color = if (isRecording) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    TextButton(onClick = { onPreviewVoice(prompt) }, enabled = recording == null) { Text("试听") }
                    if (isCustom && !isRecording) {
                        TextButton(onClick = { onResetVoice(prompt) }, enabled = recording == null) { Text("恢复默认") }
                    }
                    Button(
                        onClick = {
                            if (isRecording) {
                                onStopRecording()
                            } else if (
                                ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) ==
                                PackageManager.PERMISSION_GRANTED
                            ) {
                                onStartRecording(prompt)
                            } else {
                                pendingPrompt = prompt
                                permissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                            }
                        },
                        enabled = recording == null || isRecording,
                    ) {
                        Text(if (isRecording) "停止" else "录音")
                    }
                }
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("每次计数“嘀”一声", fontWeight = FontWeight.Medium)
                    Text(
                        "关闭后只保留语音鼓励",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(checked = countBeepEnabled, onCheckedChange = onCountBeepChange)
            }
            HorizontalDivider(Modifier.padding(vertical = 4.dp))
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("显示摄像头画面", fontWeight = FontWeight.Medium)
                    Text(
                        "关闭后只显示骨架，训练中也可随时切换",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(checked = showPreview, onCheckedChange = onShowPreviewChange)
            }
        }
    }
}

@Composable
private fun ModeCard(mode: WorkoutMode, selected: Boolean, onClick: () -> Unit) {
    OutlinedCard(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
        border = BorderStroke(
            if (selected) 2.dp else 1.dp,
            if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
        ),
        colors = CardDefaults.outlinedCardColors(
            containerColor = if (selected) {
                MaterialTheme.colorScheme.primary.copy(alpha = 0.10f)
            } else {
                Color.Transparent
            },
        ),
    ) {
        Column(Modifier.padding(16.dp)) {
            Text(mode.title, fontWeight = FontWeight.Bold, fontSize = 17.sp)
            Spacer(Modifier.height(3.dp))
            Text(
                mode.subtitle,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
    }
}

@Composable
private fun NumberStepper(
    label: String,
    value: Int,
    valueText: String,
    step: Int,
    range: IntRange,
    onChange: (Int) -> Unit,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, modifier = Modifier.weight(1f))
        IconButton(onClick = { onChange((value - step).coerceAtLeast(range.first)) }) {
            Icon(Icons.Rounded.Remove, contentDescription = "减少$label")
        }
        Text(
            valueText,
            modifier = Modifier.width(78.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            fontWeight = FontWeight.SemiBold,
        )
        IconButton(onClick = { onChange((value + step).coerceAtMost(range.last)) }) {
            Icon(Icons.Rounded.Add, contentDescription = "增加$label")
        }
    }
}

fun formatShortDuration(seconds: Int): String = when {
    seconds < 60 -> "${seconds} 秒"
    seconds % 60 == 0 -> "${seconds / 60} 分钟"
    else -> "${seconds / 60}分${seconds % 60}秒"
}
