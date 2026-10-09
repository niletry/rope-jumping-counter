package com.yzrun.ropecounter.counter

import com.yzrun.ropecounter.vision.PoseFrame
import com.yzrun.ropecounter.vision.PosePoint
import java.io.File
import org.junit.Assume.assumeTrue
import org.junit.Test

/**
 * Offline regression harness: replays landmarks dumped by ReplayPoseView through JumpDetector
 * with several parameter variants and prints per-segment counts against ground truth.
 * Run with: ./gradlew testDebugUnitTest --tests '*ReplayHarnessTest*' -PreplayCsv=/path/landmarks.csv
 */
class ReplayHarnessTest {
    // Ground truth for the 2026-10-09 test video: segment boundaries (ms) are the midpoints of
    // the four interruptions, counts come from the reference app's on-screen counter.
    private val segmentEnds = longArrayOf(3_700, 20_950, 36_550, 50_600, 61_000)
    private val truth = intArrayOf(4, 43, 29, 29, 18)

    private val variants: List<Pair<String, JumpDetector.Params>> = listOf(
        "base" to JumpDetector.Params(),
        "fixedFeetGap" to JumpDetector.Params(FEET_VELOCITY_DIFFERENCE_RATIO = 0f),
        "noFeetRule" to JumpDetector.Params(MAX_FEET_VELOCITY_DIFFERENCE = 99f, MIN_SINGLE_FOOT_RISING_VELOCITY = -99f, MIN_FEET_RISING_VELOCITY = -99f),
        "smooth0.65" to JumpDetector.Params(SMOOTHING_ALPHA = 0.65f),
    )

    @Test
    fun replayDumpedLandmarks() {
        val path = System.getProperty("replayCsv") ?: System.getenv("REPLAY_CSV")
        assumeTrue("no replayCsv given", path != null && File(path).exists())
        val frames = loadFrames(File(path!!))
        val sb = StringBuilder("REPLAY frames=${frames.size}\n")
        sb.append("%-24s %6s %6s %6s %6s %6s %6s\n".format("variant", "seg1", "seg2", "seg3", "seg4", "seg5", "total"))
        sb.append("%-24s %6d %6d %6d %6d %6d %6d\n".format("truth", truth[0], truth[1], truth[2], truth[3], truth[4], truth.sum()))
        variants.forEach { (name, params) ->
            val detector = JumpDetector(params)
            val jumps = ArrayList<Long>()
            val trace = StringBuilder()
            frames.forEach { f ->
                val d = detector.process(f)
                trace.append("${f.timestampMs},${d.state},${"%.4f".format(d.normalizedLift)},${if (d.jumpDetected) 1 else 0},${d.guidance}\n")
                if (d.jumpDetected) jumps.add(f.timestampMs)
            }
            val seg = IntArray(5)
            jumps.forEach { t -> seg[segmentEnds.indexOfFirst { t <= it }.coerceAtLeast(0)]++ }
            val diffs = seg.indices.map { seg[it] - truth[it] }
            sb.append("%-24s %6s %6s %6s %6s %6s %6s\n".format(name, *diffs.map { "%+d".format(it) }.toTypedArray(), "%d".format(jumps.size)))
            val suffix = if (name == "base") "" else ".$name"
            File("$path$suffix.jumps.txt").writeText(jumps.joinToString("\n"))
            File("$path$suffix.trace.csv").writeText(trace.toString())
        }
        println(sb)
        File("$path.report.txt").writeText(sb.toString())
    }

    private fun loadFrames(file: File): List<PoseFrame> = file.readLines().mapNotNull { line ->
        val cols = line.split(',')
        if (cols.size < 3 + 33 * 5) return@mapNotNull null
        val points = (0 until 33).map { i ->
            val b = 3 + i * 5
            PosePoint(cols[b].toFloat(), cols[b + 1].toFloat(), cols[b + 2].toFloat(), cols[b + 3].toFloat(), cols[b + 4].toFloat())
        }
        PoseFrame(cols[0].toLong(), points, cols[1].toInt(), cols[2].toInt())
    }
}
