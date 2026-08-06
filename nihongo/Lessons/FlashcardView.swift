import SwiftUI

/// Lessons flashcards — the shared `FlashcardScreen` over a lesson's vocab.
struct FlashcardView: View {
    let lesson: Lesson
    @Environment(\.pronouncer) private var pronouncer

    var body: some View {
        FlashcardScreen(
            deck: FlashDeck(lesson.entries),
            id: { $0.id },
            revealLabel: L.t("Show meaning"),
            summary: { L.t("You reviewed %@ words", "\($0)") },
            speak: { pronouncer.speak($0) },
            face: { vocab, revealed in VocabFace(vocab: vocab, revealed: revealed) }
        )
    }
}

/// The vocab card face: kana (+ kanji), revealing meaning + romaji.
private struct VocabFace: View {
    let vocab: Vocab
    let revealed: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text(vocab.kana)
                .font(.system(size: 60, weight: .light))
                .minimumScaleFactor(0.4)
                .multilineTextAlignment(.center)
            if vocab.displaysKanji {
                Text(vocab.kanji).font(.title2).foregroundStyle(.secondary)
            }
            if revealed {
                Divider().padding(.horizontal, 40)
                Text(vocab.translation)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
                if !vocab.romaji.isEmpty {
                    Text(vocab.romaji).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}
