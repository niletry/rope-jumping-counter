package com.yzrun.ropecounter.ui

import android.content.Context
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import com.yzrun.ropecounter.R
import java.util.Collections

/** Plays short audio files bundled in res/raw; it never invokes TTS or a network service. */
class FeedbackPlayer(private val context: Context) {
    private val soundPool = SoundPool.Builder()
        .setMaxStreams(2)
        .setAudioAttributes(
            AudioAttributes.Builder()
                // Media usage: audible under Do-Not-Disturb and controlled by the media volume keys.
                // USAGE_ASSISTANCE_SONIFICATION maps to the system stream, which DND mutes.
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build(),
        )
        .build()
    private val loadedSamples = Collections.synchronizedSet(mutableSetOf<Int>())
    private val countBeepSample: Int
    private val standSample: Int
    private val fullBodySample: Int
    private val threeSample: Int
    private val twoSample: Int
    private val oneSample: Int
    private val startSample: Int
    private val promptSamples = HashMap<VoicePrompt, Int>()
    /** Per-jump beep; off by default because many users find it annoying. */
    @Volatile var countBeepEnabled: Boolean = false
    @Volatile private var pendingVoiceSample: Int? = null
    @Volatile private var activeVoiceStream = 0

    private val vibrator: Vibrator? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        context.getSystemService(VibratorManager::class.java)?.defaultVibrator
    } else {
        @Suppress("DEPRECATION")
        context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    init {
        soundPool.setOnLoadCompleteListener { _, sampleId, status ->
            if (status == 0) {
                loadedSamples += sampleId
                if (pendingVoiceSample == sampleId) {
                    pendingVoiceSample = null
                    playVoice(sampleId)
                }
            }
        }
        countBeepSample = soundPool.load(context, R.raw.count_beep, 1)
        standSample = soundPool.load(context, R.raw.prompt_stand, 1)
        fullBodySample = soundPool.load(context, R.raw.prompt_full_body, 1)
        threeSample = soundPool.load(context, R.raw.countdown_three, 1)
        twoSample = soundPool.load(context, R.raw.countdown_two, 1)
        oneSample = soundPool.load(context, R.raw.countdown_one, 1)
        startSample = soundPool.load(context, R.raw.prompt_start, 1)
        reloadPrompts()
    }

    fun jump() {
        if (countBeepEnabled && countBeepSample in loadedSamples) {
            soundPool.play(
                countBeepSample,
                MAX_PLAYBACK_VOLUME,
                MAX_PLAYBACK_VOLUME,
                COUNT_BEEP_PRIORITY,
                0,
                1f,
            )
        }
    }

    fun phaseChanged() {
        vibrator?.vibrate(VibrationEffect.createOneShot(80, VibrationEffect.DEFAULT_AMPLITUDE))
    }

    fun speakGuidance(message: String) {
        when (message) {
            "请站稳" -> playVoice(standSample)
            "请保持全身入镜" -> playVoice(fullBodySample)
        }
    }

    fun speakCountdown(seconds: Int) {
        val sample = when (seconds) {
            3 -> threeSample
            2 -> twoSample
            1 -> oneSample
            else -> return
        }
        playVoice(sample)
    }

    fun speakStart() {
        playVoice(startSample)
    }

    /** (Re)loads milestone prompts, preferring a user recording over the bundled default. */
    fun reloadPrompts() {
        VoicePrompt.entries.forEach { prompt ->
            promptSamples[prompt]?.let { old ->
                soundPool.unload(old)
                loadedSamples -= old
            }
            val custom = prompt.customFile(context)
            promptSamples[prompt] = if (custom.exists()) {
                soundPool.load(custom.absolutePath, 1)
            } else {
                soundPool.load(context, prompt.defaultRes, 1)
            }
        }
    }

    /** Plays a milestone prompt ("加油" every 10, "真棒" every 100, or the user's own recording). */
    fun speakPrompt(prompt: VoicePrompt) {
        promptSamples[prompt]?.let { playVoice(it) }
    }

    /** Which prompt, if any, a count change from [before] to [after] should trigger. */
    fun promptFor(before: Int, after: Int): VoicePrompt? = when {
        after / BRAVO_EVERY > before / BRAVO_EVERY -> VoicePrompt.BRAVO
        after / CHEER_EVERY > before / CHEER_EVERY -> VoicePrompt.CHEER
        else -> null
    }

    fun stopSpeech() {
        pendingVoiceSample = null
        if (activeVoiceStream != 0) {
            soundPool.stop(activeVoiceStream)
            activeVoiceStream = 0
        }
    }

    private fun playVoice(sampleId: Int) {
        if (sampleId !in loadedSamples) {
            pendingVoiceSample = sampleId
            return
        }
        stopSpeech()
        activeVoiceStream = soundPool.play(
            sampleId,
            MAX_PLAYBACK_VOLUME,
            MAX_PLAYBACK_VOLUME,
            VOICE_PRIORITY,
            0,
            1f,
        )
    }

    fun release() {
        stopSpeech()
        soundPool.release()
    }

    companion object {
        const val CHEER_EVERY = 10
        const val BRAVO_EVERY = 100
        private const val MAX_PLAYBACK_VOLUME = 1f
        private const val VOICE_PRIORITY = 1
        private const val COUNT_BEEP_PRIORITY = 2
    }
}
