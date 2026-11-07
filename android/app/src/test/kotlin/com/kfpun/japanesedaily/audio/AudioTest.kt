package com.kfpun.japanesedaily.audio

import com.kfpun.japanesedaily.data.Course
import com.kfpun.japanesedaily.data.vocab.AssetSource
import com.kfpun.japanesedaily.data.vocab.AudioVoice
import com.kfpun.japanesedaily.data.vocab.FileAssetSource
import com.kfpun.japanesedaily.data.vocab.K
import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.data.vocab.VocabStore
import java.io.File
import kotlin.random.Random
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private class FakeClips : ClipPlayer {
    val played = mutableListOf<Pair<String, Float>>()
    var canPlay = true
    var stops = 0
    private var done: () -> Unit = {}

    override fun play(path: String, rate: Float, onDone: () -> Unit): Boolean {
        if (!canPlay) return false
        played += path to rate
        done = onDone
        return true
    }

    fun finish() = done()

    override fun stop() {
        stops++
    }

    override fun release() = Unit
}

private class FakeTts(var hasVoice: Boolean = true) : TtsEngine {
    val spoken = mutableListOf<TtsRequest>()
    private var done: () -> Unit = {}

    override fun speak(request: TtsRequest, onUnavailable: () -> Unit, onDone: () -> Unit) {
        if (!hasVoice) return onUnavailable()
        spoken += request
        done = onDone
    }

    fun finish() = done()

    override fun stop() = Unit

    override fun release() = Unit
}

private class FakeFocus(var grants: Boolean = true) : AudioFocus {
    var held = false

    override fun request(onLost: () -> Unit): Boolean {
        held = grants
        return grants
    }

    override fun abandon() {
        held = false
    }
}

class AudioTest {
    private val resources = File("../../nihongo/Resources")
    private val store = VocabStore(FileAssetSource(resources))
    private val words = store.allVocab()

    private fun pronouncer(
        clips: FakeClips = FakeClips(),
        tts: FakeTts = FakeTts(),
        focus: FakeFocus = FakeFocus(),
        missing: MutableList<String> = mutableListOf(),
        hints: MutableList<Unit> = mutableListOf(),
        course: Course = Course.current
    ) = AudioPronouncer(
        store,
        clips,
        tts,
        focus,
        course,
        onMissing = { missing += it },
        onNoJapaneseVoice = { hints += Unit },
        random = Random(1)
    )

    private fun word(romaji: String) = words.first { it.romaji == romaji }

    // MARK: clip resolution

    @Test
    fun everyWordResolvesToAClipThatExists() {
        assertEquals(2100, words.size)
        for (v in words) {
            val path = store.audioPath(v)
            assertNotNull("no clip for ${v.id}", path)
            assertTrue("$path missing", File(resources, path!!).isFile)
            assertEquals("audio/vocab/${v.audio}.m4a", path)
        }
    }

    @Test
    fun theAlternateVoiceResolvesToADifferentClipForEveryWord() {
        for (v in words) {
            val default = store.audioPath(v, AudioVoice.Default)
            val alt = store.audioPath(v, AudioVoice.Alternate)
            assertTrue("$alt missing", File(resources, alt!!).isFile)
            assertNotEquals("alternate fell back to default for ${v.id}", default, alt)
            assertTrue(alt.endsWith("-kenzaki.m4a"))
        }
    }

    @Test
    fun anAlternateWithNoClipFallsBackToTheDefault() {
        val v = word("watashi")
        // The real assets minus every alternate clip: a course shipping one voice.
        val files = FileAssetSource(resources)
        val bare = VocabStore(object : AssetSource {
            override fun open(path: String) = files.open(path)

            override fun list(dir: String) = files.list(dir).filterNot { it.contains("-kenzaki") }.toSet()
        })
        assertEquals("audio/vocab/${v.audio}.m4a", bare.audioPath(v, AudioVoice.Alternate))
    }

    @Test
    fun aWordWithoutAClipNameResolvesToNothing() {
        assertNull(store.audioPath(word("watashi").copy(audio = null)))
    }

