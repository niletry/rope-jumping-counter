package com.yzrun.ropecounter.vision

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.os.SystemClock
import androidx.camera.core.ImageProxy
import androidx.core.graphics.createBitmap
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import android.util.Log
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import java.io.Closeable
import java.util.concurrent.atomic.AtomicBoolean

class PoseLandmarkerProcessor(
    private val context: Context,
    private val onResult: (PoseFrame) -> Unit,
    private val onError: (String) -> Unit,
) : Closeable {
    private val lock = Any()
    private var landmarker: PoseLandmarker
    private var delegate: Delegate
    private var closed = false
    private var firstFrameLogged = false
    private val watchdog = InFlightWatchdog(STALL_TIMEOUT_MS)

    /** Which delegate the landmarker ended up on; shown in the replay HUD for diagnostics. */
    @Volatile
    var delegateName: String
        private set

    init {
        // Prefer the GPU: it is faster for this model and, unlike the CPU path, is not affected by
        // the big-core frequency caps phones apply when they get warm while charging. Fall back to
        // the CPU if the GPU delegate cannot be initialised on this device.
        val (created, used) = create(listOf(Delegate.GPU, Delegate.CPU))
        landmarker = created
        delegate = used
        delegateName = used.name
        Log.i(TAG, "Pose landmarker running on $used")
    }

    private fun create(candidates: List<Delegate>): Pair<PoseLandmarker, Delegate> {
        for (candidate in candidates) {
            val created = runCatching { PoseLandmarker.createFromOptions(context, options(candidate)) }
                .onFailure { Log.w(TAG, "Pose landmarker on $candidate failed: ${it.message}") }
                .getOrNull()
            if (created != null) return created to candidate
        }
        throw IllegalStateException("无法初始化姿态模型")
    }

    private fun options(delegate: Delegate): PoseLandmarker.PoseLandmarkerOptions {
        val baseOptions = BaseOptions.builder()
            .setModelAssetPath(MODEL_ASSET)
            .setDelegate(delegate)
            .build()
        return PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.LIVE_STREAM)
            .setNumPoses(1)
            .setMinPoseDetectionConfidence(0.50f)
            .setMinPosePresenceConfidence(0.50f)
            .setMinTrackingConfidence(0.50f)
            .setResultListener { result, inputImage -> handleResult(result, inputImage.width, inputImage.height) }
            .setErrorListener { error -> handleFailure(error.message ?: "姿态识别发生错误") }
            .build()
    }

    @Volatile
    private var busy = false
    private val recovering = AtomicBoolean(false)

    /**
     * True while a replay frame is in flight. Reading it also notices a landmarker that stopped
     * answering and starts the switch to the CPU, so a caller that waits for "not busy" is never
     * stuck forever.
     */
    val isBusy: Boolean
        get() {
            if (busy) ensureAlive()
            return busy
        }

    fun detect(bitmap: Bitmap, timestampMs: Long) {
        busy = true
        if (!submit(BitmapImageBuilder(bitmap).build(), timestampMs, "无法分析回放画面")) busy = false
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
            submit(BitmapImageBuilder(rotated).build(), image.imageInfo.timestamp / 1_000_000L, "无法分析摄像头画面")
        } finally {
            image.close()
        }
    }

    /**
     * Hands a frame to the landmarker. Frames are dropped while a dead landmarker is being
     * replaced; the next ones go to the CPU landmarker.
     */
    private fun submit(image: MPImage, timestampMs: Long, failureMessage: String): Boolean {
        ensureAlive()
        if (recovering.get()) return false
        val now = SystemClock.elapsedRealtime()
        return try {
            synchronized(lock) {
                if (closed) return false
                if (!firstFrameLogged) {
                    firstFrameLogged = true
                    Log.i(TAG, "First frame handed to the $delegate landmarker")
                }
                watchdog.submitted(now)
                landmarker.detectAsync(image, timestampMs)
            }
            true
        } catch (error: Throwable) {
            watchdog.answered()
            recoverAsync(error.message ?: failureMessage, report = true)
            false
        }
    }

    /** A frame unanswered for longer than the timeout means the graph died without telling us. */
    private fun ensureAlive() {
        if (watchdog.isStalled(SystemClock.elapsedRealtime())) recoverAsync("姿态识别无响应", report = false)
    }

    private fun handleFailure(message: String) {
        recoverAsync(message, report = true)
    }

    /**
     * Switches to the CPU on a background thread: the error listener runs on the graph's own
     * thread, and closing a dead GPU graph can take a while, so neither may happen on the caller.
     */
    private fun recoverAsync(reason: String, report: Boolean) {
        if (!recovering.compareAndSet(false, true)) return
        Thread({
            try {
                fallBackToCpu(reason, report)
            } finally {
                recovering.set(false)
            }
        }, "pose-fallback").start()
    }

    /**
     * Replaces a failed GPU landmarker with a CPU one. Returns false when already on the CPU;
     * [report] decides whether that case is shown to the user. Frames in flight are abandoned.
     */
    private fun fallBackToCpu(reason: String, report: Boolean): Boolean {
        synchronized(lock) {
            if (closed || delegate == Delegate.CPU) {
                // Nothing left to fall back to: drop the frames in flight and keep going. A slow
                // CPU (an emulator, a throttled phone) must not turn into an error dialog.
                watchdog.reset()
                busy = false
                Log.w(TAG, "Pose landmarker on $delegate: $reason")
                if (!closed && report) onError(reason)
                return false
            }
            Log.w(TAG, "Pose landmarker on GPU failed ($reason); switching to CPU")
            val old = landmarker
            val (created, used) = try {
                create(listOf(Delegate.CPU))
            } catch (error: Throwable) {
                onError(error.message ?: reason)
                return false
            }
            landmarker = created
            delegate = used
            delegateName = "CPU (GPU failed)"
            watchdog.reset()
            busy = false
            closeQuietly(old)
            return true
        }
    }

    private fun handleResult(result: PoseLandmarkerResult, width: Int, height: Int) {
        watchdog.answered()
        busy = false
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
        synchronized(lock) {
            if (closed) return
            closed = true
            closeQuietly(landmarker)
        }
    }

    /** A graph that failed rethrows its error from close(); that must not take the app down. */
    private fun closeQuietly(target: PoseLandmarker) {
        runCatching { target.close() }.onFailure { Log.w(TAG, "Closing pose landmarker failed: ${it.message}") }
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
        const val TAG = "PoseLandmarker"
        /** Longer than any sane inference, shorter than a user's patience. */
        const val STALL_TIMEOUT_MS = 3_000L
    }
}
