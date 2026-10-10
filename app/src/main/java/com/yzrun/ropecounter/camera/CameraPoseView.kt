package com.yzrun.ropecounter.camera

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.yzrun.ropecounter.vision.PoseFrame
import com.yzrun.ropecounter.vision.PoseLandmarkerProcessor
import java.util.concurrent.Executors

@Composable
fun CameraPoseView(
    lensFacing: Int,
    analyzeFrames: Boolean,
    poseFrame: PoseFrame?,
    onPoseFrame: (PoseFrame) -> Unit,
    onError: (String) -> Unit,
    modifier: Modifier = Modifier,
    showPreview: Boolean = true,
) {
    val context = LocalContext.current
    var hasPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }
    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { granted -> hasPermission = granted }

    LaunchedEffect(Unit) {
        if (!hasPermission) permissionLauncher.launch(Manifest.permission.CAMERA)
    }

    Box(modifier = modifier.background(Color.Black)) {
        if (hasPermission) {
            ActiveCamera(
                lensFacing = lensFacing,
                analyzeFrames = analyzeFrames,
                onPoseFrame = onPoseFrame,
                onError = onError,
                modifier = Modifier.fillMaxSize(),
            )
            if (!showPreview) Box(Modifier.fillMaxSize().background(Color.Black))
            PoseOverlay(
                frame = poseFrame,
                mirrorHorizontally = lensFacing == CameraSelector.LENS_FACING_FRONT,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Button(
                onClick = { permissionLauncher.launch(Manifest.permission.CAMERA) },
                modifier = Modifier.align(Alignment.Center),
            ) {
                Text("授予摄像头权限")
            }
        }
    }
}

@Composable
private fun ActiveCamera(
    lensFacing: Int,
    analyzeFrames: Boolean,
    onPoseFrame: (PoseFrame) -> Unit,
    onError: (String) -> Unit,
    modifier: Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val currentOnPoseFrame by rememberUpdatedState(onPoseFrame)
    val currentOnError by rememberUpdatedState(onError)
    val currentAnalyzeFrames by rememberUpdatedState(analyzeFrames)
    val previewView = remember {
        PreviewView(context).apply {
            scaleType = PreviewView.ScaleType.FILL_CENTER
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        }
    }
    val executor = remember { Executors.newSingleThreadExecutor() }
    val processor = remember {
        runCatching {
            PoseLandmarkerProcessor(
                context = context.applicationContext,
                onResult = { currentOnPoseFrame(it) },
                onError = { currentOnError(it) },
            )
        }.onFailure {
            currentOnError(it.message ?: "姿态模型加载失败")
        }.getOrNull()
    }

    AndroidView(factory = { previewView }, modifier = modifier)

    DisposableEffect(lensFacing, lifecycleOwner, processor) {
        val providerFuture = ProcessCameraProvider.getInstance(context)
        var provider: ProcessCameraProvider? = null
        val listener = Runnable {
            runCatching {
                provider = providerFuture.get()
                val preview = Preview.Builder().build().also {
                    it.surfaceProvider = previewView.surfaceProvider
                }
                val analysis = ImageAnalysis.Builder()
                    .setResolutionSelector(
                        ResolutionSelector.Builder()
                            .setResolutionStrategy(
                                ResolutionStrategy(
                                    android.util.Size(480, 640),
                                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER,
                                ),
                            )
                            .build(),
                    )
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                    .also { useCase ->
                        useCase.setAnalyzer(executor) { image ->
                            if (currentAnalyzeFrames && processor != null) {
                                processor.detect(image)
                            } else {
                                image.close()
                            }
                        }
                    }
                val selector = CameraSelector.Builder()
                    .requireLensFacing(lensFacing)
                    .build()
                provider?.unbindAll()
                provider?.bindToLifecycle(lifecycleOwner, selector, preview, analysis)
            }.onFailure {
                currentOnError(it.message ?: "摄像头启动失败")
            }
        }
        providerFuture.addListener(listener, ContextCompat.getMainExecutor(context))

        onDispose {
            provider?.unbindAll()
        }
    }

    DisposableEffect(Unit) {
        onDispose {
            processor?.close()
            executor.shutdown()
        }
    }
}