    /** The ladder stops testing listening, with no crash, if the suffix and the generator drift apart. */
    @Test
    fun theAlternateSuffixMatchesTheBuildScript() {
        val script = File("../../scripts/build-minna-data.py").readText()
        val alt = Regex("""(?m)^ALT\s*=\s*"(\w+)"""").find(script)!!.groupValues[1]
        assertTrue(script.contains("""ALT_SUFFIX = f"-{ALT}""""))
        assertEquals("-$alt", AudioVoice.Alternate.suffix)
        assertEquals("", AudioVoice.Default.suffix)
        // And a real asset, so a renamed script constant and a renamed clip cannot agree by accident.
        assertTrue(File(resources, "audio/vocab/1-watashi-kenzaki.m4a").isFile)
        assertTrue(File(resources, "audio/vocab/1-watashi.m4a").isFile)
    }

    @Test
    fun everyKanaAndCheerResolves() {
        assertNotNull(store.kanaAudioPath("ka"))
        assertNotNull(store.cheerAudioPath("sugoi", AudioVoice.Alternate))
        assertTrue(store.cheerAudioPath("sugoi", AudioVoice.Alternate)!!.endsWith("-kenzaki.m4a"))
    }

    // MARK: pronouncer paths

    @Test
    fun aWordPlaysItsClipUnderFocusAndReleasesFocusWhenDone() {
        val clips = FakeClips()
        val tts = FakeTts()
        val focus = FakeFocus()
        val p = pronouncer(clips, tts, focus)
        p.speak(word("watashi"))
        assertEquals(listOf("audio/vocab/1-watashi.m4a" to 1f), clips.played)
        assertTrue(tts.spoken.isEmpty())
        assertTrue(focus.held)
        clips.finish()
        assertFalse(focus.held)
    }

    @Test
    fun theLadderVoiceAndRateReachThePlayer() {
        val clips = FakeClips()
        pronouncer(clips).speak(word("watashi"), AudioVoice.Alternate, 1.5f)
        assertEquals(listOf("audio/vocab/1-watashi-kenzaki.m4a" to 1.5f), clips.played)
    }

    @Test
    fun aWordWithoutAClipSpeaksItsKanaAndReportsTheGap() {
        val clips = FakeClips()
        val tts = FakeTts()
        val missing = mutableListOf<String>()
        val v: Vocab = word("watashi").copy(audio = null)
        pronouncer(clips, tts, missing = missing).speak(v)
        assertTrue(clips.played.isEmpty())
        assertEquals(listOf(TtsRequest(v.kana, "ja-JP", Speech.TTS_RATE)), tts.spoken)
        assertEquals(listOf(v.id), missing)
    }

    @Test
    fun aClipThatFailsToStartFallsBackToTts() {
        val clips = FakeClips().apply { canPlay = false }
        val tts = FakeTts()
        pronouncer(clips, tts).speak(word("watashi"))
        assertEquals(1, tts.spoken.size)
    }

    @Test
    fun aClipLessCourseSpeaksWithoutReportingMissing() {
        val missing = mutableListOf<String>()
        val tts = FakeTts()
        pronouncer(tts = tts, missing = missing, course = Course.Minna.copy(hasBundledAudio = false))
            .speak(word("watashi").copy(audio = null))
        assertEquals(1, tts.spoken.size)
        assertTrue(missing.isEmpty())
    }

    @Test
    fun bareTextTilesSpeakThroughTtsWithAnnotationsStripped() {
        val clips = FakeClips()
        val tts = FakeTts()
        pronouncer(clips, tts).speakText("わたし（私）")
        assertTrue(clips.played.isEmpty())
        assertEquals("わたし", tts.spoken.single().text)
        assertEquals("ja-JP", tts.spoken.single().languageTag)
    }

    @Test
    fun aKanaCellPlaysItsClip() {
        val clips = FakeClips()
        pronouncer(clips).speak(K("か", "カ", "ka"))
        assertEquals("audio/kana/kana-ka.m4a", clips.played.single().first)
    }

    @Test
    fun aKanaWithNoClipSpeaksTheHiraganaAndReportsIt() {
        val tts = FakeTts()
        val missing = mutableListOf<String>()
        pronouncer(tts = tts, missing = missing).speak(K("ゑ", "ヱ", "zzz-nope"))
        assertEquals("ゑ", tts.spoken.single().text)
        assertEquals(listOf("kana-zzz-nope"), missing)
    }

    @Test
    fun cheersPlayABundledVoiceAndFallBackToText() {
        val clips = FakeClips()
        val tts = FakeTts()
        val p = pronouncer(clips, tts)
        p.speakCheer("sugoi", "すごい")
        assertTrue(clips.played.single().first.startsWith("audio/cheer/cheer-sugoi"))
        p.speakCheer("not-a-cheer", "ほげ")
        assertEquals("ほげ", tts.spoken.single().text)
    }

    @Test
    fun anExamplePlaysItsClip() {
        val clips = FakeClips()
        val v = words.first { it.example != null }
        pronouncer(clips).speakExample(v)
        assertEquals("audio/examples/ex-${v.audio}.m4a", clips.played.single().first)
    }

    @Test
    fun deniedFocusPlaysNothing() {
        val clips = FakeClips()
        val tts = FakeTts()
        pronouncer(clips, tts, FakeFocus(grants = false)).speak(word("watashi"))
        assertTrue(clips.played.isEmpty() && tts.spoken.isEmpty())
    }

    @Test
    fun stopHaltsBothPlayersAndFreesFocus() {
        val clips = FakeClips()
        val focus = FakeFocus()
        val p = pronouncer(clips, focus = focus)
        p.speak(word("watashi"))
        val stops = clips.stops
        p.stop()
        assertTrue(clips.stops > stops)
        assertFalse(focus.held)
    }

    // MARK: no Japanese voice

    @Test
    fun noJapaneseVoiceIsHandledWithOneHint() {
        val tts = FakeTts(hasVoice = false)
        val focus = FakeFocus()
        val hints = mutableListOf<Unit>()
        val p = pronouncer(tts = tts, focus = focus, hints = hints)
        repeat(3) { p.speakText("か") }
        assertEquals(1, hints.size)
        assertTrue(tts.spoken.isEmpty())
        assertFalse(focus.held)
    }

    @Test
    fun completionCallbackFiresForTtsAndClips() {
        val clips = FakeClips()
        val tts = FakeTts()
        val p = pronouncer(clips, tts)
        var done = 0
        p.speak(word("watashi")) { done++ }
        clips.finish()
        p.speakText("か") { done++ }
        tts.finish()
        assertEquals(2, done)
    }

    // MARK: rates

    @Test
    fun onlyNormalSpeedIsFreeAndTheDialIsGated() {
        val pro = object : PremiumStatus {
            override val isPremium = true
        }
        assertEquals(listOf(0.8, 1.0, 1.2, 1.5), PlaybackRates.choices)
        for (r in PlaybackRates.choices) {
            assertEquals(1.0, PlaybackRates.effective(r, NotPremium), 0.0)
            assertEquals(r, PlaybackRates.effective(r, pro), 0.0)
            assertEquals(r != 1.0, PlaybackRates.isLocked(r, NotPremium))
            assertFalse(PlaybackRates.isLocked(r, pro))
        }
        assertFalse(NotPremium.isPremium)
    }

    // MARK: speech policy and credits

    @Test
    fun meaningsAreSpokenInTheirOwnLanguage() {
        assertEquals("zh-CN", Speech.meaningLocale("zh"))
        assertEquals("zh-TW", Speech.meaningLocale("zh-Hant"))
        assertEquals("fil-PH", Speech.meaningLocale("fil"))
        assertEquals("de", Speech.meaningLocale("de"))
    }

    @Test
    fun randomVoiceReachesBoth() {
        val seen = (1..40).map { Speech.randomVoice(Random(it)) }.toSet()
        assertEquals(setOf(AudioVoice.Default, AudioVoice.Alternate), seen)
    }

    @Test
    fun everyBundledVoiceHasItsCreditLine() {
        val skill = File("../../minna/.claude/skills/generate-audio/SKILL.md")
        val script = File("../../scripts/build-minna-data.py").readText()
        for (c in Licenses.voicevox) {
            assertTrue("generator does not use ${c.voice}", script.contains("\"${c.voice}\""))
            if (skill.isFile) {
                assertTrue(
                    "${c.line} not in the submodule's licensing note",
                    skill.readText().contains(c.line)
                )
            }
        }
        assertEquals(listOf("VOICEVOX:WhiteCUL", "VOICEVOX:剣崎雌雄"), Licenses.voicevox.map { it.line })
    }
}
