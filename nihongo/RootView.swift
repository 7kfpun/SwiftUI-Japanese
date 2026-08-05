import SwiftUI
import SwiftData

struct RootView: View {
    @AppStorage("appLanguage") private var appLanguage = L.deviceDefault

    var body: some View {
        TabView {
            KanaBrowserView()
                .tabItem { Label(L.t("Kana"), systemImage: "character.book.closed") }

            LessonListView()
                .tabItem { Label(L.t("Lessons"), systemImage: "list.bullet") }

            SettingsView()
                .tabItem { Label(L.t("Settings"), systemImage: "gearshape") }
        }
        .id(appLanguage)   // rebuild the whole tree when the app language changes
    }
}

#Preview {
    RootView()
        .tint(Theme.accent)
        .modelContainer(for: KanaResult.self, inMemory: true)
}
