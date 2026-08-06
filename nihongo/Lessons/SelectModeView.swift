import SwiftUI

struct SelectModeView: View {
    let lesson: Lesson
    @AppStorage("translationLanguage") private var language = VocabStore.defaultLanguage

    // Re-resolve so entering a mode uses the current Meanings language.
    private var current: Lesson { VocabStore.lesson(lesson.number, language) }

    var body: some View {
        List {
            NavigationLink { VocabListView(lesson: current) } label: {
                ModeRow(icon: "list.bullet", title: L.t("Vocab List"),
                        subtitle: L.t("Browse & hear all words"))
            }
            NavigationLink { FlashcardView(lesson: current) } label: {
                ModeRow(icon: "rectangle.on.rectangle.angled", title: L.t("Flashcards"),
                        subtitle: L.t("Swipe right if you know it"))
            }
            NavigationLink { LearnView(lesson: current) } label: {
                ModeRow(icon: "square.grid.2x2", title: L.t("Learn"),
                        subtitle: L.t("Rebuild the reading from tiles"))
            }
            NavigationLink { QuizView(lesson: current) } label: {
                ModeRow(icon: "checkmark.circle", title: L.t("Quiz"),
                        subtitle: L.t("Multiple choice, any form"))
            }
            NavigationLink { QuizView(lesson: current, from: .audio) } label: {
                ModeRow(icon: "speaker.wave.2", title: L.t("Listening"),
                        subtitle: L.t("Hear it, pick the word"))
            }
        }
        .navigationTitle(L.t("Lesson %@", "\(lesson.number)"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { Track.screen("select_mode", ["lesson": lesson.number]) }
    }
}

private struct ModeRow: View {
    let icon: String, title: String, subtitle: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 30)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
