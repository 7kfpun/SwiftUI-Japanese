import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftData)
import SwiftData
#endif
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

/// Survey submissions — the one place in the app that writes to a server.
///
/// Everything else here is on-device or in the user's own iCloud: purchases are
/// verified locally by StoreKit, progress lives in a CloudKit *private* database
/// nobody but the user can read, and analytics goes to Firebase as aggregates.
/// A survey answer is different in kind: it's content the user chose to send us,
/// so it goes somewhere we can actually read it back.
///
/// Write-only by construction. The security rules (`firestore.rules`) deny read,
/// update and delete outright and validate the whole document shape server-side,
/// so a decompiled build yields no way to read other people's answers and no way
/// to overwrite them — only to append one well-formed row. Attestation that the
/// caller *is* this app comes from App Check (see `AppBootstrap`).
///
/// Deliberately no user identifier of any kind. The app ships without App
/// Tracking Transparency and its privacy manifest declares no collected
/// identifiers; Anonymous Auth would mint a persistent UID per install and undo
/// that. The cost is that two submissions from one person can't be joined, which
/// is why a later NPS submission carries copies of these answers rather than a
/// foreign key.
enum Survey {
    /// Bumped when a field is added or removed, so whatever reads these rows can tell a
    /// missing field from an unanswered one. Rules require it present.
    ///
    /// 2: every collection now carries the shared `Context` below, and `survey_intro`
    /// stopped naming the two languages itself (the context already reports them).
    ///
    /// 3: a third collection (`survey_rating`, one row per star tap) plus seven context
    /// fields describing *where* the sender was — `last_screen`, `text_size`,
    /// `appearance`, `shown_fields`, `kana_answered` — and *who* they said they were at
    /// first launch: `knows_kana`, `goal`, `textbook_lesson`. The three intro answers now
    /// ride on every row, which is what makes feedback segmentable without a join key.
    ///
    /// 4: `survey_feedback` asks a second question and carries the answer — `area` for a bug
    /// report, `lesson` + `item` for a wrong word — plus a fourth `source`, `card`, for the
    /// reports opened from the flag on a practice screen. A v3 feedback row is not a row
    /// whose sender declined to answer: it is one from a build that never asked.
    static let schemaVersion = 4

    /// The most recent screen name, for `Context.last_screen`.
    ///
    /// Deliberately in-memory only: a screen name persisted from a previous launch would
    /// be worse than nothing, since it names somewhere the sender isn't. `""` until the
    /// first screen of this session is recorded, which is exactly what the rules allow.
    ///
    /// Recorded and read on the main actor in practice — `Track.screen` is called from
    /// `onAppear`, and `Context` is built from a view or a sheet callback — so this needs
    /// no locking, the same assumption `Track`'s own cached `isPremium` makes.
    private static var screen = ""

    /// Remember the screen just shown. Call it from `Track.screen`, which every screen in
    /// the app already reports through — one call site, no per-view bookkeeping.
    ///
    /// It lives here rather than in `Track` because a breadcrumb kept for survey rows is
    /// this file's business: it is not sent anywhere on its own, it ignores the analytics
    /// opt-out exactly as the rest of `Survey` does, and `Track` may not log at all (a
    /// clone with no `GoogleService-Info.plist`) while a survey row still wants the field.
    static func recordScreen(_ name: String) {
        screen = String(name.prefix(40))   // the rules cap it; truncating beats a rejection
    }

    /// Where the sender was, or `""` if no screen has been recorded this session.
    static var lastScreen: String { screen }

    /// One completed onboarding run. Skips and partial runs submit nothing — the
    /// drop-off shape is counted in Analytics instead (`intro_skip`), which is
    /// what lets this schema stay closed with no nullable fields or sentinels.
    ///
    /// Only the three *answers* live here. The languages the answers were given in, the
    /// build, the device and everything else comes from `Context` — see its note on why
    /// every collection carries the identical map.
    struct Intro {
        let knowsKana: String       // none | hiragana | both
        let textbookLesson: Int     // 0 = never studied, else 1...50
        let goal: String            // travel | jlpt | work | culture | other
    }

