package com.yzrun.ropecounter.ui

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import java.io.File

/** Records a short AAC clip from the microphone into [target]; auto-stops after [MAX_DURATION_MS]. */
class VoiceRecorder(private val context: Context) {
    private var recorder: MediaRecorder? = null
    private var target: File? = null
    private var temp: File? = null

    val isRecording: Boolean get() = recorder != null

    fun start(file: File, onAutoStop: () -> Unit) {
        stop(discard = true)
        val tmp = File(file.parentFile, file.name + ".tmp")
        val r = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) MediaRecorder(context) else @Suppress("DEPRECATION") MediaRecorder()
        r.setAudioSource(MediaRecorder.AudioSource.MIC)
        r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        r.setAudioSamplingRate(24_000)
        r.setAudioEncodingBitRate(64_000)
        r.setMaxDuration(MAX_DURATION_MS)
        r.setOutputFile(tmp.absolutePath)
        r.setOnInfoListener { _, what, _ ->
            if (what == MediaRecorder.MEDIA_RECORDER_INFO_MAX_DURATION_REACHED) {
                stop(discard = false)
                onAutoStop()
            }
        }
        r.prepare()
        r.start()
        recorder = r
        target = file
        temp = tmp
    }

    /** Stops recording. Returns true when a clip was saved to the target file. */
    fun stop(discard: Boolean = false): Boolean {
        val r = recorder ?: return false
        recorder = null
        val saved = runCatching { r.stop() }.isSuccess && !discard
        r.release()
        val tmp = temp
        val out = target
        temp = null
        target = null
        if (saved && tmp != null && out != null && tmp.length() > 0) {
            out.delete()
            return tmp.renameTo(out)
        }
        tmp?.delete()
        return false
    }

    companion object {
        const val MAX_DURATION_MS = 3_000
    }
}
