import SwiftUI

/// The still lifes the intro shows: one per Learn mode, the Challenge ladder a lesson
/// in, and the Today widget.
///
/// All of them are **static vignettes over real lesson-1 data** — never a hardcoded
/// word, and never a live mode. Instantiating `TrainModel` / `LearnModel` or the real
/// mode views would drag in gating, ad slots and session state for a card nobody can
/// play, and each of those views owns a horizontal drag gesture that would fight
/// `cardPager`'s page turn. So these reuse the *chrome* (`SwipeCard`, `SwipeStamp`,
/// `SwipeOptionChip`, `VocabRow`, `StarRow`) and answer to taps only.
struct IntroModeSample: View {
    let mode: Intro.Mode
    let entries: [Vocab]
    @Environment(\.pronouncer) private var pronouncer

    private var word: Vocab? { entries.first }

    var body: some View {
        Group {
            switch mode {
            case .vocabList:  vocabList
            case .flashcards: flashcard
            case .train:      train
            case .learn:      learn
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Vocab List — three real rows of the list itself. `VocabRow` already *is* this
    /// (reading left, meaning right, speaker icon, tap to hear), so it's reused rather
    /// than imitated; only the `List`'s separators are drawn by hand here.
    private var vocabList: some View {
        let rows = Array(entries.prefix(3))
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, vocab in
                if i > 0 { Divider() }
                VocabRow(vocab: vocab).padding(.vertical, 7)
            }
        }
    }

    /// Flashcards — the real card face, already revealed, with a `SwipeStamp` standing
    /// in for the stamp that fades in under a drag.
    ///
    /// Accent, not green: green and red are answer feedback everywhere in this app and
    /// nothing in the intro is graded, so the corner hint borrows the shape without the
    /// colour that would claim a verdict.
    @ViewBuilder private var flashcard: some View {
        if let word {
            SwipeCard(showsHint: false) {
                VStack(spacing: 6) {
                    Text(word.kana)
                        .font(Theme.jp(34))
                        .lineLimit(1).minimumScaleFactor(0.4)
                    Text(word.romaji)
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(word.translation)
                        .font(.subheadline).foregroundStyle(Theme.accent)
                        .multilineTextAlignment(.center).minimumScaleFactor(0.6)
                }
                .padding(16)
            }
            .overlay(alignment: .topTrailing) {
                SwipeStamp(systemImage: "checkmark", color: Theme.accent, rotation: 8)
                    .padding(10)
            }
            .contentShape(Rectangle())
            .onTapGesture { pronouncer.speak(word) }
        }
    }

    /// Train — the prompt over the mode's own two option chips, left unanswered
    /// (`picked: nil`), which is exactly the state whose chevrons read as "swipe this
    /// way". `TrainModel.optionCount` is 2, so two is the honest number.
    @ViewBuilder private var train: some View {
        if let word, entries.count > 1 {
            VStack(spacing: 10) {
                Text(word.kana)
                    .font(Theme.jp(30))
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .contentShape(Rectangle())
                    .onTapGesture { pronouncer.speak(word) }
                HStack(spacing: 10) {
                    chip(entries[0], side: 0, isAnswer: true)
                    chip(entries[1], side: 1, isAnswer: false)
                }
            }
        }
    }

    private func chip(_ vocab: Vocab, side: Int, isAnswer: Bool) -> some View {
        SwipeOptionChip(text: vocab.translation, side: side, picked: nil, isAnswer: isAnswer,
                        font: .subheadline.weight(.semibold)) {
            // Tapping any sample speaks the word being taught, not the chip's own word —
            // the vignette is about the prompt, and there's no answer to be right about.
            if let word { pronouncer.speak(word) }
        }
    }

    /// Learn — the reading half-built above the tile grid it's built from.
    @ViewBuilder private var learn: some View {
        if let word {
            LearnSample(entry: word)
                .contentShape(Rectangle())
                .onTapGesture { pronouncer.speak(word) }
        }
    }
}

/// Learn's tile game frozen mid-solve: part of the reading assembled, the rest still in
/// the grid among distractors.
private struct LearnSample: View {
    private let assembled: String
    private let tiles: [String]
    private let cols = 5
    private let spacing: CGFloat = 6

    init(entry: Vocab) {
        let chars = Array(cleanWord(entry.kana)).map(String.init)
        // Half-built, so it reads as in progress rather than solved or untouched.
        assembled = chars.prefix(max(1, chars.count / 2)).joined()
        // Distractors come from the very pool `LearnModel` draws on, so the grid is the
        // real thing — but they're picked at a fixed stride and ordered by a hash of the
        // glyph rather than `.shuffled()`. A static vignette that re-dealt itself would
        // twitch every time SwiftUI redrew the card.
        let pool = KanaData.hiraganaPool.filter { !chars.contains($0) }
        let want = max(0, 10 - chars.count)
        let extra = stride(from: 3, to: pool.count, by: 7).prefix(want).map { pool[$0] }
        tiles = (chars + extra).sorted { Self.rank($0) < Self.rank($1) }
    }

