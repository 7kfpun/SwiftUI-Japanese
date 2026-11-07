package com.kfpun.japanesedaily.data

/**
 * Everything that differs between the courses built from this codebase (port of `Shared/Course.swift`).
 * Only Minna is implemented in v1; a `jlpt` flavour adds a second instance and points
 * [dataResource] at `Apps/jlpt/Resources` through its own asset source.
 */
data class Course(
    /** Analytics/survey discriminator, and the only safe thing to key persisted data on. */
    val id: String,
    /** Bundled JSON compiled by `scripts/build-*-data.py`, without the extension. */
    val dataResource: String,
    /** False means every word plays through live TTS by design. */
    val hasBundledAudio: Boolean,
    /** Highest lesson number; lessons are `1..lessonCount`. */
    val lessonCount: Int,
    /** The lesson list's picker segments. They must tile `1..lessonCount` with no gap or overlap. */
    val groups: List<Group>,
    /** Lessons `1..freeLessonLimit` are free in full. */
    val freeLessonLimit: Int,
    val products: Products
) {
    /** One segment of the lesson list's picker. [name] is a `UIStrings.json` key. */
    data class Group(val name: String, val first: Int, val last: Int) {
        val range: IntRange get() = first..last
    }

    /**
     * Play product ids. FOX-158 creates the real Play products; these mirror the iOS ids' shape
     * and are case-sensitive like them. [legacy] is restore-only, never sold.
     */
    data class Products(val lifetime: String, val subscriptions: List<String>, val legacy: List<String>)

    fun hasLesson(n: Int): Boolean = n in 1..lessonCount

    companion object {
        val Minna = Course(
            id = "minna",
            dataResource = "MinnaData",
            hasBundledAudio = true,
            lessonCount = 50,
            groups = listOf(
                Group("Beginning 1", 1, 13),
                Group("Beginning 2", 14, 25),
                Group("Advanced 1", 26, 38),
                Group("Advanced 2", 39, 50)
            ),
            freeLessonLimit = 5,
            products = Products(
                lifetime = "premium.lifetime",
                subscriptions = listOf("premium.1m", "premium.3M", "premium.6M", "premium.12M"),
                legacy = listOf("premium.3m", "premium.6m", "premium.12m")
            )
        )

        /** The course this build ships. The `minna` flavour is the only one in v1. */
        val current: Course = Minna
    }
}
