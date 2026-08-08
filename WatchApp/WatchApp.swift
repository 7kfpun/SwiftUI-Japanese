import SwiftUI

@main
struct WatchApp: App {
    @State private var today = WatchToday()

    var body: some Scene {
        WindowGroup {
            WatchTodayView(today: today)
                .tint(WatchTheme.accent)
                // Activated here rather than in `init` so the first frame draws from the
                // stored snapshot immediately; the session catches up a moment later.
                .onAppear(perform: today.start)
        }
    }
}