    /// Stable pseudo-shuffle: a Knuth-multiplicative hash of the glyph, so the
    /// arrangement looks dealt yet is identical on every redraw.
    private static func rank(_ glyph: String) -> UInt64 {
        (UInt64(glyph.unicodeScalars.first?.value ?? 0) &* 2_654_435_761) % 100_003
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(assembled)
                .font(Theme.jp(34))
                .lineLimit(1).minimumScaleFactor(0.4)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: spacing),
                                     count: cols),
                      spacing: spacing) {
                ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                    Text(tile)
                        .font(.subheadline)
                        .frame(minWidth: 30, minHeight: 30)
                        .padding(3)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line))
                }
            }
        }
    }
}

/// The Challenge ladder as it looks a rung in: one cleared, the next open, the one after
/// still shut behind it.
///
/// `ChallengeRow`'s anatomy — filled accent circle with a checkmark once passed, the
/// `StarRow`, the same `Best %@%` / `Beat Challenge %@ to unlock` captions — rebuilt here
/// rather than reused, because the real row takes a `ChallengeResult` and fabricating
/// `@Model` rows for a mockup would mean inserting invented history into a CloudKit-backed
/// store. Nothing is persisted by this view; it is a picture of a row, not a row.
struct IntroChallengeRungs: View {
    /// The three states a rung can be in, mirroring `ChallengeRowState`.
    ///
    /// Modelled explicitly rather than inferred from "has stars", because those aren't the
    /// same fact: a rung nobody has attempted yet is *open* — numbered, three empty stars,
    /// no padlock — while a locked one sits behind an unpassed rung below it. Collapsing
    /// the two would draw a padlock on rung 3 with rung 2 already cleared above it, which
    /// contradicts, in the illustration, the exact rule this card's copy is teaching.
    private enum Rung {
        case passed(best: Int, stars: Int)
        case open
        case locked

        var isPassed: Bool { if case .passed = self { return true } else { return false } }
        var isLocked: Bool { if case .locked = self { return true } else { return false } }

        var best: Int? {
            if case .passed(let best, _) = self { return best } else { return nil }
        }

        /// `nil` means a padlock takes the star row's place. An open rung still shows the
        /// row, empty — three outlines are how the real ladder says "not yet".
        var stars: Int? {
            switch self {
            case .passed(_, let stars): return stars
            case .open:                 return 0
            case .locked:               return nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            rung(1, .passed(best: 100, stars: 3))
            rung(2, .open)
            rung(3, .locked)
        }
    }

    private func rung(_ index: Int, _ state: Rung) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(state.isPassed ? Theme.accent : Color.secondary.opacity(0.15))
                    .frame(width: 28, height: 28)
                if state.isPassed {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(index)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(state.isLocked ? Color.secondary : Color.primary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("Challenge %@", "\(index)"))
                    .font(Theme.title(.subheadline))   // the real row's face, one step down
                    .foregroundStyle(state.isLocked ? Color.secondary : Color.primary)
                if let best = state.best {
                    Text(L.t("Best %@%", "\(best)"))
                        .font(.caption2).foregroundStyle(.secondary)
                } else if state.isLocked {
                    // Name the rung that opens it, exactly as the real row does.
                    Text(L.t("Beat Challenge %@ to unlock", "\(index - 1)"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .lineLimit(2).minimumScaleFactor(0.7)

            Spacer(minLength: 4)

            if let stars = state.stars {
                StarRow(stars: stars)
            } else {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

/// A miniature of the Today widget — the same fields, accent capsule and dot row the real
/// one shows, so "this deck is also on your Lock Screen" is a claim the card can back up.
///
/// Inset in `Theme.canvas` rather than `Theme.surface`: it sits *on* a surface card, and
/// the screen colour is what makes it read as a separate little pane.
struct IntroWidgetPreview: View {
    let word: Vocab
    let lesson: Int
    /// Everyone is on rung 1 at first launch, so the call to action is honest as a
    /// constant — nothing here reads progress.
    private let challenge = 1

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Text(L.t("Lesson %@", "\(lesson)"))
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Text(L.t("Ready for Challenge %@?", "\(challenge)"))
                    Image(systemName: "chevron.right").imageScale(.small)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Theme.accent.opacity(0.12), in: Capsule())
            }
            Text(word.kana)
                .font(.title3.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.5)
            if !word.romaji.isEmpty {
                Text(word.romaji).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(word.translation)
                .font(.subheadline).foregroundStyle(Theme.accent)
                .lineLimit(2).minimumScaleFactor(0.7)
            dots
        }
        .multilineTextAlignment(.center)
        .padding(12)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
    }

    /// Same five-dot row as the widget, first dot lit — decorative here, since a picture
    /// of a widget has nothing to page through.
    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(i == 0 ? Theme.accent : Color.secondary.opacity(0.35))
                    .frame(width: i == 0 ? 7 : 6, height: i == 0 ? 7 : 6)
            }
        }
        .padding(.top, 2)
    }
}
