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
            // Offered here too, and the kana case is why `Feedback.Item.lesson` accepts 0: a
            // syllable belongs to no lesson, so the romaji alone identifies it and
            // `last_screen` ("kana_flashcard") says which chart it came from. Worth having —
            // a mis-cut clip or a wrong reading in `KanaChart.json` is the same kind of data
            // error as a wrong translation, and it goes to the same regeneration.
            report: { Feedback.Item(lesson: 0, romaji: $0.romaji) },
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
                // The reading is the answer this card exists to give, and it's Latin —
                // so it takes the rounded Latin face the browser tiles and Write's prompt
                // use, rather than being the one romaji in the Kana tab set in plain SF.
                Text(kana.romaji).font(Theme.title(.title)).foregroundStyle(Theme.accent)
                Text(kana.katakana).font(Theme.jpBold(20)).foregroundStyle(.secondary)
            }
        }
    }
}
