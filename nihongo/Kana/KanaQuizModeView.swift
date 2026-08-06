import SwiftUI

/// Lets the learner pick how to take the kana quiz.
struct KanaQuizModeView: View {
    let table: KanaTable

    var body: some View {
        List {
            Section {
                NavigationLink { KanaQuizView(table: table) } label: {
                    ModeCard(icon: "hand.tap", title: L.t("Classic"),
                             subtitle: L.t("Tap one of 4 options"))
                }
                NavigationLink { KanaSwipeQuizView(table: table) } label: {
                    ModeCard(icon: "rectangle.portrait.and.arrow.right", title: L.t("Swipe"),
                             subtitle: L.t("Swipe left / right between 2 options"))
                }
                NavigationLink { KanaFlashcardView(table: table) } label: {
                    ModeCard(icon: "rectangle.on.rectangle.angled", title: L.t("Flashcards"),
                             subtitle: L.t("Swipe right if you know it"))
                }
            }
        }
        .navigationTitle(L.t("Choose mode"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ModeCard: View {
    let icon: String, title: String, subtitle: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3).frame(width: 30)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
