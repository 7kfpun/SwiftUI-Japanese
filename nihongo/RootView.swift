import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage(Pref.appLanguage) private var appLanguage = L.deviceDefault

    var body: some View {
        TabView {
            banner(TodayView(), .today)
                .tabItem { Label(L.t("Today"), systemImage: "sun.max") }

            banner(KanaBrowserView(), .kana)
                .tabItem { Label(L.t("Kana"), systemImage: "character.book.closed") }

            banner(LessonListView(), .lessons)
                .tabItem { Label(L.t("Lessons"), systemImage: "list.bullet") }

            banner(SettingsView(), .about)
                .tabItem { Label(L.t("Settings"), systemImage: "gearshape") }
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
        .modelContainer(for: KanaResult.self, inMemory: true)
}
