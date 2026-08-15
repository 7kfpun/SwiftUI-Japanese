import Foundation

/// Everything that differs between the apps built from this codebase, in one place.
///
/// The engine is dataset-agnostic almost everywhere already — `Challenge` derives the
/// whole ladder from a word count, `VocabStore.availableLanguages` reads its language
/// list out of the data file — so what actually varies is a short list of constants that
/// used to be literals scattered across four targets. Each one of those was a way for a
/// second app to silently share the first app's state: the same App Group, the same
/// CloudKit container, the same StoreKit products.
///
/// Lives in `Shared/` because the widget and watch targets need the App Group and the
/// sample deck at compile time, so this type may only use plain values — no `Vocab`, no
/// StoreKit, nothing from the app target.
struct Course {
    /// Analytics/survey discriminator. Also the only safe thing to key persisted data on.
    let id: String
    /// Bundled JSON compiled by `scripts/build-*-data.py`, without the extension.
    let dataResource: String
    /// Whether this course's dataset ships audio clips. When false, every word plays
    /// through the live-TTS fallback by design, and a missing clip is not an anomaly —
    /// see `Track.audioMissing`, which would otherwise fire on every single tap.
    let hasBundledAudio: Bool
    /// Highest lesson number; lessons are `1...lessonCount`.
    let lessonCount: Int
    /// The segments of the lesson list's picker, in teaching order. Minna carves its
    /// flat 50 into four difficulty bands; JLPT's segments are the levels themselves,
    /// which is why the level tier this replaced was never needed — one picker already
    /// sits above the list, and a second screen would have been a tier of five rows.
    ///
    /// Must cover `1...lessonCount` contiguously: the list renders exactly the selected
    /// segment's range, so a gap hides lessons and an overlap shows them twice.
    let groups: [Group]
    /// Lessons 1…`freeLessonLimit` are free in full.
    ///
    /// Not the only way past the paywall: three-starring every challenge in those
    /// lessons earns `groups.first` outright — see `Gating.freeThrough(earnedFirstGroup:)`.
    let freeLessonLimit: Int
    let appGroup: String
    let cloudKitContainer: String
    /// This app's own App Store listing — where Settings' share row and the recommend
    /// nudge send people. Two apps, two listings: a JLPT user recommending the Minna app
    /// is the kind of mistake nobody would ever report.
    let appStoreURL: String
    let products: Products
    /// Shown by the widget, the watch app and the watch complications before the phone
    /// has ever published a snapshot — so nothing is ever blank. Course-specific: a
    /// JLPT widget showing Minna's lesson-1 words is exactly the kind of silent
    /// mismatch the hand-copied decks used to produce.
    let sampleWords: [TodayShared.Word]

    /// Product IDs. Case-sensitive and immutable once sold — note the uppercase M in
    /// `3M`/`6M`, and that the lowercase 2019 IDs stay reserved forever.
    struct Products {
        let lifetime: String
        let subscriptions: [String]
        /// No longer sold, still honoured so old buyers restore.
        let legacy: [String]
    }

    /// One segment of the lesson list's picker.
    ///
    /// `name` is passed to `L.t`, which falls back to the key itself when the string
    /// isn't in `UIStrings.json` — that is deliberate for JLPT, whose "N5"…"N1" are
    /// proper nouns identical in all 17 languages. Minna's four band names *are*
    /// registered keys and do translate.
    struct Group {
        let name: String
        let first: Int
        let last: Int

        var range: ClosedRange<Int> { first...last }
    }

    func hasLesson(_ n: Int) -> Bool { (1...lessonCount).contains(n) }
}

extension Course {
    static let minna = Course(
        id: "minna",
        dataResource: "MinnaData",
        hasBundledAudio: true,
        lessonCount: 50,
        groups: [
            .init(name: "Beginning 1", first: 1, last: 13),
            .init(name: "Beginning 2", first: 14, last: 25),
            .init(name: "Advanced 1", first: 26, last: 38),
            .init(name: "Advanced 2", first: 39, last: 50),
        ],
        freeLessonLimit: 5,
        appGroup: "group.com.kfpun.nihongo",
        cloudKitContainer: "iCloud.com.kfpun.nihongo",
        appStoreURL: "https://apps.apple.com/app/id1447639161",
        products: .init(
            lifetime: "com.kfpun.nihongo.premium.lifetime",
            subscriptions: [
                "com.kfpun.nihongo.premium.1m",
                "com.kfpun.nihongo.premium.3M",
                "com.kfpun.nihongo.premium.6M",
            ],
            legacy: [
                "com.kfpun.nihongo.premium.3m",
                "com.kfpun.nihongo.premium.6m",
                "com.kfpun.nihongo.premium.12m",
            ]),
        sampleWords: [
            .init(kana: "わたし", kanji: "私", romaji: "watashi", meaning: "I"),
            .init(kana: "せんせい", kanji: "先生", romaji: "sensei", meaning: "teacher"),
            .init(kana: "がくせい", kanji: "学生", romaji: "gakusei", meaning: "student"),
            .init(kana: "ほん", kanji: "本", romaji: "hon", meaning: "book"),
            .init(kana: "とけい", kanji: "時計", romaji: "tokei", meaning: "watch, clock"),
            .init(kana: "でんわ", kanji: "電話", romaji: "denwa", meaning: "telephone"),
            .init(kana: "くるま", kanji: "車", romaji: "kuruma", meaning: "car"),
        ])

