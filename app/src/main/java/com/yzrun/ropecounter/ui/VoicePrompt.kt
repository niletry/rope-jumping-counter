package com.yzrun.ropecounter.ui

import android.content.Context
import com.yzrun.ropecounter.R
import java.io.File

/** Encouragement prompts that play on count milestones. Each has a bundled default and an optional user recording. */
enum class VoicePrompt(val label: String, val hint: String, val defaultRes: Int, private val fileName: String) {
    CHEER("每 10 次", "默认“加油”", R.raw.prompt_cheer, "voice_cheer.m4a"),
    BRAVO("每 100 次", "默认“真棒”", R.raw.prompt_bravo, "voice_bravo.m4a"),
    ;

    fun customFile(context: Context): File = File(context.filesDir, fileName)
}
