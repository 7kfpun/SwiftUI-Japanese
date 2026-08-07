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
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
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
        }
        .modelContainer(sharedModelContainer)
    }
}
