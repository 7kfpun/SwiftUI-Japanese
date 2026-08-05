import SwiftUI

struct SelectModeView: View {
    let lesson: Lesson

    var body: some View {
        List {
            Section {
                NavigationLink { VocabListView(lesson: lesson) } label: {
                    ModeRow(icon: "list.bullet", title: L.t("Vocab List"),
                            subtitle: L.t("Browse & hear all words"))
                }
                NavigationLink { LearnView(lesson: lesson) } label: {
                    ModeRow(icon: "square.grid.2x2", title: L.t("Learn"),
                            subtitle: L.t("Rebuild the reading from tiles"))
                }
                NavigationLink { QuizView(lesson: lesson) } label: {
                    ModeRow(icon: "checkmark.circle", title: L.t("Quiz"),
                            subtitle: L.t("Multiple choice, any form"))
                }
            }
            Section(L.t("Needs audio (coming soon)")) {
                ModeRow(icon: "speaker.wave.2", title: L.t("Listening"),
                        subtitle: L.t("Hear it, pick the word")).foregroundStyle(.secondary)
                ModeRow(icon: "play.circle", title: L.t("Read All"),
                        subtitle: L.t("Auto-play the whole lesson")).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L.t("Lesson %@", "\(lesson.number)"))
        .navigationBarTitleDisplayMode(.inline)
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
