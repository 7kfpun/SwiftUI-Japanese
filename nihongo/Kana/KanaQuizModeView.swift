import SwiftUI

/// Lets the learner pick how to take the kana quiz.
struct KanaQuizModeView: View {
    let table: KanaTable

    var body: some View {
        List {
            Section {
                NavigationLink { KanaFlashcardView(table: table) } label: {
                    ModeRow(icon: "rectangle.on.rectangle.angled", title: L.t("Flashcards"),
                            subtitle: L.t("Swipe right if you know it"))
                }
                NavigationLink { KanaQuizView(table: table) } label: {
                    ModeRow(icon: "hand.tap", title: L.t("Classic"),
                            subtitle: L.t("Tap one of 4 options"))
                }
                NavigationLink { KanaSwipeQuizView(table: table) } label: {
                    ModeRow(icon: "rectangle.portrait.and.arrow.right", title: L.t("Swipe"),
                            subtitle: L.t("Swipe left / right between 2 options"))
                }
                NavigationLink { KanaQuizView(table: table, listening: true) } label: {
                    ModeRow(icon: "speaker.wave.2", title: L.t("Listening"),
                            subtitle: L.t("Hear it, pick the word"))
                }
                NavigationLink { KanaWriteView(table: table) } label: {
                    ModeRow(icon: "pencil.and.outline", title: L.t("Write"),
                            subtitle: L.t("Hear it, draw it"))
                }
            }
        }
        .navigationTitle(L.t("Choose mode"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Track.screen("kana_quiz_mode") }
    }
}
