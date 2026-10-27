#if os(iOS)
import ActivityKit
import AppIntents
import Foundation

/// What a Read-along Live Activity shows.
///
/// `lesson` is the only fixed fact. Everything that moves — the word, the index, the
/// play/pause labels — is `ContentState`, and those labels are already localized.
/// The widget extension does not ship `UIStrings.json`; the app fills them with `L.t`
/// on each update, so a language change shows up on the next word.
///
/// Nothing in here identifies a person. The lesson number is which lesson is playing.
/// `Activity.request` is called with `pushType: nil`, so ActivityKit never mints a
/// push token, and the activity id is not written down. The App Group and OneSignal's
/// group are not involved: the system carries this payload itself.
nonisolated struct ReadAlongAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var lessonTitle: String
        var word: String
        /// Zero-based index into the list the player was given.
        var index: Int
        var count: Int
        /// Audio is moving. A pause keeps the activity and sets this false; stopping
        /// ends the activity, so "stopped" is not a state this struct has to spell.
        var isPlaying: Bool
        var progressLabel: String
        var statusLabel: String
        /// The pause/resume button's accessibility name. Already localized.
        var actionLabel: String
        var modeLabel: String
    }

    var lesson: Int
}

/// `nihongo://read?lesson=N`. The widget extension is embedded only in the Minna app,
/// whose scheme is `nihongo` — a JLPT build never draws this activity.
nonisolated enum ReadAlongLink {
    static let scheme = "nihongo"

    static func url(lesson: Int) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "read"
        components.queryItems = [URLQueryItem(name: "lesson", value: String(lesson))]
        return components.url
    }
}

/// The island's pause button cannot see `LessonPlayer` — that type lives in the app,
/// and this file is also compiled into the widget. The screen installs a closure for
/// as long as it is on screen; the intent runs in the app process and calls it.
@MainActor
enum ReadAlongRemote {
    static var toggle: (() -> Void)?
}

/// Pause or resume the lesson that is already playing.
///
/// `LiveActivityIntent` runs this in the app, where `ReadAlongRemote` was installed.
/// `AudioPlaybackIntent` lets that happen with the phone locked, without bringing
/// the app forward. `nonisolated` because the app target isolates types to the main
/// actor by default, and `AppIntent` requires `Sendable`.
nonisolated struct ToggleReadAlongIntent: AudioPlaybackIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or resume"
    /// Not a Shortcuts action. It only means something while Read along is up.
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await MainActor.run { ReadAlongRemote.toggle?() }
        return .result()
    }
}

/// Start, update and end the one Read-along activity.
///
/// Offered only for Minna. The drawing code is in `TodayWidget`, and that extension
/// is embedded in the Minna app alone — a JLPT request would be an activity with no UI.
@MainActor
enum ReadAlongActivity {
    static var isOffered: Bool { Course.current.id == "minna" }

    private static var activity: Activity<ReadAlongAttributes>?
    private static var chain: Task<Void, Never>?

    static func sync(lesson: Int, state: ReadAlongAttributes.ContentState) {
        guard isOffered else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            enqueue { await endCurrent() }
            return
        }
        enqueue {
            if let activity, activity.attributes.lesson == lesson {
                await activity.update(Self.content(state))
            } else {
                await endCurrent()
                do {
                    activity = try Activity.request(
                        attributes: ReadAlongAttributes(lesson: lesson),
                        content: Self.content(state),
                        pushType: nil)
                } catch {
                    activity = nil
                }
            }
        }
    }

    static func end() {
        guard isOffered else { return }
        enqueue { await endCurrent() }
    }

    /// Long enough that a looping lesson is not declared stale between words, short
    /// enough that a killed app does not leave a frozen card up all day. Each update
    /// pushes the deadline out.
    private static func content(_ state: ReadAlongAttributes.ContentState)
        -> ActivityContent<ReadAlongAttributes.ContentState> {
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(20 * 60))
    }

    private static func endCurrent() async {
        let ending = activity
        activity = nil
        await ending?.end(nil, dismissalPolicy: .immediate)
        for existing in Activity<ReadAlongAttributes>.activities {
            await existing.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Updates arrive from SwiftUI on every word. They have to run in order, or a
    /// slow `request` can finish after the `end` that was meant to follow it.
    private static func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = chain
        chain = Task { @MainActor in
            await previous?.value
            await work()
        }
    }
}
#endif
