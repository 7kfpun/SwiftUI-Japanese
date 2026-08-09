import Foundation

/// The first-launch intro: five cards that show what the app does and ask the three
/// questions worth asking before anyone has used anything.
///
/// Everything in this file is view-free on purpose. The only parts of the intro with
/// consequences are the answer→preference mapping and the landing-tab decision, and
/// keeping them out of `IntroView` is what makes them testable without presenting a
/// cover, a pronouncer or a model container.
enum Intro {
    /// The five cards, in paging order — shallow → deep, the same instinct as
    /// `SelectModeView`'s rows: what a word looks like, then the syllabary that's free
    /// in full, then the four untested practice modes, then the scored ladder, then the
    /// daily habit that feeds it.
    ///
    /// The raw value is the 1-based card number the analytics events carry, so
    /// `intro_card` / `intro_skip` line up with "card 3" in a conversation about the flow.
    enum Card: Int, CaseIterable, Identifiable {
        case meanings = 1, kana, modes, challenge, today
        var id: Int { rawValue }
    }

    /// How much kana the learner says they already read.
    ///
    /// The one intro answer with a behavioural consumer — see `landingTab(kana:)`. The
    /// raw values are what `Pref.knowsKana` stores, so they're the wire format for both
    /// the preference and the survey field and must not be renamed casually.
    ///
    /// `notYet` rather than `none` because this type is used as an `Optional`
    /// (unanswered), and `.none` on an optional means something else entirely.
    enum KanaLevel: String, CaseIterable, Identifiable {
        case notYet = "none", hiragana, both

        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .notYet:   return "Not yet"
            case .hiragana: return "Hiragana only"
            case .both:     return "Both, comfortably"
            }
        }
        var title: String { L.t(titleKey) }
    }

    /// Why they're learning. Recorded only — nothing in the app reads it.
    enum Goal: String, CaseIterable, Identifiable {
        case travel, jlpt, work, culture, other

        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .travel:  return "Travel"
            case .jlpt:    return "JLPT"
            case .work:    return "Work"
            case .culture: return "Culture"
            case .other:   return "Other"
            }
        }
        var title: String { L.t(titleKey) }
        /// SF Symbols only, like every other icon in the app.
        var icon: String {
            switch self {
            case .travel:  return "airplane"
            case .jlpt:    return "checkmark.seal"
            case .work:    return "briefcase"
            case .culture: return "theatermasks"
            case .other:   return "ellipsis"
            }
        }
    }

    /// The four Learn modes card 3 previews, in `SelectModeView`'s shallow → deep order.
    ///
    /// Titles, subtitles and icons are the *same* strings and symbols the real mode rows
    /// use — deliberately not intro-specific copy, so the tour teaches the labels the
    /// learner will meet again a tap later. Nothing new to translate here.
    enum Mode: String, CaseIterable, Identifiable {
        case vocabList, flashcards, train, learn

        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .vocabList:  return "Vocab List"
            case .flashcards: return "Flashcards"
            case .train:      return "Train"
            case .learn:      return "Learn"
            }
        }
        var subtitleKey: String {
            switch self {
            case .vocabList:  return "Browse & hear all words"
            case .flashcards: return "Swipe right if you know it"
            case .train:      return "Swipe to the right answer"
            case .learn:      return "Rebuild the reading from tiles"
            }
        }
        var icon: String {
            switch self {
            case .vocabList:  return "list.bullet"
            case .flashcards: return "rectangle.on.rectangle.angled"
            case .train:      return "arrow.left.arrow.right"
            case .learn:      return "square.grid.2x2"
            }
        }
        var title: String { L.t(titleKey) }
        var subtitle: String { L.t(subtitleKey) }
    }

    /// Where `Start learning →` lands.
    ///
    /// Someone who can't read kana yet has little use for a Today card made of it, and
    /// Kana is the one part of the app that's free in full — so they start there.
    /// Everyone else keeps Today, the app's normal landing tab, and so does anyone who
    /// skipped the question: an unanswered question is not a "no".
    static func landingTab(kana: KanaLevel?) -> Router.Tab {
        kana == .notYet ? .kana : .today
    }
}

/// The three answers the intro collects, and the single place they get written.
///
/// Each one is optional because Skip sits on every card: an unanswered question writes
/// no preference at all, rather than persisting a guess made on the learner's behalf.
/// Only `kana` changes how the app behaves — the other two are recorded so a later
/// survey submission can be segmented by prior experience and motive. This app ships no
/// user identifier of any kind, so there is no key to join a second submission back on.
struct IntroAnswers: Equatable {
    var kana: Intro.KanaLevel?
    /// 0 = never studied Minna no Nihongo, 1…50 = the lesson they say they reached.
    ///
    /// Recorded only. Deliberately no lesson floor, no seeded `ChallengeResult` rows and
    /// no effect on `TodayView.studyLesson()`: seeding would push invented history to
    /// every one of the learner's devices through CloudKit and inflate
    /// `ChallengeResult.totalPassed`, which is what gates the rating prompt.
    var textbookLesson: Int?
    var goal: Intro.Goal?

    /// Reported instead of dropping the param, so every `intro_done` event carries the
    /// same three keys and a funnel can count "asked but not answered" rather than
    /// finding a param missing.
    static let unanswered = "unanswered"
    static let unansweredLesson = -1

    /// Whether the run answered everything — what a later survey submission would
    /// require, since a partial row can't be told from a "0" answer after the fact.
    var isComplete: Bool { kana != nil && textbookLesson != nil && goal != nil }

    /// The survey document for a completed run, or `nil` for a partial one.
    ///
    /// Returning `nil` rather than filling blanks is the whole gate: `survey_intro` has a
    /// closed schema with no nullable fields (the security rules reject any document that
    /// isn't exactly the ten expected keys), and a half-answered row would be
    /// indistinguishable from a deliberate "0" once it's in the collection. How far people
    /// get before abandoning is counted in Analytics instead, where counting belongs.
    ///
    /// The two languages come from the caller because they're settings, not answers — one
    /// of them (`vocabLanguage`) is what card 1 may just have changed.
    func submission(vocabLanguage: String, appLanguage: String) -> Survey.Intro? {
        guard let kana, let textbookLesson, let goal else { return nil }
        return Survey.Intro(knowsKana: kana.rawValue,
                            textbookLesson: textbookLesson,
                            goal: goal.rawValue,
                            vocabLanguage: vocabLanguage,
                            appLanguage: appLanguage)
    }

    /// Mark the intro seen and persist whatever was answered.
    ///
    /// `introAnswered` goes down even on a skip: the flag gates the cover, and asking
    /// again on the next launch is how a first-run tour turns into a nag.
    func save(to defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Pref.introAnswered)
        if let kana { defaults.set(kana.rawValue, forKey: Pref.knowsKana) }
        if let textbookLesson { defaults.set(textbookLesson, forKey: Pref.textbookLesson) }
        if let goal { defaults.set(goal.rawValue, forKey: Pref.goal) }
    }

    /// Analytics params for `intro_done`. snake_case to match the rest of the event
    /// catalog (`is_premium`, `query_length`) rather than the camelCase `Pref` keys.
    var trackParams: [String: Any] {
        ["knows_kana": kana?.rawValue ?? Self.unanswered,
         "textbook_lesson": textbookLesson ?? Self.unansweredLesson,
         "goal": goal?.rawValue ?? Self.unanswered]
    }
}
