import Foundation

/// The in-app feedback survey: what can be reported, from where, and the one rule about
/// when a report is sendable.
///
/// View-free on purpose, like `Intro`. The parts with consequences are the wire values,
/// the length caps and the validity gate, and keeping them out of `FeedbackView` is what
/// makes them testable without presenting a sheet.
///
/// This replaces an Airtable form opened in `SFSafariViewController`, which collected
/// nothing at all in the RN app's lifetime. A web form asks someone who is already
/// annoyed to wait for a page load, meet unfamiliar chrome, and type into a text box
/// with the app's context left behind on the other side of a browser. Every one of those
/// is a place to give up, and the empty table says they all got taken.
enum Feedback {
    /// Where the sheet was opened from.
    ///
    /// The same three values the old form's `prefill_Source` carried, kept deliberately:
    /// Settings is someone who went looking for a way to write in, `rating` is someone
    /// the app sent after a low star pick, and `hidden` is the developer testing through
    /// the Diagnostics screen. Three different populations, and a row can't be read
    /// without knowing which one it came from — a complaint the app solicited reads
    /// differently from one that was volunteered.
    ///
    /// `card` is the fourth population and the reason it isn't folded into `settings`: a
    /// report opened from the word on screen arrives already knowing which word it is
    /// about, so those rows are the ones with a resolvable `item` and they read completely
    /// differently from prose typed cold from Settings. Source is what the collection gets
    /// grouped by, so a new route needs a new value — and the rules' `source in [...]` list
    /// has to gain it in the same edit or every one of these writes is rejected.
    ///
    /// `CaseIterable` so `SurveyTests` can pin the whole set against that list.
    enum Source: String, CaseIterable {
        case settings, rating, hidden, card
    }

