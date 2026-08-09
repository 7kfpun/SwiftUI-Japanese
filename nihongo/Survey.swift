import Foundation
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
    /// Bumped when a question is added or removed, so whatever reads these rows
    /// can tell a missing field from an unanswered one. Rules require it present.
    static let schemaVersion = 1

    /// One completed onboarding run. Skips and partial runs submit nothing — the
    /// drop-off shape is counted in Analytics instead (`intro_skip`), which is
    /// what lets this schema stay closed with no nullable fields or sentinels.
    struct Intro {
        let knowsKana: String       // none | hiragana | both
        let textbookLesson: Int     // 0 = never studied, else 1...50
        let goal: String            // travel | jlpt | work | culture | other
        let vocabLanguage: String   // the language meanings are shown in
        let appLanguage: String     // the app's own UI language — a separate setting
    }

    /// Field names are snake_case to match the Analytics param convention
    /// (`is_premium`, `query_length`) rather than the camelCase `Pref` keys —
    /// these two datasets get read side by side, and the rules' `hasOnly` list
    /// has to match this map exactly or the write is rejected.
    static func submit(_ intro: Intro) {
        submit(collection: "survey_intro", fields: [
            "knows_kana": intro.knowsKana,
            "textbook_lesson": intro.textbookLesson,
            "goal": intro.goal,
            "vocab_language": intro.vocabLanguage,
            "app_language": intro.appLanguage,
            "app_version": AppInfo.version,
            "os": AppInfo.os,
            "platform": "iOS",
            "debug": AppInfo.isDebugBuild,
            "v": schemaVersion,
        ])
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

/// Build and OS strings for anything that reports about itself.
enum AppInfo {
    /// e.g. `"2.1.0 (143)"` — marketing version plus build number, since a
    /// TestFlight bug report is usually about a specific build, not a version.
    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    /// True for a Debug build.
    ///
    /// Rides along on every survey submission because `Survey` deliberately *doesn't*
    /// honour the analytics opt-out — development runs write real rows into the same
    /// collection as real users. This is the field that tells them apart when reading
    /// results, and it's cheaper than the alternative of suppressing DEBUG writes and
    /// never exercising the path.
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
}
