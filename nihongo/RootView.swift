import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage(Pref.appLanguage) private var appLanguage = L.deviceDefault
    @Environment(Router.self) private var router

    /// First launch only. Read into `@State` rather than bound to the preference: the
    /// intro writes `introAnswered` itself as part of saving its answers, and a cover
    /// bound straight to that key would vanish mid-dismissal instead of animating out.
    @State private var showIntro = !UserDefaults.standard.bool(forKey: Pref.introAnswered)

    /// First launch, or the hidden replay from Settings. One binding so the cover has a
    /// single source of truth and dismissing clears whichever of the two raised it.
    private var introPresented: Binding<Bool> {
        Binding(get: { showIntro || router.replayIntro },
                set: { shown in
                    guard !shown else { return }
                    showIntro = false
                    router.replayIntro = false
                })
    }

    var body: some View {
        // Selection is bound so the widget's deep link can switch tabs; the tags are
        // what make that binding addressable.
        @Bindable var router = router
        TabView(selection: $router.tab) {
            banner(TodayView(), .today)
                .tabItem { Label(L.t("Today"), systemImage: "sun.max") }
                .tag(Router.Tab.today)

            banner(KanaBrowserView(), .kana)
                .tabItem { Label(L.t("Kana"), systemImage: "character.book.closed") }
                .tag(Router.Tab.kana)

            banner(LessonListView(), .lessons)
                .tabItem { Label(L.t("Lessons"), systemImage: "list.bullet") }
                .tag(Router.Tab.lessons)

            banner(SettingsView(), .about)
                .tabItem { Label(L.t("Settings"), systemImage: "gearshape") }
                .tag(Router.Tab.settings)
        }
        .id(appLanguage)
        // Outside the `.id`, so nothing about the tour depends on the tree beneath it
        // being rebuilt. The intro chooses the landing tab (Kana for someone who can't
        // read kana yet, otherwise Today) — see `Intro.landingTab`.
        .fullScreenCover(isPresented: introPresented) {
            IntroView { landing in
                router.tab = landing
                showIntro = false
                router.replayIntro = false
            }
        }
    }

    /// Reserve the banner's space structurally (VStack), not via safeAreaInset —
    /// screens pushed inside a NavigationStack ignore an outer safe-area inset and
    /// would render underneath the ad (e.g. a challenge's Next button).
    private func banner(_ content: some View, _ slot: AdSlot) -> some View {
        VStack(spacing: 0) {
            content
            BannerAd(slot: slot)
        }
    }
}

#Preview {
    RootView()
        .tint(Theme.accent)
        .environment(Store())
        .environment(Router())
        .modelContainer(for: [KanaResult.self, ChallengeResult.self], inMemory: true)
}