    /// What the report is about. Small and closed so the collection is sortable at all,
    /// and validated in the rules so a client-side typo can't invent a fifth bucket that
    /// quietly splits the data.
    ///
    /// Four buckets, because they route to four different places: `bug` to the code,
    /// `idea` to the backlog, `content` to the `minna` data pipeline (a wrong meaning or
    /// a mis-cut audio clip is a regeneration, not a code change), `other` to a human.
    /// Any finer taxonomy would be guessing on the sender's behalf.
    enum Kind: String, CaseIterable, Identifiable {
        case bug, idea, content, other

        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .bug:     return "Something's broken"
            case .idea:    return "An idea"
            case .content: return "A wrong word, meaning or sound"
            case .other:   return "Something else"
            }
        }
        var title: String { L.t(titleKey) }
        /// SF Symbols only, like every other icon in the app.
        var icon: String {
            switch self {
            case .bug:     return "ladybug"
            case .idea:    return "lightbulb"
            case .content: return "text.badge.xmark"
            case .other:   return "ellipsis.bubble"
            }
        }
    }

    /// Which part of the app a `bug` report is about — the second-level question, asked
    /// only after `Something's broken`.
    ///
    /// It exists because "it doesn't work" routes nowhere. `Context.last_screen` names the
    /// screen the sender was *standing on when they wrote in*, which is very often Settings
    /// and can never be the widget or the Watch, so the area has to be asked rather than
    /// inferred.
    ///
    /// The eight buckets are the app's surfaces as a user meets them, and each one maps to a
    /// place in the code a report can actually be taken to:
    ///
    /// - `audio` → `Pronouncer` and the bundled Kyoko clips. An area rather than a screen
    ///   because it cuts across every one of them, and it is the single most reported thing.
    /// - `kana` → the Kana tab (`Router.Tab.kana`): the chart, the five modes
    ///   `KanaQuizModeView` lists, and the stroke scoring in `KanaWriteView`.
    /// - `lesson` → the Lessons tab: the list, its search, and the four practice modes in
    ///   `SelectModeView`'s first section.
    /// - `challenge` → the scored ladder only (`ChallengeView`, `Challenge`, the gating and
    ///   the stars). Split from `lesson` because the bug classes don't overlap: a wrong
    ///   score or a rung that won't unlock is nothing like a card that won't flip.
    /// - `today` → the Today tab and the widget that shares its deck (`TodayShared`,
    ///   `TodayWidget`). Named together because they are one feature to a user and the
    ///   widget is a surface `last_screen` cannot ever report.
    /// - `watch` → the Watch app and its complication.
    /// - `purchase` → `Store`, `PaywallView`, restores and prices.
    /// - `other` → so the list is never a dead end. Everything not above (Settings,
    ///   appearance, ads, the intro) lands here, and the prose says which.
    ///
    /// Labels are what the user sees on the screen in question, never the internal name —
    /// "Sound and pronunciation", not `Pronouncer`. Three of them are deliberately the exact
    /// tab names already in `UIStrings.json`: the tab is how the user refers to that part of
    /// the app, and re-wording it here would invent a second name for one thing.
    enum Area: String, CaseIterable, Identifiable {
        case audio, kana, lesson, challenge, today, watch, purchase, other

        var id: String { rawValue }
        var titleKey: String {
            switch self {
            case .audio:     return "Sound and pronunciation"
            case .kana:      return "Kana"
            case .lesson:    return "Lessons"
            case .challenge: return "Challenge"
            case .today:     return "Today or the widget"
            case .watch:     return "Apple Watch"
            case .purchase:  return "Buying or unlocking"
            case .other:     return "Another part of the app"
            }
        }
        var title: String { L.t(titleKey) }
        /// SF Symbols only, like every other icon in the app. Three of these are the tab
        /// bar's own symbols, for the same reason three of the labels are the tab names.
        var icon: String {
            switch self {
            case .audio:     return "speaker.wave.2"
            case .kana:      return "character.book.closed"
            case .lesson:    return "list.bullet"
            case .challenge: return "flag.checkered"
            case .today:     return "sun.max"
            case .watch:     return "applewatch"
            case .purchase:  return "creditcard"
            case .other:     return "ellipsis"
            }
        }
    }

    /// The entry a `content` report is about — a wrong meaning, reading or clip.
    ///
    /// A lesson plus the romaji that names the word inside it, which together spell
    /// `Vocab.id` (`"<lesson>/<romaji>"`). Romaji and not the translation on purpose: the
    /// translation is whatever `Pref.translationLanguage` was set to, and that language is
    /// already in the survey context — so the reader can resolve the entry in the sender's
    /// own language, while the stored value keeps meaning the same thing in all seventeen.
    ///
    /// `lesson == 0` means the item is not a lesson word at all: the kana flashcards report
    /// their syllable this way, where the romaji alone identifies it and `last_screen` says
    /// which table it came from.
    ///
    /// Only ever filled in by the flag on a practice screen, which knows the card on screen.
    /// The sheet itself has no word field — see `FeedbackView`.
    struct Item: Equatable, Hashable {
        let lesson: Int
        let romaji: String
    }

    /// Characters the sheet accepts in the message.
    ///
    /// 2000 is about two screens of typing — room for steps to reproduce plus the words
    /// involved, and past the point where anyone keeps typing into a phone. The ceiling
    /// exists because the field is free text reaching a server: without one, a pasted
    /// crash log or a stuck key writes a document that costs money to store and can't be
    /// read anyway. The rules allow more than this (see `firestore.rules`) — Swift counts
    /// grapheme clusters and Firestore's `size()` counts characters, so an emoji-heavy
    /// message can pass here and exceed the same number there. The rule is the safety
    /// bound; this is the cap.
    static let messageLimit = 2000

    /// 254 is the longest address SMTP will carry (RFC 5321), so anything longer is not
    /// a truncated address, it's a paste into the wrong field.
    static let emailLimit = 254

    /// The longest romaji in the bundled data is 40 characters (a sentence entry in lesson
    /// 47, `"shimasu [oto/koe ga~]…"`), so 60 is headroom for a regeneration that adds a
    /// longer one rather than a limit anyone can reach. The rules cap the same field, and a
    /// value over the cap would reject the whole document instead of the one field.
    static let itemLimit = 60
}

