package com.kfpun.japanesedaily

import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The minna flavour reads nihongo/Resources in place (app/build.gradle.kts), so this checks the
 * generated data is there and is the JSON the parser (FOX-148) will expect. A JVM test has no
 * APK; CI additionally checks that the debug APK contains these files.
 */
class MinnaAssetsTest {
    // Unit tests run with the module directory (android/app) as the working directory.
    private val resources = File("../../nihongo/Resources")

    @Test
    fun minnaDataIsReadable() {
        val text = File(resources, "MinnaData.json").readText()
        assertTrue(text.trimStart().startsWith("{"))
        assertTrue(text.contains("\"lessons\""))
        assertTrue(text.contains("\"languages\""))
    }

    @Test
    fun kanaChartIsReadable() {
        assertTrue(File(resources, "KanaChart.json").readText().isNotBlank())
    }

    @Test
    fun audioClipsArePresent() {
        for (kind in listOf("vocab", "kana")) {
            val clips = File(resources, "audio/$kind").listFiles { f -> f.extension == "m4a" }
            assertTrue("audio/$kind has no clips", clips != null && clips.isNotEmpty())
        }
    }
}
