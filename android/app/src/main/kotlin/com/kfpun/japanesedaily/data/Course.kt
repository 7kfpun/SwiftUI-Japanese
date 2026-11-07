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
     * The Play products (FOX-158), permanent once created in Play Console. One subscription whose
     * base plans are the 1, 3, 6 and 12 month periods, plus the one-time [lifetime] product. They are
     * independent of the iOS ids, which carry a bundle prefix and the 3M/6M case workaround.
     */
    data class Products(val lifetime: String, val subscription: String, val basePlans: List<String>)

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
                subscription = "premium.subscription",
                basePlans = listOf("p1m", "p3m", "p6m", "p12m")
            )
        )

        /** The course this build ships. The `minna` flavour is the only one in v1. */
        val current: Course = Minna
    }
}
