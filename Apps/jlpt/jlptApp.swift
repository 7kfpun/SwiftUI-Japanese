import SwiftUI
import SwiftData

/// The JLPT app's entry point.
///
/// Deliberately a near-copy of `nihongoApp` rather than a shared base type. Everything
/// that actually differs between the two apps is already expressed in `Course`, so what
/// is left here is the handful of lines Swift requires to be per-target: the `@main`
/// attribute (only one per module), and the URL scheme, which is a string in each app's
/// Info.plist and cannot come from a shared constant without one app claiming the
/// other's links.
@main
struct jlptApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = Store()
    /// The achievement route past the paywall, beside the entitlement one. Both are
    /// consulted at every gate — see `Gating.isLocked`.
    @State private var unlock = Unlock()
    @State private var router = Router()
    /// Per-word Practice stages — local-only by decision, not a CloudKit model.
    /// See `PracticeProgress` for why.
    @State private var practice = PracticeProgress()
    private let pronouncer = AudioPronouncer()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([KanaResult.self, ChallengeResult.self, StudyDay.self, Bookmark.self])

        // CloudKit private database first, so kana mastery and challenge progress
        // follow the user across devices. The container name comes from `Course` —
        // sharing Minna's would let JLPT lesson 12 overwrite Minna lesson 12, since a
        // `ChallengeResult` is keyed by lesson number and nothing else.
        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema,
                                                    cloudKitDatabase: .private(Course.current.cloudKitContainer))])
        } catch {
            print("CloudKit store unavailable (\(error)) — falling back to local-only")
        }

        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Theme.accent)
                .environment(\.pronouncer, pronouncer)
                .environment(store)
                .environment(unlock)
                .environment(router)
                .environment(practice)
                .onOpenURL(perform: handle)
        }
        .modelContainer(sharedModelContainer)
    }

    /// The widget's deep links — see `nihongoApp.handle` for what each one means. The
    /// scheme is `jlpt`, so a link minted by one app can never open the other.
    private func handle(_ url: URL) {
        guard url.scheme == "jlpt" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func int(_ name: String) -> Int? {
            items.first { $0.name == name }?.value.flatMap(Int.init)
        }

        switch url.host {
        case "widget":
            Track.event("widget_open", ["lesson": int("lesson") ?? 0])
            router.tab = .today

        case "challenge":
            guard let n = int("lesson"), Course.current.hasLesson(n) else { return }
            Track.event("widget_challenge_open", ["lesson": n, "index": int("index") ?? 0])
            if Gating.isLocked(lesson: n, isPremium: store.isPremium,
                               earnedFirstGroup: unlock.earnedFirstGroup) {
                router.openLessonList()
            } else {
                let language = UserDefaults.standard.string(forKey: Pref.translationLanguage)
                    ?? VocabStore.deviceDefaultLanguage
                router.openLesson(VocabStore.lesson(n, language))
            }

        default:
            break
        }
    }
}
