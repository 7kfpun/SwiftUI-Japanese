import SwiftUI

struct SelectModeView: View {
    let lesson: Lesson
    @Environment(Store.self) private var store
    @State private var showPaywall = false

    /// Lessons 6–50 lock every mode except Vocab List until premium.
    private var locked: Bool { Gating.isLocked(lesson: lesson.number, isPremium: store.isPremium) }

    var body: some View {
        List {
            // Always free — even for locked lessons.
            NavigationLink { VocabListView(lesson: lesson) } label: {
                ModeRow(icon: "list.bullet", title: L.t("Vocab List"),
                        subtitle: L.t("Browse & hear all words"))
            }
            gated(icon: "rectangle.on.rectangle.angled", title: "Flashcards",
                  subtitle: "Swipe right if you know it") { FlashcardView(lesson: lesson) }
            gated(icon: "square.grid.2x2", title: "Learn",
                  subtitle: "Rebuild the reading from tiles") { LearnView(lesson: lesson) }
            gated(icon: "checkmark.circle", title: "Quiz",
                  subtitle: "Multiple choice, any form") { QuizView(lesson: lesson) }
            gated(icon: "speaker.wave.2", title: "Listening",
                  subtitle: "Hear it, pick the word") { QuizView(lesson: lesson, from: .audio) }
        }
        .navigationTitle(L.t("Lesson %@", "\(lesson.number)"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    /// A premium mode: navigates when unlocked, else shows a lock and opens the paywall.
    @ViewBuilder
    private func gated<Destination: View>(icon: String, title: String, subtitle: String,
                                          @ViewBuilder destination: @escaping () -> Destination) -> some View {
        if locked {
            Button { showPaywall = true } label: {
                ModeRow(icon: icon, title: L.t(title), subtitle: L.t(subtitle), locked: true)
            }
            .foregroundStyle(.primary)
        } else {
            NavigationLink { destination() } label: {
                ModeRow(icon: icon, title: L.t(title), subtitle: L.t(subtitle))
            }
        }
    }
}

private struct ModeRow: View {
    let icon: String, title: String, subtitle: String
    var locked = false

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
            if locked {
                Spacer()
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
