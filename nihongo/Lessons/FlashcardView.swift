import SwiftUI

/// Flashcards — a lesson's words as a deck you page through, and nothing else.
///
/// **Deliberately unscored.** The graded deck this replaces asked "did you know it?" on
/// every card, and that self-assessment is exactly what `PracticeView` exists to avoid:
/// it measures confidence rather than recall, and it was the difference beginners could
/// not choose between. So this screen keeps only the part that never needed a verdict —
/// meeting the words, one at a time, at your own pace — and every judgement lives in
/// Practice and the Challenge ladder.
///
/// It writes **nothing**: no `PracticeProgress` stage, no `ChallengeResult`, no streak
/// day. Browsing a lesson is not evidence of anything, and a screen that quietly moved a
/// word up a ladder for being looked at would make the ladder mean less.
struct FlashcardView: View {
    let lesson: Lesson

    @AppStorage(Pref.flashcardsOrdered) private var ordered = true
    @AppStorage(Pref.soundOn) private var soundOn = true
    @Environment(\.pronouncer) private var pronouncer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var index = 0
    /// Held down — the card is showing its back. Released, it turns straight back.
    @State private var flipped = false
    /// This card already logged its flip — `flashcard_flip` counts cards peeked, not
    /// presses, so it stays comparable with `practice_peek` across the two screens.
    @State private var flippedThisCard = false
    /// Distinct cards reached this sitting — `flashcard_swipe` reports depth rather
    /// than raw turns (back-and-forth on two cards isn't progress), same rule as
    /// `today_swipe`, and only a *new* card logs.
    @State private var cardsSeen: Set<Int> = [0]

    private var entries: [Vocab] { lesson.entries }
    private var current: Vocab? { entries.indices.contains(index) ? entries[index] : nil }

    var body: some View {
        VStack(spacing: 16) {
            orderPicker

            if let word = current {
                ZStack {
                    CardStackPeek(count: min(2, max(0, entries.count - 1)))
                    // On the card, **not** on this ZStack. `cardPager` offsets and rotates
                    // whatever it modifies, so outside the card it flings the peek layers
                    // too and the deck leaves as one slab — which is exactly what it did
                    // here. Same rule Today, Intro and Kana Swipe follow.
                    card(word)
                        .cardPager(page: turnPage)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        }
        .padding()
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ToolbarStatus {
                    Text("\(index + 1) / \(entries.count)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            FlagAndSoundToolbar(item: current.map { Feedback.Item(lesson: $0.lesson,
                                                                  romaji: $0.romaji) })
        }
        .onAppear {
            autoPlay()
            Track.screen("flashcards", ["lesson": lesson.number])
            ModeVisits.mark(lesson: lesson.number, mode: "flashcards")
        }
    }

    // MARK: - The card

    /// Front: the word. Back: what it means, on a hold.
    ///
    /// A press-and-hold rather than a tap-to-flip, matching Practice: the card returns
    /// the moment you let go, so peeking costs a held finger and the deck can never be
    /// left sitting face-up. That also leaves the tap free for the audio, which is what a
    /// learner reaches for most on a screen whose whole job is meeting new words.
    ///
    /// The swipe hint hides while flipped: it belongs to `SwipeCard`, which is what the
    /// 3D turn rotates, so on the back it rendered mirror-written. The faces counter-
    /// rotate themselves; the hint is cheaper to hide than to un-mirror, and you can't
    /// swipe mid-hold anyway.
    private func card(_ word: Vocab) -> some View {
        SwipeCard(showsHint: entries.count > 1 && !flipped) {
            ZStack {
                back(word).opacity(flipped ? 1 : 0)
                front(word).opacity(flipped ? 0 : 1)
            }
            .padding(24)
        }
        .rotation3DEffect(.degrees(flipped && !reduceMotion ? 180 : 0),
                          axis: (x: 0, y: 1, z: 0))
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.45),
                   value: flipped)
        .onTapGesture { pronouncer.speak(word) }
        .onLongPressGesture(minimumDuration: CardFlip.hold) {
            if !flippedThisCard {
                flippedThisCard = true
                Track.event("flashcard_flip", ["lesson": lesson.number])
            }
            withAnimation { flipped = true }
        } onPressingChanged: { pressing in
            if !pressing, flipped { withAnimation { flipped = false } }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: flipped)
    }

    private func front(_ word: Vocab) -> some View {
        VStack(spacing: 14) {
            Text(word.kana)
                .font(Theme.jp(56))
                .minimumScaleFactor(0.4)
                .multilineTextAlignment(.center)
            if word.displaysKanji {
                Text(word.kanji).font(Theme.jp(22)).foregroundStyle(.secondary)
            }
        }
    }

    /// Mirrored, so it reads the right way round once the card has turned.
    private func back(_ word: Vocab) -> some View {
        VocabFace(vocab: word, revealed: true,
                  speakExample: {
                      pronouncer.speak(example: word)
                      Track.event("play_example", ["lesson": lesson.number,
                                                   "surface": "flashcards"])
                  })
            .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
    }

    // MARK: - Chrome

    /// Ordered by default, unlike Practice's queue: this screen is for a first walk
    /// through a lesson, and a first walk wants the order the course teaches in. Random
    /// is the second pass, and gets the shuffle button instead of a swipe direction.
    private var orderPicker: some View {
        OrderPicker(ordered: $ordered, event: "flashcard_order_mode")
    }

    /// One hint, both modes.
    ///
    /// Random used to get a full-width "Random" button here instead. It did exactly what a
    /// swipe already does in that mode — draw another card — while wearing the same word
    /// as the selected picker segment above it, so it read as a mode switch that was
    /// already switched. The gesture is the control on a deck; the only thing worth
    /// teaching is the one that isn't discoverable.
    private var footer: some View {
        Text(L.t("Long-press to see details"))
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Paging

    /// Ordered walks the lesson and wraps; random jumps. Speaks explicitly rather than
    /// through `onChange(of: index)`, because a random jump can land on the card already
    /// showing and would then silently skip the word — the same reason Learn does it here.
    private func turnPage(_ dir: Int) {
        guard !entries.isEmpty else { return }
        flipped = false
        flippedThisCard = false
        if ordered {
            index = (index + (dir > 0 ? 1 : -1) + entries.count) % entries.count
        } else if entries.count > 1 {
            var next = index
            while next == index { next = Int.random(in: entries.indices) }
            index = next
        }
        if cardsSeen.insert(index).inserted {
            Track.event("flashcard_swipe", ["lesson": lesson.number,
                                            "depth": cardsSeen.count])
        }
        autoPlay()
    }

    private func autoPlay() {
        guard soundOn, let word = current else { return }
        pronouncer.speak(word)
    }
}
