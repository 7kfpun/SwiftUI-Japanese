import Foundation

/// Central registry of UserDefaults / @AppStorage keys — one place, no scattered
/// string literals (a typo would silently create a brand-new setting).
enum Pref {
    static let appLanguage         = "appLanguage"
    static let translationLanguage = "translationLanguage"
    static let soundOn             = "isSoundOn"
    static let ordered             = "isOrdered"
    static let kanjiShown          = "isKanjiShown"
    static let kanaShown           = "isKanaShown"
    static let romajiShown         = "isRomajiShown"
    static let translationShown    = "isTranslationShown"
    static let kanaTileScript      = "kanaTileScript"
    /// Whether vocab lists show each word's example sentence. One global switch, not
    /// per-row disclosure: the user's call ("show all / off all"). Off by default
    /// (design 3a): every sentence expanded left four words per screen, and a vocab
    /// list's first job is to be scannable. The flashcard back still shows them.
    static let examplesShown       = "examplesShown"
    /// RETIRED — Train's word order, gone with Train itself when it merged into
    /// Practice (whose scheduler owns the order). The key stays reserved so a future
    /// setting can never silently inherit an old device's stale value.
    static let trainOrdered        = "trainOrdered"
    /// Practice's quiz pair (design 5a): which face the prompt shows and which the
    /// options answer, as `VForm.label` strings — stable ASCII, never localized text.
    /// Unset reads as the default kana → meaning.
    static let practiceFrom        = "practiceFrom"
    static let practiceTo          = "practiceTo"
    /// When true, every quiz card draws a random valid pair instead of the fixed one.
    static let practiceMixed       = "practiceMixed"
    /// "Play all" playback speed as a multiplier (0.8, 1.0, 1.2, 1.5). Applies to the
    /// bundled clips and the TTS fallback alike; unset reads as 1.0.
    static let playbackRate        = "playbackRate"
    /// `ModeVisits`' backing array — which practice modes each lesson has opened.
    static let modeVisits          = "modeVisits"
    /// Flashcards' order picker. Its own key, not Learn's `ordered`: the two screens
    /// default the same way but they are different sittings, and sharing one switch
    /// would make changing the order in one silently change the other.
    static let flashcardsOrdered   = "flashcardsOrdered"
    /// Per-device opt-out of analytics collection, independent of DEBUG/Release —
    /// toggled via a long-press on the version footer in Settings. Lets the
    /// developer exclude their own TestFlight/Release usage without a rebuild.
    static let analyticsExcluded   = "analyticsExcluded"
    /// Set once the rating star row has been shown, so it never asks twice.
    /// Legacy: the boolean "asked once, ever" that shipped only in the unreleased 3.0.0.
    /// Superseded by `ratingAskedAt`; read only by `RatingPrompt.migrateLegacyFlagIfNeeded`.
    static let ratingAsked         = "ratingAsked"
    /// When the star row was last shown, as `timeIntervalSince1970`. A timestamp rather than
    /// a flag so the ask can repeat quarterly — see `RatingPrompt.askAgainAfter`.
    static let ratingAskedAt       = "ratingAskedAt"
    /// When the "recommend it to a friend" nudge was last shown, as
    /// `timeIntervalSince1970`. Separate from `ratingAskedAt` on purpose: the two prompts
    /// have different audiences and different windows (monthly here, quarterly there),
    /// and sharing a key would make each one silence the other — see `SharePrompt`.
    static let shareAskedAt        = "shareAskedAt"

    // MARK: Notifications (see nihongo/StreakReminder.swift)

    /// Whether the daily streak reminder is scheduled. **Off by default** — a learner who
    /// has never asked for notifications hasn't agreed to a daily one, and turning it on
    /// is what triggers the iOS permission prompt.
    static let streakReminderOn    = "streakReminderOn"
    /// Local hour (1…23) the reminder fires. Unset reads as `StreakReminder.defaultHour`,
    /// because a stored 0 can't be told apart from "never chosen".
    static let streakReminderHour  = "streakReminderHour"
    /// When the *soft* opt-in was last shown, as `timeIntervalSince1970`. Not "has the
    /// system prompt been shown": iOS owns that and answers it via
    /// `UNAuthorizationStatus`. This one exists so a "not now" is respected for a while —
    /// see `NotificationOptIn.askAgainAfter`.
    static let notificationAskedAt = "notificationAskedAt"

    // MARK: First-launch intro (see nihongo/Intro)

    /// Set once the intro has been seen — including when it was skipped. It gates the
    /// cover on its own, so a tour that reopened would be a nag, not a tour.
    static let introAnswered       = "introAnswered"
    /// How much kana the learner said they read: "none" / "hiragana" / "both".
    /// **The only intro answer anything acts on**: "none" lands the app on the Kana tab
    /// instead of Today, since Kana is free in full and a Today card is no use to someone
    /// who can't read it yet.
    static let knowsKana           = "knowsKana"
    /// The lesson they said they'd reached in Minna no Nihongo (0 = never studied it).
    ///
    /// **Recorded only.** Nothing reads it: no lesson floor, no seeded `ChallengeResult`
    /// rows, no effect on `TodayView.studyLesson()`. Seeding would push invented history
    /// to every device through CloudKit and inflate `ChallengeResult.totalPassed`, which
    /// gates the rating prompt. It exists so a later survey submission can be segmented by
    /// prior experience — this app ships no user identifier of any kind, so there is no
    /// join key and the answer has to travel with the row.
    static let textbookLesson      = "textbookLesson"
    /// Why they said they're learning: "travel" / "jlpt" / "work" / "culture" / "other".
    /// Recorded only, for the same segmentation reason as `textbookLesson`.
    static let goal                = "goal"
}


/// Which practice modes a lesson has opened — the honest datum behind the lesson
/// screen's "Tried / Not tried yet" status labels (design 2a). "Opened" is all it
/// records: inventing a completion state for modes that are deliberately endless
/// (Match, Practice) would be a lie with a progress bar.
///
/// A `Set` of `"lesson/mode"` strings in UserDefaults: tens of entries even for a
/// finished course, written once per first visit, and local like every other
/// unscored study trace.
enum ModeVisits {
    static func mark(lesson: Int, mode: String) {
        var set = Set(UserDefaults.standard.stringArray(forKey: Pref.modeVisits) ?? [])
        guard set.insert("\(lesson)/\(mode)").inserted else { return }
        UserDefaults.standard.set(Array(set), forKey: Pref.modeVisits)
    }

    /// The modes `lesson` has visited, as bare mode keys.
    static func all(lesson: Int) -> Set<String> {
        let prefix = "\(lesson)/"
        return Set((UserDefaults.standard.stringArray(forKey: Pref.modeVisits) ?? [])
            .filter { $0.hasPrefix(prefix) }
            .map { String($0.dropFirst(prefix.count)) })
    }
}
