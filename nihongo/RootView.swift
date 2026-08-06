import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage("appLanguage") private var appLanguage = L.deviceDefault

    var body: some View {
        TabView {
            KanaBrowserView()
                .safeAreaInset(edge: .bottom) { BannerAd(slot: .kana) }
                .tabItem { Label(L.t("Kana"), systemImage: "character.book.closed") }

            LessonListView()
                .safeAreaInset(edge: .bottom) { BannerAd(slot: .lessons) }
                .tabItem { Label(L.t("Lessons"), systemImage: "list.bullet") }

            SettingsView()
                .safeAreaInset(edge: .bottom) { BannerAd(slot: .about) }
                .tabItem { Label(L.t("Settings"), systemImage: "gearshape") }
        }
        .id(appLanguage)   // rebuild the whole tree when the app language changes
    }
}

#Preview {
    RootView()
        .tint(Theme.accent)
        .environment(Store())
        .modelContainer(for: KanaResult.self, inMemory: true)
}