/// What the sheet is holding, and the single place it becomes a submission.
///
/// The gate is deliberately one condition: **a non-empty message**. Nothing else can
/// stop a send.
///
/// - `email` is optional and never validated. Someone who wants no reply leaves it
///   blank, and someone who fat-fingers their address still gets their report through —
///   a rejected form is a lost bug, and a typo'd address costs only the reply.
/// - `kind` is optional and unset by default. Preselecting a bucket would put a claim in
///   the row that nobody made, and *requiring* one would be a second gate on a form
///   whose whole point is that it's easier to use than the web form it replaces. Unpicked
///   goes to the wire as `other`, which is exactly what it means.
/// - `area` and `item` are the two second-level answers, and neither gates anything
///   either. They are the difference between a report that routes to a file and one that
///   routes to a guess, but a sender who can't answer them still has something to say.
struct FeedbackDraft: Equatable {
    var kind: Feedback.Kind?
    /// Which part of the app is broken. Only meaningful for `.bug` — see `submittedArea`.
    var area: Feedback.Area?
    /// The word being reported, when the report was opened from the card showing it. The
    /// sheet never sets this: the flag on a practice screen is the only thing that does.
    var item: Feedback.Item?
    var message = ""
    var email = ""
    /// 1…5 when the sheet was opened from the star row, 0 otherwise. Carried so a
    /// complaint can be read next to the rating that produced it — the star row's own
    /// number is the only thing Apple's review sheet would never have told us.
    var stars = 0

    /// Whitespace-only is empty. Otherwise "   " sends a document with nothing in it and
    /// the sender believes they've reported something.
    var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The only thing that gates Send. Not the email, not the kind, and not either of the
    /// two follow-up answers.
    var isValid: Bool { !trimmedMessage.isEmpty }

    /// The three second-level fields as they go to the wire, each scoped to the bucket it
    /// belongs to.
    ///
    /// The scoping is here rather than in the view because it is the part with consequences:
    /// the follow-up sections appear and disappear as the kind is re-picked, and a sender who
    /// answers "which part is broken", changes their mind to `An idea` and sends would
    /// otherwise ship an `area` that contradicts the `kind` on the same row. Reading a
    /// collection where that can happen means never trusting either field.
    ///
    /// Empty rather than absent, in all three cases: the rules close the key set with
    /// `hasAll`, so every row carries every field and "not answered" has to be a value.
    var submittedArea: String { kind == .bug ? (area?.rawValue ?? "") : "" }

    /// The lesson as its own int beside `submittedItem`, which already encodes it —
    /// deliberately redundant, see `Survey.Feedback.lesson`.
    var submittedLesson: Int { kind == .content ? (item?.lesson ?? 0) : 0 }

    /// Truncated for the same reason `message` is: the rules cap the field, and a cap that
    /// rejects the document loses the whole report over one long romaji.
    var submittedItem: String {
        guard kind == .content, let romaji = item?.romaji else { return "" }
        return String(romaji.prefix(Feedback.itemLimit))
    }

    /// The document to submit, or nil if there's nothing to say.
    ///
    /// Truncation happens here rather than in the text field: a cap enforced by refusing
    /// keystrokes is a cap the sender fights, and one enforced silently at the boundary
    /// keeps everything they actually typed up to the limit.
    func submission(source: Feedback.Source) -> Survey.Feedback? {
        guard isValid else { return nil }
        return Survey.Feedback(kind: (kind ?? .other).rawValue,
                               area: submittedArea,
                               message: String(trimmedMessage.prefix(Feedback.messageLimit)),
                               email: String(email.trimmingCharacters(in: .whitespacesAndNewlines)
                                                  .prefix(Feedback.emailLimit)),
                               source: source.rawValue,
                               stars: stars,
                               lesson: submittedLesson,
                               item: submittedItem)
    }

    /// Analytics params for the funnel. Never the message or the address — `Track` is the
    /// aggregate seam, and content belongs only in the collection the sender chose to
    /// write to. Length stands in for it, the same way `query_length` does for search.
    /// `area` and `lesson` ride along because they're buckets, which is what an event stream
    /// counts well: "half of all bug reports are about audio" is an answer no single row
    /// gives. The romaji does not — `has_item` is its aggregate half, like `has_email`.
    func trackParams(source: Feedback.Source) -> [String: Any] {
        ["source": source.rawValue,
         "kind": (kind ?? .other).rawValue,
         "area": submittedArea,
         "lesson": submittedLesson,
         "has_item": !submittedItem.isEmpty,
         "message_length": trimmedMessage.count,
         "has_email": !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
         "stars": stars]
    }
}
