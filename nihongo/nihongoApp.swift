import SwiftUI
import SwiftData

@main
struct nihongoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = Store()
    /// The achievement route past the paywall, beside the entitlement one. Both are
    /// consulted at every gate — see `Gating.isLocked`.
    @State private var unlock = Unlock()
    @State private var router = Router()
    /// Per-word Practice stages — local-only by decision, not a CloudKit model.
    /// See `PracticeProgress` for why.
    @Environment(\.scenePhase) private var scenePhase
    @State private var practice = PracticeProgress()
    private let pronouncer = AudioPronouncer()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([KanaResult.self, ChallengeResult.self, StudyDay.self, Bookmark.self])

        // CloudKit private database first, so kana mastery and challenge progress
        // follow the user across devices. Neither model carries `.unique` — CloudKit
        // forbids it; see `ChallengeResult` for how uniqueness is enforced instead.
        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema,
                                                    cloudKitDatabase: .private(Course.current.cloudKitContainer))])
        } catch {
            // No iCloud entitlement (open-source clone), no logged-in account on the
            // simulator, or CloudKit refusing the schema — progress still matters
            // locally, so fall back to the plain on-device store rather than dying.
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
                // One app-level flush, not one per writing screen: ChallengeView
                // demotes stages too, and a jetsam kill during suspension persisted
                // its SwiftData result while the matching demote sat in the debounce —
                // the result screen's "missed words come back in Practice" promise,
                // silently false.
                .onChange(of: scenePhase) {
                    if scenePhase == .background { practice.saveNow() }
                }
                .onOpenURL(perform: handle)
        }
        .modelContainer(sharedModelContainer)
    }

    /// The widget's deep links.
    ///
    /// `nihongo://widget?lesson=N` — a tap on the card itself, which opens Today: the
    /// widget *is* a Today card, so the tab holding the same deck is where a tap should
    /// continue. It also makes the tap countable — a widget launch is otherwise
    /// indistinguishable from any other cold start.
    ///
    /// `nihongo://challenge?lesson=N&index=C` — the "Ready for Challenge C?" call to
    /// action, which lands on that lesson's mode list rather than the app's front door.
    private func handle(_ url: URL) {
        guard url.scheme == "nihongo" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func int(_ name: String) -> Int? {
            items.first { $0.name == name }?.value.flatMap(Int.init)
        }

        switch url.host {
        case "widget":
            Track.event("widget_open", ["lesson": int("lesson") ?? 0])
            router.tab = .today

        case "challenge":
            // `index` is read only for the analytics event — the link lands on the
            // lesson's mode list, not the rung, so nothing navigates by it.
            guard let n = int("lesson"), Course.current.hasLesson(n) else { return }
            Track.event("widget_challenge_open", ["lesson": n, "index": int("index") ?? 0])
            // Today keeps showing words for lessons a free user can't yet test on, so
            // this link can legitimately name a locked lesson. Those stop at the
            // Lessons list rather than dead-ending one screen deeper on the paywall.
            if Gating.isLocked(lesson: n, isPremium: store.isPremium,
                               earnedFirstGroup: unlock.earnedFirstGroup) {
                router.openLessonList()
            } else {
                // The widget carries no language of its own — it renders whatever the
                // app last published — so resolve the lesson in the app's current one.
                let language = UserDefaults.standard.string(forKey: Pref.translationLanguage)
                    ?? VocabStore.deviceDefaultLanguage
                router.openLesson(VocabStore.lesson(n, language))
            }

        default:
            break
        }
    }
}