    /// One feedback submission from the in-app sheet (`FeedbackView`).
    ///
    /// Free text, so unlike `Intro` this can't be a closed set of enums — which is
    /// exactly why `kind` exists beside `message`. A bucket the sender picked is worth
    /// more than any classification of the prose after the fact, and it's the field that
    /// makes the collection sortable at all.
    ///
    /// Three of these five follow-up fields are unanswerable for most rows, and all three are
    /// present anyway: the rules use `hasAll`, so a closed schema with no nullable fields is
    /// the price of the guard that keeps junk out. "Not asked" and "asked and declined" are
    /// both the empty value, and `v` is what distinguishes them — see `schemaVersion`.
    struct Feedback {
        let kind: String        // bug | idea | content | other
        /// Which part of the app a `bug` report is about, `""` for every other kind and for
        /// a bug report whose sender skipped the question. `Feedback.Area`'s raw values.
        let area: String
        let message: String     // required, non-empty, capped client-side
        let email: String       // "" when not given — optional, and never gates sending
        let source: String      // settings | rating | hidden | card
        /// 1…5 when the sheet was opened from the star row, 0 otherwise. Present either
        /// way: a closed schema with no nullable fields is what lets the rules use
        /// `hasAll`, and "no rating" is honestly expressed as 0.
        let stars: Int
        /// 1…50, or 0 when no word is attached — and also 0 for a kana item, which belongs
        /// to no lesson. Redundant against `item`, which encodes it, and kept anyway: the
        /// console is a document browser, and sorting a pile of content reports by lesson is
        /// the first thing a reader wants that a `"2/tsukue"` string cannot give them.
        let lesson: Int
        /// The word's romaji, `""` when none is attached. With `lesson` it reconstructs
        /// `Vocab.id`. Deliberately not the translation: that follows the sender's
        /// `vocab_language`, which is already in the context, so the reader can resolve the
        /// entry in their language while the stored value means one thing in all seventeen.
        let item: String
    }

    /// One star tap, written the moment it happens.
    ///
    /// A separate collection from `Feedback` rather than a `stars`-only feedback row, and
    /// the reason is a constraint that would otherwise have to be surrendered:
    /// `survey_feedback` requires `message` to be non-empty server-side, and a rating has
    /// no message, so sharing the collection would mean relaxing the guard on the one
    /// field that matters most — permanently, for every future row. The cardinalities
    /// differ wildly too (a row per tap versus a row per person who writes prose), and
    /// there is no join key by design, so merging wouldn't buy correlation either.
    ///
    /// Written *before* the 4-vs-below branch in `ChallengeView.routeRating`, which is the
    /// whole point of the type: 4★ and up hands off to Apple's review sheet, which reports
    /// nothing back, and a 1-3★ who then abandons the feedback form used to vanish
    /// entirely. Both are now captured. Consequence when reading results: a low rater who
    /// *also* writes feedback appears in both collections, so the two must never be summed
    /// as "responses" — `survey_rating` is the denominator.
    struct Rating {
        let stars: Int          // 1…5. Never 0: no answer writes no row at all.
    }

    /// The diagnostic context every submission carries, identically, in every collection.
    ///
    /// A survey row arrives with no way to ask a follow-up question: there is no
    /// identifier, no session and no reply channel unless the sender volunteered an
    /// email. So whatever is needed to act on it has to already be in the row. "The
    /// audio is broken" is unactionable; "the audio is broken, iPhone 12 mini, iOS 26.1,
    /// app 2.1.0 (143), sound off" is a five-second answer.
    ///
    /// **Device characteristics, never a device identity.** Hardware model, OS version
    /// and language describe the machine a bug happened on; none of them is unique, none
    /// survives as a handle on a person, and there is deliberately nothing here — no
    /// IDFA, no IDFV, no vendor UUID, no minted install ID — that could join two rows
    /// back to one human. See this file's own note on why that line matters.
    ///
    /// Five of these values can't be reached from here: `Store` is a `@MainActor`
    /// observable owned by the app scene, the two counts need a `ModelContext`, and the
    /// text size and appearance are UIKit reads that are only valid on the main thread.
    /// They're constructor parameters rather than a lookup through some global, so this
    /// type stays a plain value a test can build and assert on off the main actor —
    /// `init(store:modelContext:)` below is the one place real submissions resolve them.
    ///
    /// Everything else is read inside `fields` straight from `UserDefaults`, so it reports
    /// a setting the sender may have changed seconds ago on the very screen they're
    /// complaining about.
    struct Context {
        let isPremium: Bool
        let tier: String
        let challengesPassed: Int
        let kanaAnswered: Int
        /// Short Dynamic Type category — see `AppInfo.textSize`.
        let textSize: String
        /// `"light"` or `"dark"` — the rules accept nothing else, see `AppInfo.appearance`.
        let appearance: String