    static let jlpt = Course(
        id: "jlpt",
        dataResource: "JLPTData",
        // All 7,972 entries gained Kyoko clips in the submodule's `47d51da`, normalised
        // to minna's RMS target so the two courses play back equally loud. Live TTS
        // stays as the fallback path it always was — bare kana tiles still use it.
        hasBundledAudio: true,
        lessonCount: 201,
        // Mirrors the `levels` block that `build-jlpt-data.py` writes into
        // JLPTData.json. Hardcoded for the same reason `lessonCount` is: `Course`
        // compiles into the widget and watch targets, which resolve it long before
        // any JSON is decoded. If the dataset ever regroups, the build script's
        // summary line is where the drift shows.
        groups: [
            .init(name: "N5", first: 1, last: 19),
            .init(name: "N4", first: 20, last: 37),
            .init(name: "N3", first: 38, last: 93),
            .init(name: "N2", first: 94, last: 136),
            .init(name: "N1", first: 137, last: 201),
        ],
        // Five, matching Minna's — one rule across both apps rather than a per-course
        // tuning nobody can remember. A thinner slice here (5 of 201 against 5 of 50),
        // but the offer is "finish a few whole lessons", which reads the same either
        // way — and the earned unlock is what makes the slice generous: mastering these
        // five opens all of N5, 19 lessons, against Minna's 13.
        freeLessonLimit: 5,
        appGroup: "group.com.kfpun.jlptjp",
        cloudKitContainer: "iCloud.com.kfpun.jlptjp",
        appStoreURL: "https://apps.apple.com/app/id6800220716",
        // These IDs deliberately do **not** mirror minna's, and both differences are
        // load-bearing. Product IDs are immutable and unique per *team* forever, so this
        // block records what App Store Connect actually holds — never an aspiration.
        //
        // `forever`, not `lifetime`: `…premium.lifetime` was created here and deleted
        // during setup, and Apple reserves a deleted product ID permanently. The word is
        // simply gone for this app. (`…premium.lifttime`, a typo made while working
        // around that, also exists and is deliberately left unattached — deleting it
        // would burn a third ID and gain nothing.) `forever` matches the paywall's own
        // "Pay once, yours forever", and `Store.tierLabel` matches this product by
        // identity rather than by string, so analytics still report `lifetime`.
        //
        // Lowercase `3m`/`6m`: minna's uppercase `3M`/`6M` are a workaround for lowercase
        // IDs the RN app burned there. JLPT has no such history, so lowercase is the
        // clean choice here, not a mistake to correct.
        products: .init(
            lifetime: "com.kfpun.jlptjp.premium.forever",
            subscriptions: [
                "com.kfpun.jlptjp.premium.1m",
                "com.kfpun.jlptjp.premium.3m",
                "com.kfpun.jlptjp.premium.6m",
            ],
            // Nothing legacy yet — this app has never sold anything.
            legacy: []),
        // The opening N5 lesson, "Greetings, Replies and Everyday Phrases". Written
        // out rather than read from `VocabStore` because the widget and the watch
        // complications render this before any app code has run.
        sampleWords: [
            .init(kana: "はい", kanji: "はい", romaji: "hai", meaning: "yes"),
            .init(kana: "いいえ", kanji: "いいえ", romaji: "iie", meaning: "no, not at all"),
            .init(kana: "ちがう", kanji: "違う", romaji: "chigau", meaning: "to be different; wrong"),
            .init(kana: "どうぞ", kanji: "どうぞ", romaji: "douzo", meaning: "please, kindly"),
            .init(kana: "どうも", kanji: "どうも", romaji: "doumo", meaning: "thank you"),
            .init(kana: "ください", kanji: "下さい", romaji: "kudasai", meaning: "please do for me"),
            .init(kana: "もしもし", kanji: "もしもし", romaji: "moshimoshi", meaning: "hello? (on the phone)"),
        ])

    /// The course this build ships.
    ///
    /// A per-*target* choice, not a runtime one: the widget and watch extensions must
    /// resolve the App Group before any app code runs, and one app must never be able
    /// to reach another's container by accident. `COURSE_JLPT` is set in the `jlpt`
    /// target's `SWIFT_ACTIVE_COMPILATION_CONDITIONS` and nowhere else.
    #if COURSE_JLPT
    static let current = Course.jlpt
    #else
    static let current = Course.minna
    #endif
}
