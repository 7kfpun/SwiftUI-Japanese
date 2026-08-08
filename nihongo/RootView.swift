import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage(Pref.appLanguage) private var appLanguage = L.deviceDefault
    @Environment(Router.self) private var router

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
        .id(appLanguage)   // rebuild the whole tree when the app language changes
    }

    /// Reserve the banner's space structurally (VStack), not via safeAreaInset —
    /// screens pushed inside a NavigationStack ignore an outer safe-area inset and
    /// would render underneath the ad (e.g. the Quiz's Next button).
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