        init(isPremium: Bool, tier: String, challengesPassed: Int,
             kanaAnswered: Int, textSize: String, appearance: String) {
            self.isPremium = isPremium
            self.tier = tier
            self.challengesPassed = challengesPassed
            self.kanaAnswered = kanaAnswered
            self.textSize = textSize
            self.appearance = appearance
        }

        /// The map, minus `at` — that one is the server's to stamp (see `submit`).
        ///
        /// Every key here is in the rules' `hasOnly`/`hasAll` list for *both* collections.
        /// Adding one without republishing the rules rejects every write in the app, and
        /// the rejection is invisible except as a console line, so `SurveyTests` pins the
        /// key set against a transcription of the published list.
        var fields: [String: Any] {
            [
                // The field exists so an Android client could one day share the
                // collection rather than fork the schema. Rules pin it to 'iOS'.
                "platform": "iOS",
                "app_version": AppInfo.version,
                "os": AppInfo.os,
                "device": AppInfo.device,
                "os_language": AppInfo.osLanguage,
                // The two settings that decide what's on screen.
                "app_language": L.current,
                "vocab_language": AppInfo.setting(Pref.translationLanguage,
                                                  default: VocabStore.deviceDefaultLanguage),
                // Store region, which decides pricing, product availability and whether
                // the paywall a complaint is about could even have loaded.
                "region": AppInfo.region,
                "is_premium": isPremium,
                "tier": tier,
                // How far in the sender actually is, measured rather than claimed. The
                // difference between "confusing" from someone on rung 2 and from someone
                // on rung 40 is the whole content of the report.
                "challenges_passed": challengesPassed,
                // The other half of "how far in are they": the Kana tab is free in full,
                // so a sender with 0 rungs and 300 kana answers is a heavy user of a part
                // of the app the challenge count says they never opened. Row count, which
                // is one row per distinct kana (`KanaResult.record` upserts), so it reads
                // as coverage rather than attempts.
                "kana_answered": kanaAnswered,
                // First question to ask about any report that audio is missing or
                // unwanted, and the app's own toggle is the likeliest cause.
                "sound_on": AppInfo.setting(Pref.soundOn, default: true),
                // Why there's no analytics trail beside this row. Without it, a row from
                // an opted-out device looks like a session that never happened.
                "analytics_excluded": Track.isExcluded,
                // Which of the four card fields are visible — see `AppInfo.shownFields`
                // for the encoding. "" is legitimate: all four hidden, which is itself
                // the bug report.
                "shown_fields": AppInfo.shownFields,
                // Most "the text is cut off" reports are an accessibility text size.
                // The *stored* value, never `AppInfo.textSize` again: that accessor
                // touches `UIApplication` and is main-actor for it, while `fields` is
                // documented as legal off the main actor (tests build a Context there).
                // Reading UIKit here made the stored property dead and the doc a lie.
                "text_size": textSize,
                // `Theme` deliberately swaps the surface/canvas roles between light and
                // dark, so a contrast complaint is meaningless without knowing which.
                "appearance": appearance,
                // The highest-value field here — see `Survey.recordScreen`.
                "last_screen": Survey.lastScreen,
                // The three first-launch answers, for segmentation — whether beginners and
                // returning learners complain about different things is what makes
                // feedback actionable in bulk rather than one row at a time. These
                // duplicate the answers inside a `survey_intro` row; accepted, because one
                // context shared by every collection beats a harmless repeat. Read from
                // `Pref` with the same sentinels `IntroAnswers` reports to Analytics, so
                // "skipped the question" stays distinguishable from a real answer.
                "knows_kana": AppInfo.setting(Pref.knowsKana, default: IntroAnswers.unanswered),
                "goal": AppInfo.setting(Pref.goal, default: IntroAnswers.unanswered),
                "textbook_lesson": AppInfo.setting(Pref.textbookLesson,
                                                   default: IntroAnswers.unansweredLesson),
                "debug": AppInfo.isDebugBuild,
                "v": Survey.schemaVersion,
            ]
        }

