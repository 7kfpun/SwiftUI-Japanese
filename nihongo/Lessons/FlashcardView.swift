import SwiftUI

/// Lessons flashcards — the shared `FlashcardScreen` over a lesson's vocab.
/// Entry is gated in `SelectModeView`, so reaching this means the lesson is unlocked.
struct FlashcardView: View {
    let lesson: Lesson
    @Environment(\.pronouncer) private var pronouncer

    var body: some View {
        FlashcardScreen(
            deck: FlashDeck(lesson.entries),
            id: { $0.id },
            revealLabel: L.t("Show meaning"),
            summary: { L.t("You reviewed %@ words", "\($0)") },
            trackName: "flashcard",
            speak: { pronouncer.speak($0) },
            face: { vocab, revealed in VocabFace(vocab: vocab, revealed: revealed) }
        )
        .onAppear { Track.screen("flashcards", ["lesson": lesson.number]) }
    }
}

/// The vocab card face: kana (+ kanji), revealing meaning + romaji.
private struct VocabFace: View {
    let vocab: Vocab
    let revealed: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text(vocab.kana)
                .font(Theme.jp(56))
                .minimumScaleFactor(0.4)
                .multilineTextAlignment(.center)
            if vocab.displaysKanji {
                Text(vocab.kanji).font(Theme.jp(22)).foregroundStyle(.secondary)
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
