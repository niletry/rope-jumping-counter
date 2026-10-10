package com.yzrun.ropecounter.camera

import android.graphics.BitmapFactory
import android.os.SystemClock
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.yzrun.ropecounter.vision.PoseFrame
import com.yzrun.ropecounter.vision.PoseLandmarkerProcessor
import java.io.File
import org.json.JSONArray
import org.json.JSONObject
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext

/**
 * Debug-only替代 CameraPoseView：按固定帧率回放一个目录里的 JPEG/PNG 帧序列，
 * 并把每一帧送进同一套 MediaPipe 姿态识别管线。用于在模拟器上用录制视频回归计数算法。
 * 启动方式：adb shell am start -n com.yzrun.ropecounter/.MainActivity --es replay_dir <目录>
 */
@Composable
fun ReplayPoseView(
    replayDir: String,
    analyzeFrames: Boolean,
    poseFrame: PoseFrame?,
    onPoseFrame: (PoseFrame) -> Unit,
    onError: (String) -> Unit,
    modifier: Modifier = Modifier,
    showPreview: Boolean = true,
) {
    val context = LocalContext.current
    val currentOnPoseFrame by rememberUpdatedState(onPoseFrame)
    val currentOnError by rememberUpdatedState(onError)
    val currentAnalyzeFrames by rememberUpdatedState(analyzeFrames)
    var currentBitmap by remember { mutableStateOf<ImageBitmap?>(null) }
    var progressText by remember { mutableStateOf("") }
    val dumpFile = remember { File(context.filesDir, "replay_landmarks.jsonl").also { it.delete() } }
    val processor = remember {
        runCatching {
            PoseLandmarkerProcessor(
                context = context.applicationContext,
                onResult = { frame ->
                    runCatching {
                        val obj = JSONObject()
                            .put("t", frame.timestampMs)
                            .put("w", frame.imageWidth)
                            .put("h", frame.imageHeight)
                        val arr = JSONArray()
                        frame.landmarks.forEach { p ->
                            arr.put(JSONArray().put(p.x.toDouble()).put(p.y.toDouble()).put(p.z.toDouble()).put(p.visibility.toDouble()).put(p.presence.toDouble()))
                        }
                        obj.put("lm", arr)
                        dumpFile.appendText(obj.toString() + "\n")
                    }
                    currentOnPoseFrame(frame)
                },
                onError = { currentOnError(it) },
            )
        }.onFailure {
            currentOnError(it.message ?: "姿态模型加载失败")
        }.getOrNull()
    }

    LaunchedEffect(replayDir, processor) {
        if (processor == null) return@LaunchedEffect
        withContext(Dispatchers.IO) {
            val files = File(replayDir)
                .listFiles { file -> file.extension.lowercase() in setOf("jpg", "jpeg", "png") }
                ?.sortedBy { it.name }
                .orEmpty()
            if (files.isEmpty()) {
                withContext(Dispatchers.Main) { currentOnError("回放目录为空：$replayDir") }
                return@withContext
            }
            val frameMs = 1_000L / REPLAY_FPS
            val startMs = SystemClock.elapsedRealtime()
            var analyzed = 0
            var index = 0
            while (isActive && index < files.size) {
                val wait = startMs + index * frameMs - SystemClock.elapsedRealtime()
                if (wait > 0) delay(wait)
                val bitmap = BitmapFactory.decodeFile(files[index].absolutePath)
                if (bitmap != null) {
                    if (currentAnalyzeFrames && !processor.isBusy) {
                        processor.detect(bitmap, index * frameMs)
                        analyzed++
                    }
                    val image = bitmap.asImageBitmap()
                    val text = "回放 ${index + 1}/${files.size} · 已分析 $analyzed · ${processor.delegateName}"
                    withContext(Dispatchers.Main) {
                        currentBitmap = image
                        progressText = text
                    }
                }
                index++
            }
            withContext(Dispatchers.Main) { progressText = "回放结束 · 已分析 $analyzed/${files.size} · ${processor.delegateName}" }
        }
    }

    DisposableEffect(Unit) {
        onDispose { processor?.close() }
    }

    Box(modifier = modifier.background(Color.Black)) {
        if (showPreview) currentBitmap?.let {
            Image(
                bitmap = it,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
        PoseOverlay(
            frame = poseFrame,
            mirrorHorizontally = false,
            modifier = Modifier.fillMaxSize(),
        )
        Text(
            text = progressText,
            color = Color.White,
            modifier = Modifier
                .align(Alignment.TopStart)
                .statusBarsPadding()
                .padding(start = 12.dp, top = 12.dp),
        )
    }
}

private const val REPLAY_FPS = 30
