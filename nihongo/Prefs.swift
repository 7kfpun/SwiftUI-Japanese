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
    /// Train's word order — false (random) by default; Learn's `ordered` key defaults
    /// the other way, so the two modes deliberately don't share a switch.
    static let trainOrdered        = "trainOrdered"
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