        /// The full key set, including the `at` that `submit` adds — the invariant the
        /// rules enforce and `SurveyTests` guards.
        static let keys: Set<String> = [
            "platform", "app_version", "os", "device", "os_language",
            "app_language", "vocab_language", "region",
            "is_premium", "tier", "challenges_passed", "kana_answered",
            "sound_on", "analytics_excluded",
            "shown_fields", "text_size", "appearance", "last_screen",
            "knows_kana", "goal", "textbook_lesson",
            "debug", "v", "at",
        ]
    }

    /// Field names are snake_case to match the Analytics param convention
    /// (`is_premium`, `query_length`) rather than the camelCase `Pref` keys —
    /// these two datasets get read side by side, and the rules' `hasOnly` list
    /// has to match this map exactly or the write is rejected.
    /// `survey_intro` adds no keys of its own any more: the three answers are context
    /// fields now, carried by every collection. The merge stays because it decides which
    /// *value* wins — the answers from this run rather than a re-read of `Pref`, so the row
    /// can't depend on `IntroAnswers.save()` having landed first. The key set is identical
    /// either way, which is why the rules take `hasExactly(data, [])` here.
    static func submit(_ intro: Intro, context: Context) {
        submit(collection: "survey_intro", fields: context.fields.merging([
            "knows_kana": intro.knowsKana,
            "textbook_lesson": intro.textbookLesson,
            "goal": intro.goal,
        ]) { _, answer in answer })
    }

    /// One row per star tap. See `Rating` on why this isn't a `survey_feedback` row.
    static func submit(_ rating: Rating, context: Context) {
        submit(collection: "survey_rating", fields: context.fields.merging([
            "stars": rating.stars,
        ]) { _, answer in answer })
    }

    static func submit(_ feedback: Feedback, context: Context) {
        submit(collection: "survey_feedback", fields: context.fields.merging([
            "kind": feedback.kind,
            "area": feedback.area,
            "message": feedback.message,
            "email": feedback.email,
            "source": feedback.source,
            "stars": feedback.stars,
            "lesson": feedback.lesson,
            "item": feedback.item,
        ]) { _, answer in answer })
    }

    /// The actual write. No-op unless Firestore is linked *and* Firebase is
    /// configured (a fresh open-source clone has no `GoogleService-Info.plist`),
    /// mirroring how `Track` and `BannerAd` stay silent in that build.
    private static func submit(collection: String, fields: [String: Any]) {
        // Deliberately NOT gated on `Pref.analyticsExcluded` or `#if DEBUG`, unlike
        // everything in `Track`. That switch governs passive telemetry — events the
        // user never asked to send. A survey answer is the opposite: content someone
        // deliberately typed and submitted, and silently discarding it would be a
        // worse betrayal than sending it. Suppressing DEBUG would also make this path
        // untestable outside TestFlight, and an unexercised write path is one that
        // breaks unnoticed.
        //
        // Consequence: development submissions land in the same collection as real
        // ones and nothing distinguishes them.
        #if canImport(FirebaseFirestore)
        guard FirebaseApp.app() != nil else { return }
        var payload = fields
        // Server-stamped, not device-claimed: clocks lie, and Firestore's offline
        // queue can land this write hours after the tap that made it. The rules
        // require `at == request.time`, so this has to be the sentinel.
        payload["at"] = FieldValue.serverTimestamp()

        #if DEBUG
        print("survey: submitting to \(collection) — \(payload.keys.sorted().joined(separator: ","))")
        #endif
        Firestore.firestore().collection(collection).addDocument(data: payload) { error in
            // A rules rejection arrives *here*, not at the call: offline
            // persistence applies the write locally first and only learns it was
            // refused on flush. Swallowing this would make a misconfigured rule
            // or a missing App Check token look exactly like success.
            if let error {
                // The print is the DEBUG-visible half: `Track` still honours the
                // analytics opt-out, because a failure *count* is telemetry even
                // though the answer it failed to send isn't.
                print("survey: \(collection) write failed — \(error.localizedDescription)")
                Track.event("survey_failed", ["collection": collection])
            } else {
                #if DEBUG
                print("survey: \(collection) write acknowledged by the server")
                #endif
            }
        }
        #endif
    }
}

