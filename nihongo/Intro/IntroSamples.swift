import SwiftUI

/// The still lifes the intro shows: one per Learn mode, the Challenge ladder a lesson
/// in, and the Today widget.
///
/// All of them are **static vignettes over real lesson-1 data** — never a hardcoded
/// word, and never a live mode. Instantiating `PracticeModel` / `LearnModel` or the real
/// mode views would drag in gating, ad slots and session state for a card nobody can
/// play, and each of those views owns a horizontal drag gesture that would fight
/// `cardPager`'s page turn. So these reuse the *chrome* (`SwipeCard`,
/// `SwipeOptionChip`, `VocabRow`, `StarRow`) and answer to taps only.
struct IntroModeSample: View {
    let mode: Intro.Mode
    let entries: [Vocab]
    @Environment(\.pronouncer) private var pronouncer

    /// A different lesson-1 word per mode, rather than the same one four times.
    ///
    /// Tapping through the chips should feel like looking at four modes, and repeating one
    /// vocabulary item made them read as four skins on the same card. Keyed off the mode's
    /// position so it's *stable* — deliberately not `randomElement()`, which would re-deal
    /// on every SwiftUI redraw and make the card twitch (the same reason `LearnSample`
    /// pseudo-shuffles its tiles by hash instead of shuffling).
    private var word: Vocab? {
        guard !entries.isEmpty else { return nil }
        return entries[offset % entries.count]
    }

    /// Vocab List shows three rows starting at 0, so the others start past them: the card
    /// shouldn't teach a word the list above it already showed.
    private var offset: Int {
        switch mode {
        case .vocabList:  return 0
        case .flashcards: return 4
        case .practice:   return 3
        case .match:      return 8
        case .learn:      return 6
        }
    }

    var body: some View {
        Group {
            switch mode {
            case .vocabList:  vocabList
            case .flashcards: flashcard
            case .practice:   practice
            case .match:      match
            case .learn:      learn
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Match — two short columns with one pair already joined.
    ///
    /// Three rows rather than the real mode's five: the card has to fit under a headline
    /// and a chip grid, and the point being made is the *shape* of the task, which three
    /// rows carry as well as five. The columns are deliberately out of step with each
    /// other, because two columns in the same order wouldn't look like a puzzle.
    private var match: some View {
        let rows = Array(entries.dropFirst(offset).prefix(3))
        let meanings = rows.reversed()      // never the same order as the words
        return HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 6) {
                ForEach(rows, id: \.id) { chip($0.kana, japanese: true, joined: $0.id == rows.first?.id) }
            }
            VStack(spacing: 6) {
                ForEach(Array(meanings), id: \.id) { chip($0.translation, japanese: false, joined: $0.id == rows.first?.id) }
            }
        }
    }

    /// One Match tile. `joined` marks the single pair shown as already cleared — the
    /// accent border is the same selection language the real mode uses, and green stays
    /// where it belongs, on actual answer feedback.
    private func chip(_ text: String, japanese: Bool, joined: Bool) -> some View {
        Text(text)
            .font(japanese ? Theme.jp(15) : .system(.caption, weight: .medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 30)
            .padding(.horizontal, 4)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.accent, lineWidth: joined ? 1.5 : 0))
            .opacity(joined ? 1 : 0.55)
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

    /// Flashcards — the front of a card, which is the whole mode: no verdict, no
    /// options, just the word. The one vignette with nothing being asked.
    @ViewBuilder private var flashcard: some View {
        if let word {
            SwipeCard(showsHint: false) {
                VStack(spacing: 6) {
                    Text(word.kana)
                        .font(Theme.jp(32))
                        .lineLimit(1).minimumScaleFactor(0.4)
                    if word.displaysKanji {
                        Text(word.kanji).font(Theme.jp(17)).foregroundStyle(.secondary)
                    }
                }
                .padding(16)
            }
            .contentShape(Rectangle())
            .onTapGesture { pronouncer.speak(word) }
        }
    }

    /// Practice — the quiz face: the prompt over the mode's own two option chips, left
    /// unanswered (`picked: nil`), which is exactly the state whose chevrons read as
    /// "swipe this way". `PracticeModel.optionCount` is 2, so two is the honest number.
    /// The quiz half rather than the card half, because the card is a flashcard anyone
    /// recognises — the swipe-to-answer is the part worth previewing.
    @ViewBuilder private var practice: some View {
        if let word, let other = distractor {
            VStack(spacing: 10) {
                Text(word.kana)
                    .font(Theme.jp(30))
                    .lineLimit(1).minimumScaleFactor(0.4)
                    .contentShape(Rectangle())
                    .onTapGesture { pronouncer.speak(word) }
                HStack(spacing: 10) {
                    chip(word, side: 0, isAnswer: true)
                    chip(other, side: 1, isAnswer: false)
                }
            }
        }
    }

    /// The wrong option: the next word along, so the pair is a real 50/50 from the lesson
    /// rather than the prompt shown twice. Wraps, so it can't collide with `word`.
    private var distractor: Vocab? {
        guard entries.count > 1 else { return nil }
        return entries[(offset + 1) % entries.count]
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
/// The ladder's anatomy — filled accent circle with a checkmark once passed, the
/// `StarRow`, the same `Best %@%` / `Beat Challenge %@ to unlock` captions — rebuilt here
/// rather than reused, because the real row takes a `ChallengeResult` and fabricating
/// `@Model` rows for a mockup would mean inserting invented history into a CloudKit-backed
/// store. Nothing is persisted by this view; it is a picture of a row, not a row.
struct IntroChallengeRungs: View {
    /// The three states a rung can be in, mirroring the real strip's chips.
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
