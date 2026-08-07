import SwiftUI

/// Kana flashcards — the same shared `FlashcardScreen`, over the current kana table.
/// Show a kana, decide if you know its reading; reveal shows romaji + katakana.
struct KanaFlashcardView: View {
    let table: KanaTable
    @Environment(\.pronouncer) private var pronouncer

    var body: some View {
        FlashcardScreen(
            deck: FlashDeck(table.rows.flatMap { $0 }.filter { !$0.isEmpty }),
            id: { $0.romaji },
            revealLabel: L.t("Reveal"),
            summary: { L.t("You reviewed %@ kana", "\($0)") },
            trackName: "kana_flashcard",
            speak: { pronouncer.speak(kana: $0) },
            face: { kana, revealed in KanaFace(kana: kana, revealed: revealed) }
        )
        .onAppear { Track.screen("kana_flashcard") }
    }
}

/// The kana card face: hiragana, revealing romaji + katakana.
private struct KanaFace: View {
    let kana: K
    let revealed: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text(kana.hiragana)
                .font(Theme.jpStrokes(160))
                .lineLimit(1)
                .minimumScaleFactor(0.4)   // combos (びゃ) shrink to fit instead of truncating
            if revealed {
                Divider().padding(.horizontal, 40)
                Text(kana.romaji).font(.title).foregroundStyle(Theme.accent)
                Text(kana.katakana).font(Theme.jpBold(20)).foregroundStyle(.secondary)
            }
        }
    }
}