#if canImport(SwiftData)
extension Survey.Context {
    /// The one-liner every call site actually uses.
    ///
    /// Still an injection rather than a lookup — every value is handed in, and the
    /// primitive initializer above remains the only way the type is built. This exists
    /// so four call sites don't each spell out the same reads, and so the awkward
    /// dependencies (`@MainActor` store, two SwiftData fetches, two main-thread-only UIKit
    /// reads) are named in exactly one place.
    ///
    /// `@MainActor` is what makes `AppInfo.textSize` / `AppInfo.appearance` legal here:
    /// both go through `UIApplication`, and a `Context` built off the main actor (as a test
    /// does) must not touch UIKit at all.
    @MainActor init(store: Store, modelContext: ModelContext) {
        self.init(isPremium: store.isPremium,
                  tier: store.tier,
                  challengesPassed: ChallengeResult.totalPassed(context: modelContext),
                  // Count, not fetch: the row set is only needed for its size, and this is
                  // on the path of a tap the user is waiting on.
                  kanaAnswered: (try? modelContext.fetchCount(FetchDescriptor<KanaResult>())) ?? 0,
                  textSize: AppInfo.textSize,
                  appearance: AppInfo.appearance)
    }
}
#endif

/// Build, OS and device strings for anything that reports about itself.
enum AppInfo {
    /// e.g. `"2.1.0 (143)"` — marketing version plus build number, since a
    /// TestFlight bug report is usually about a specific build, not a version.
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    /// True for a Debug build — the field that tells a development submission from a real
    /// one, since `Survey.submit` deliberately writes both (see its note).
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    /// e.g. `"iOS 26.1"`.
    static var os: String {
        #if canImport(UIKit)
        return "iOS " + ProcessInfo.processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "")
            .components(separatedBy: " ").first!
        #else
        return "unknown"
        #endif
    }

    /// The hardware model identifier, e.g. `"iPhone17,1"`.
    ///
    /// Deliberately the model code and not a marketing name. Mapping codes to
    /// "iPhone 16 Pro" needs a table that is wrong every September, and the reports this
    /// rides along with are about screen size, safe-area shape and CPU class — all of
    /// which the code names precisely and the marketing string only implies.
    ///
    /// A *characteristic*, not an identifier: every unit of a model returns the same
    /// string, so it can't single anybody out and doesn't touch the promise in this
    /// file's own header. `identifierForVendor` would, which is why it isn't here.
    ///
    /// `hw.machine` reports the host CPU on the Simulator (`arm64`), which would make
    /// every development row indistinguishable, so the Simulator's own model variable
    /// wins when it's set.
    static var device: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &bytes, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: bytes)
    }

    /// The device's preferred language as a BCP-47 tag, e.g. `"en-GB"`.
    ///
    /// Neither of the app's two language settings: this is what iOS itself is running in,
    /// which is what a report about a system keyboard, a date format or a VoiceOver
    /// announcement is actually about.
    static var osLanguage: String {
        Locale.preferredLanguages.first ?? "unknown"
    }

    /// The device region, e.g. `"GB"` — a store/formatting characteristic, not a location.
    /// Nothing here reads Core Location and no permission is involved.
    static var region: String {
        Locale.current.region?.identifier ?? "unknown"
    }

    /// Which of the four card fields are switched on, comma-joined in one fixed order:
    /// `"kanji,kana,romaji,translation"`, down to `""` when all four are hidden.
    ///
    /// A single string in a canonical order rather than four boolean fields or a nested
    /// map. The rules close the key set, so four fields would be four more things that
    /// must stay in step with a published ruleset for one answer; a map can't be grouped or
    /// filtered in the console; and a fixed order means two senders with the same
    /// configuration produce the identical string instead of two spellings of it.
    ///
    /// The order is the card's own top-to-bottom order, the same one `CardOptionsBar`
    /// draws, so the value reads like the card the sender was looking at.
    ///
    /// All four default to `true` (`@AppStorage(Pref.kanjiShown) private var showKanji =
    /// true` and friends), which is why every read passes `default: true` — see
    /// `setting(_:default:)` on why that argument is load-bearing.
    static var shownFields: String {
        let fields = [("kanji", Pref.kanjiShown), ("kana", Pref.kanaShown),
                      ("romaji", Pref.romajiShown), ("translation", Pref.translationShown)]
        return fields.filter { setting($0.1, default: true) }.map(\.0).joined(separator: ",")
    }

    /// The Dynamic Type category, shortened: `"XS"`…`"XXXL"`, or `"AX1"`…`"AX5"` for the
    /// five accessibility sizes.
    ///
    /// Shortened rather than raw, because the raw values are
    /// `UICTContentSizeCategoryAccessibilityXXXL` — 40 characters of prefix that say
    /// nothing, in a field the rules cap. `AX1`–`AX5` is how Apple's own accessibility
    /// documentation numbers those five, so the short form is the readable one.
    ///
    /// Read from `UIApplication` rather than a trait collection: this is the app-level
    /// setting, it accounts for an app-level override, and it doesn't depend on being
    /// inside a view update to be meaningful. Main actor for exactly that reason.
    @MainActor static var textSize: String {
        #if canImport(UIKit)
        switch UIApplication.shared.preferredContentSizeCategory {
        case .extraSmall:                        return "XS"
        case .small:                             return "S"
        case .medium:                            return "M"
        case .large:                             return "L"
        case .extraLarge:                        return "XL"
        case .extraExtraLarge:                   return "XXL"
        case .extraExtraExtraLarge:              return "XXXL"
        case .accessibilityMedium:               return "AX1"
        case .accessibilityLarge:                return "AX2"
        case .accessibilityExtraLarge:           return "AX3"
        case .accessibilityExtraExtraLarge:      return "AX4"
        case .accessibilityExtraExtraExtraLarge: return "AX5"
        default:                                 return "unknown"
        }
        #else
        return "unknown"
        #endif
    }

    /// `"light"` or `"dark"` — never anything else, because the rules pin the field to
    /// those two and a third value would reject the whole write.
    ///
    /// Taken from the foreground window's traits, which is the appearance actually on
    /// screen: it reflects a `preferredColorScheme` override the app might apply, where
    /// reading the raw system setting would not. `.unspecified` (no window yet, or a
    /// trait collection consulted outside a view update) resolves to `"light"`, which is
    /// what UIKit itself renders for an unspecified style.
    @MainActor static var appearance: String {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let style = scene?.keyWindow?.traitCollection.userInterfaceStyle
            ?? UITraitCollection.current.userInterfaceStyle
        return style == .dark ? "dark" : "light"
        #else
        return "light"
        #endif
    }

    /// A `@AppStorage`-backed preference read from outside a view.
    ///
    /// The `default:` argument is load-bearing: `UserDefaults.bool(forKey:)` answers
    /// `false` for a key that was never written, so a preference whose `@AppStorage`
    /// default is `true` (like `Pref.soundOn`) reports the opposite of the truth until
    /// the user happens to toggle it. Reporting "sound off" for someone who never
    /// touched the switch would send every audio bug report chasing the wrong cause.
    static func setting(_ key: String, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    static func setting(_ key: String, default fallback: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? fallback
    }

    /// Same trap as the `Bool` overload: `UserDefaults.integer(forKey:)` answers `0` for a
    /// key nobody wrote, and `0` is a real answer for `Pref.textbookLesson` ("never studied
    /// the textbook"). An unanswered question has to stay tellable from that, hence the
    /// object read and the `-1` the caller passes.
    static func setting(_ key: String, default fallback: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? fallback
    }
}
