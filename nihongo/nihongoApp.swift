//
//  nihongoApp.swift
//  nihongo
//
//  Created by KF PUN on 5/8/26.
//

import SwiftUI
import SwiftData

@main
struct nihongoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = Store()
    private let pronouncer = AudioPronouncer()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([KanaResult.self, ChallengeResult.self])

        // CloudKit private database first, so kana mastery and challenge progress
        // follow the user across devices. Neither model carries `.unique` —
        // CloudKit-backed SwiftData forbids unique constraints, so uniqueness is
        // enforced by the models' `record` upserts and merge-tolerant readers.
        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema,
                                                    cloudKitDatabase: .private("iCloud.com.kfpun.nihongo"))])
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
                // The Today widget's deep link (`nihongo://widget?lesson=N`). Its only
                // job is to make a home-screen tap countable — a widget launch is
                // otherwise indistinguishable from any other cold start, so without
                // this there's no way to tell whether the widget drives returns.
                .onOpenURL { url in
                    guard url.scheme == "nihongo", url.host == "widget" else { return }
                    let lesson = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                        .queryItems?.first { $0.name == "lesson" }
                        .flatMap { $0.value.flatMap(Int.init) }
                    Track.event("widget_open", ["lesson": lesson ?? 0])
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
