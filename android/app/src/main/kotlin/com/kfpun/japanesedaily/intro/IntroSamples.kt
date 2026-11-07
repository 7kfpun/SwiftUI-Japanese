package com.kfpun.japanesedaily.intro

import com.kfpun.japanesedaily.data.vocab.Vocab
import com.kfpun.japanesedaily.data.vocab.VocabStore

/** What the intro shows, taken from lesson 1 of the bundled data so the tour cannot drift from it. */
class IntroSamples(val lesson1: List<Vocab>, val languages: List<String>, val lessonCount: Int) {
    /**
     * Card 1 deliberately skips the first entry: わたし is kana-only, so a card built on it would
     * teach three fields where the card options toggle four. It takes the first entry with a
     * distinct kanji, falling back to the first.
     */
    val anatomyWord: Vocab? get() = lesson1.firstOrNull { it.displaysKanji } ?: lesson1.firstOrNull()

    companion object {
        fun from(vocab: VocabStore, language: String) = IntroSamples(
            lesson1 = vocab.lesson(1, language).entries,
            languages = vocab.availableLanguages,
            lessonCount = vocab.course.lessonCount
        )
    }
}
