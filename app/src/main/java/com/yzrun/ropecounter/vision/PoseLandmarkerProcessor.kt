package com.yzrun.ropecounter.vision

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import androidx.camera.core.ImageProxy
import androidx.core.graphics.createBitmap
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import java.io.Closeable

class PoseLandmarkerProcessor(
    context: Context,
    private val onResult: (PoseFrame) -> Unit,
    private val onError: (String) -> Unit,
) : Closeable {
    private val landmarker: PoseLandmarker

    init {
        val baseOptions = BaseOptions.builder()
            .setModelAssetPath(MODEL_ASSET)
            .build()
        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.LIVE_STREAM)
            .setNumPoses(1)
            .setMinPoseDetectionConfidence(0.50f)
            .setMinPosePresenceConfidence(0.50f)
            .setMinTrackingConfidence(0.50f)
            .setResultListener { result, inputImage -> handleResult(result, inputImage.width, inputImage.height) }
            .setErrorListener { error -> isBusy = false; onError(error.message ?: "姿态识别发生错误") }
            .build()
        landmarker = PoseLandmarker.createFromOptions(context, options)
    }

    @Volatile
    var isBusy: Boolean = false
        private set

    fun detect(bitmap: Bitmap, timestampMs: Long) {
        try {
            isBusy = true
            landmarker.detectAsync(BitmapImageBuilder(bitmap).build(), timestampMs)
        } catch (error: Throwable) {
            isBusy = false
            onError(error.message ?: "无法分析回放画面")
        }
    }

    fun detect(image: ImageProxy) {
        try {
            val bitmap = image.toBitmapWithPaddingHandled()
            val rotation = image.imageInfo.rotationDegrees
            val rotated = if (rotation == 0) {
                bitmap
            } else {
                Bitmap.createBitmap(
                    bitmap,
                    0,
                    0,
                    bitmap.width,
                    bitmap.height,
                    Matrix().apply { postRotate(rotation.toFloat()) },
                    true,
                ).also { if (it !== bitmap) bitmap.recycle() }
            }
            val mpImage = BitmapImageBuilder(rotated).build()
            landmarker.detectAsync(mpImage, image.imageInfo.timestamp / 1_000_000L)
        } catch (error: Throwable) {
            onError(error.message ?: "无法分析摄像头画面")
        } finally {
            image.close()
        }
    }

    private fun handleResult(result: PoseLandmarkerResult, width: Int, height: Int) {
        isBusy = false
        val points = result.landmarks().firstOrNull().orEmpty().map { landmark ->
            PosePoint(
                x = landmark.x(),
                y = landmark.y(),
                z = landmark.z(),
                visibility = landmark.visibility().orElse(0f),
                presence = landmark.presence().orElse(0f),
            )
        }
        onResult(
            PoseFrame(
                timestampMs = result.timestampMs(),
                landmarks = points,
                imageWidth = width,
                imageHeight = height,
            ),
        )
    }

    override fun close() {
        landmarker.close()
    }

    private fun ImageProxy.toBitmapWithPaddingHandled(): Bitmap {
        val plane = planes.first()
        val buffer = plane.buffer.apply { rewind() }
        val pixelStride = plane.pixelStride
        val rowStride = plane.rowStride
        val paddedWidth = width + (rowStride - pixelStride * width) / pixelStride
        val padded = createBitmap(paddedWidth, height)
        padded.copyPixelsFromBuffer(buffer)
        if (paddedWidth == width) return padded
        return Bitmap.createBitmap(padded, 0, 0, width, height).also { padded.recycle() }
    }

    private companion object {
        const val MODEL_ASSET = "pose_landmarker_lite.task"
    }
}
