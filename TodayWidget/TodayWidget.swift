import WidgetKit
import SwiftUI
import AppIntents   // Button(intent:) — the next-word control

// Cycles through Today's deck — the words the next unpassed rung can ask — read from
// the App Group snapshot the app writes.

struct TodayEntry: TimelineEntry {
    let date: Date
    let word: TodayShared.Word?
    let lesson: Int
    /// How many words are behind this entry — the view hides the dot row when there's
    /// only one, since a single-word challenge deck has nowhere to page to.
    var deckSize: Int = 1
    /// This word's place in the deck, so the dot row knows which dot to light.
    var wordIndex: Int = 0
    /// The challenge these words prepare for — the medium widget turns this into a
    /// call-to-action. Always sent by the current app (a cleared ladder sends its
    /// last rung as a retake); nil only from a pre-field snapshot.
    var challenge: Int? = nil
    /// The whole deck, for the families with room to show more than the current word
    /// (large and extra large). Empty for a hand-built entry, which those layouts treat
    /// as "just the one word".
    var deck: [TodayShared.Word] = []

    /// The words after the current one, wrapping round the deck, never the current word
    /// itself — so the list reads as "what's next" and stays honest as the clock or the
    /// arrows move the cursor.
    func upcoming(_ limit: Int) -> [TodayShared.Word] {
        guard deck.count > 1 else { return [] }
        let n = deck.count
        return (1..<n).prefix(limit).map { deck[(wordIndex + $0) % n] }
    }
}

struct TodayProvider: TimelineProvider {
    /// The shared fallback deck — see `TodayShared.sampleWords`.
    static let sampleWords = TodayShared.sampleWords

    /// The published snapshot, or the sample deck when nothing was published yet.
    /// (The sample claims challenge 1, so the gallery preview shows the CTA too.)
    private func currentWords() -> (words: [TodayShared.Word], lesson: Int, challenge: Int?) {
        let snap = TodayShared.read()
        if let snap, !snap.words.isEmpty { return (snap.words, snap.lesson, snap.challenge) }
        return (Self.sampleWords, 1, 1)
    }

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), word: Self.sampleWords[0], lesson: 1,
                   deckSize: Self.sampleWords.count, challenge: 1,
                   deck: Self.sampleWords)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let (words, lesson, challenge) = currentWords()
        completion(TodayEntry(date: Date(), word: words[0], lesson: lesson,
                              deckSize: words.count, challenge: challenge, deck: words))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let (words, lesson, challenge) = currentWords()
        let now = Date()
        // Tapping and waiting move the same cursor, so a tap doesn't fight the timeline and
        // the widget never jumps back to a word already dismissed.
        let cursor = WidgetPosition.offset

        func entry(at date: Date) -> TodayEntry {
            let idx = TodayShared.rotationIndex(count: words.count, cursor: cursor, at: date)
            return TodayEntry(date: date, word: words[idx], lesson: lesson,
                              deckSize: words.count, wordIndex: idx, challenge: challenge, deck: words)
        }

        // The word is derived from the *hour*, never counted forward from this rebuild —
        // `TodayShared.rotationIndex` documents why that distinction is the whole rotation.
        //
        // First entry is *now* so the current hour is covered immediately; the rest land on
        // clock-hour boundaries rather than `now + n hours`, so the rotation stays on the
        // clock instead of drifting to whenever it was last rebuilt. One entry per word: the
        // 30 is a backstop against a pathological deck, not a design.
        let boundary = TodayShared.nextHour(after: now)
        let entries = [entry(at: now)]
            + (0..<min(words.count, 30)).map { entry(at: boundary.addingTimeInterval(Double($0) * 3600)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct TodayWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TodayEntry
    // Mirrors Theme.accent (app target) — brighter teal in dark so it keeps its
    // pop on the dark widget background.
    private let accent = Color(uiColor: UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.25, green: 0.78, blue: 0.84, alpha: 1)
            : UIColor(red: 0.06, green: 0.69, blue: 0.75, alpha: 1)
    })

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                // One line above the Lock Screen clock.
                if let w = entry.word {
                    Text("\(w.kana) · \(w.meaning)")
                } else {
                    Text("Japanese Daily")
                }
            case .accessoryRectangular:
                // Compact block below the Lock Screen clock (renders vibrant/monochrome).
                VStack(alignment: .leading, spacing: 1) {
                    if let w = entry.word {
                        Text(w.kana)
                            .font(.headline)
                            .minimumScaleFactor(0.6).lineLimit(1)
                        if !w.romaji.isEmpty {
                            Text(w.romaji).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text(w.meaning).font(.caption).lineLimit(1)
                    } else {
                        Text("Open Japanese Daily").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            case .accessoryCircular:
                circular
            case .systemLarge:
                large
            case .systemExtraLarge:
                extraLarge
            default:
                smallOrMedium
            }
        }
        .containerBackground(.background, for: .widget)
        // Deep link so a widget tap is distinguishable from a cold launch — without
        // it the app can't tell whether the home-screen widget drives any returns.
        // The app answers this in `onOpenURL` (nihongoApp.swift).
        .widgetURL(URL(string: "nihongo://widget?lesson=\(entry.lesson)"))
    }

    /// Home-screen small/medium — centered, like a little flashcard.
    /// Interactive widgets are home-screen only: the Lock Screen accessory
    /// families can't take a Button, so they keep cycling on the timeline
    /// alone. WidgetKit has no gestures at all — a widget cannot scroll or
    /// swipe, whatever the affordance looks like — so paging is explicit
    /// buttons. Page dots were tried and read as swipeable, which they
    /// aren't; arrows at least look like what they are. Hidden when there's
    /// nothing to page through.
    @ViewBuilder
    private var smallOrMedium: some View {
        let paging = entry.word != nil && entry.deckSize > 1
        let wide = family == .systemMedium
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text("Lesson \(entry.lesson)")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                // Medium's header has width to spare — spend it daring the
                // learner toward the rung these words prepare for, and make it
                // land there: a `Link` overrides the container's `widgetURL` for
                // its own region, so this opens the challenge while a tap
                // anywhere else still opens the app. Links only carry their own
                // destination on medium and larger, which is where this lives.
                if wide, let c = entry.challenge,
                   let url = URL(string: "nihongo://challenge?lesson=\(entry.lesson)&index=\(c)") {
                    Link(destination: url) {
                        // Same wording and same accent capsule as Today's own
                        // "Ready for Challenge N?" chip — one promise, two
                        // surfaces, so they shouldn't read as different things.
                        HStack(spacing: 4) {
                            Text("Ready for Challenge \(c)?")
                            Image(systemName: "chevron.right").imageScale(.small)
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(accent.opacity(0.12), in: Capsule())
                    }
                }
                // Small is too narrow to flank the word without squeezing a long
                // kana reading, so its controls ride in the header row instead —
                // they cost no extra height there.
                if paging && !wide {
                    HStack(spacing: 0) {
                        stepButton(PreviousWordIntent(), symbol: "chevron.left",
                                   label: "Previous word", side: 22)
                        stepButton(NextWordIntent(), symbol: "chevron.right",
                                   label: "Next word", side: 22)
                    }
                }
            }
            Spacer(minLength: 0)
            // Medium has width to spare, so its controls flank the word like a
            // carousel: larger targets, and the direction reads at a glance.
            HStack(spacing: 2) {
                if paging && wide {
                    stepButton(PreviousWordIntent(), symbol: "chevron.left",
                               label: "Previous word", side: 32)
                }
                card
                if paging && wide {
                    stepButton(NextWordIntent(), symbol: "chevron.right",
                               label: "Next word", side: 32)
                }
            }
            Spacer(minLength: 0)
            if paging { dots }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Lock Screen circular

    /// One glanceable thing: the kana, on the system's frosted disc. No buttons —
    /// accessory families can't take them. Everything is foreground-only so it reads in
    /// vibrant and monochrome rendering alike; no colour carries meaning here.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let w = entry.word {
                Text(w.kana)
                    .font(.headline.weight(.semibold))
                    .minimumScaleFactor(0.35).lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(4)
            } else {
                Image(systemName: "character.book.closed")
                    .font(.title3)
            }
        }
        .widgetAccentable()
    }

    // MARK: - Large

    /// Room for more than a card: the current word big, with its paging arrows and the
    /// challenge link, and the next few words listed underneath so the deck is visible
    /// at a glance. Rows size to their text, never to a fixed height, so a long German
    /// meaning wraps to a second line instead of clipping.
    private var large: some View {
        let paging = entry.word != nil && entry.deckSize > 1
        return VStack(spacing: 8) {
            header
            HStack(spacing: 2) {
                if paging { stepButton(PreviousWordIntent(), symbol: "chevron.left",
                                       label: "Previous word", side: 36) }
                bigCard
                if paging { stepButton(NextWordIntent(), symbol: "chevron.right",
                                       label: "Next word", side: 36) }
            }
            let rest = entry.upcoming(4)
            if !rest.isEmpty {
                Divider()
                VStack(spacing: 6) {
                    ForEach(rest, id: \.self) { w in row(w) }
                }
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Extra large (iPad)

    /// The width is the point: the current word and its controls take the left column,
    /// and the deck fills the right as a grid of cards — each its own little flashcard
    /// — rather than the large layout stretched wide.
    private var extraLarge: some View {
        let paging = entry.word != nil && entry.deckSize > 1
        let others = entry.upcoming(8)
        return VStack(spacing: 12) {
            header
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    bigCard
                    if paging {
                        HStack(spacing: 24) {
                            stepButton(PreviousWordIntent(), symbol: "chevron.left",
                                       label: "Previous word", side: 40)
                            stepButton(NextWordIntent(), symbol: "chevron.right",
                                       label: "Next word", side: 40)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                if !others.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(others, id: \.self) { w in gridCard(w) }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// "Lesson N" and, from medium up, the call-to-action link.
    private var header: some View {
        HStack(spacing: 4) {
            Text("Lesson \(entry.lesson)")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            challengeLink
        }
    }

    @ViewBuilder
    private var challengeLink: some View {
        if let c = entry.challenge,
           let url = URL(string: "nihongo://challenge?lesson=\(entry.lesson)&index=\(c)") {
            Link(destination: url) {
                HStack(spacing: 4) {
                    Text("Ready for Challenge \(c)?")
                    Image(systemName: "chevron.right").imageScale(.small)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(accent.opacity(0.12), in: Capsule())
                .widgetAccentable()
            }
        }
    }

    /// The current word at the size the big families afford.
    @ViewBuilder
    private var bigCard: some View {
        VStack(spacing: 6) {
            if let w = entry.word {
                Text(w.kana)
                    .font(.largeTitle.weight(.semibold))
                    .minimumScaleFactor(0.5).lineLimit(2)
                if !w.romaji.isEmpty {
                    Text(w.romaji).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(w.meaning)
                    .font(.title3).foregroundStyle(accent).widgetAccentable()
                    .lineLimit(3).minimumScaleFactor(0.8)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Nothing published yet — and, on the big families, a symbol to hold the space the
    /// absent word would have.
    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "character.book.closed")
                .font(.largeTitle).foregroundStyle(accent).widgetAccentable()
            Text("Open the app to load today's words")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// One line of the up-next list: the kana, and its meaning wrapping rather than
    /// clipping.
    private func row(_ w: TodayShared.Word) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(w.kana).font(.subheadline.weight(.semibold)).lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(w.meaning).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One tile of the extra-large deck grid. `Theme.canvas` can't be reached from the
    /// extension, so the tile is a faint wash of the label colour — lighter-than-nothing
    /// on either appearance, and it drops out cleanly in tinted rendering.
    private func gridCard(_ w: TodayShared.Word) -> some View {
        VStack(spacing: 2) {
            Text(w.kana).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
            if !w.romaji.isEmpty {
                Text(w.romaji).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Text(w.meaning).font(.caption).foregroundStyle(accent).widgetAccentable()
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    /// The word itself — shared by both home-screen layouts, which differ only in where
    /// they hang the paging controls.
    @ViewBuilder
    private var card: some View {
        VStack(spacing: 4) {
            if let w = entry.word {
                Text(w.kana)
                    .font(.title2.weight(.semibold))
                    .minimumScaleFactor(0.5).lineLimit(1)
                if !w.romaji.isEmpty {
                    Text(w.romaji).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(w.meaning)
                    .font(.subheadline).foregroundStyle(accent).lineLimit(2)
            } else {
                Text("Open the app to load today's words")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// A five-dot window onto the deck, each dot a jump straight to that word.
    ///
    /// The arrows walk; the dots teleport and say where you are. A dot per word would
    /// be honest but unusable here — a challenge pool runs to twenty-odd words, and
    /// twenty 6pt circles across a small widget is a smear with no hit area worth
    /// tapping. Five keeps every target real and still shows movement.
    ///
    /// The window slides with the cursor and clamps at both ends, so the current dot is
    /// centred in the middle of the deck but settles to an edge near its start or end —
    /// the same behaviour a page control has. Outermost dots shrink when the deck
    /// continues past them, which is what distinguishes "more words that way" from
    /// "you're at the end".
    private var dots: some View {
        let window = min(5, entry.deckSize)
        let lo = max(0, min(entry.wordIndex - window / 2, entry.deckSize - window))
        let range = lo..<(lo + window)
        return HStack(spacing: 0) {
            ForEach(range, id: \.self) { i in
                let isCurrent = i == entry.wordIndex
                let continues = (i == range.lowerBound && lo > 0)
                    || (i == range.upperBound - 1 && range.upperBound < entry.deckSize)
                let d: CGFloat = isCurrent ? 7 : (continues ? 4 : 6)
                Button(intent: JumpToWordIntent(target: i)) {
                    Circle()
                        .fill(isCurrent ? accent : Color.secondary.opacity(0.35))
                        .frame(width: d, height: d)
                        .frame(width: 15, height: 15)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Word \(i + 1) of \(entry.deckSize)")
            }
        }
    }

    /// One paging control. Generic over the intent because `Button(intent:)` binds a
    /// concrete `AppIntent` — an existential won't do.
    ///
    /// The glyph is small to stay out of the word's way, but the *hit area* is the `side`
    /// square: a bare `.caption` symbol is about 11pt, which is a miss more often than a
    /// tap on a home screen.
    private func stepButton<I: AppIntent>(_ intent: I, symbol: String,
                                          label: String, side: CGFloat) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .frame(width: side, height: side)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent)
        .accessibilityLabel(label)
    }
}

struct TodayWidget: Widget {
    let kind = "TodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Japanese Daily")
        .description("A word from your current lesson.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Previews
//
// Three states per family: a normal word, a long German meaning (the length a Dynamic
// Type / 19-language layout must survive), and no snapshot at all. Light and dark are the
// preview canvas's appearance toggle — `#Preview(as:)` takes no colour scheme.

private let previewDeck = TodayProvider.sampleWords

private func previewEntry(_ i: Int = 2, meaning: String? = nil, empty: Bool = false) -> TodayEntry {
    let base = previewDeck[i % previewDeck.count]
    let w = TodayShared.Word(kana: base.kana, kanji: base.kanji, romaji: base.romaji,
                             meaning: meaning ?? base.meaning)
    return TodayEntry(date: .now, word: empty ? nil : w, lesson: 1,
                      deckSize: previewDeck.count, wordIndex: i % previewDeck.count,
                      challenge: 1, deck: previewDeck)
}
private let germanLong = "Studentin oder Student einer Universität (Hochschulangehörige)"

#Preview("Small", as: .systemSmall) {
    TodayWidget()
} timeline: {
    previewEntry(); previewEntry(meaning: germanLong); previewEntry(empty: true)
}

#Preview("Medium", as: .systemMedium) {
    TodayWidget()
} timeline: {
    previewEntry(); previewEntry(meaning: germanLong); previewEntry(empty: true)
}

#Preview("Large", as: .systemLarge) {
    TodayWidget()
} timeline: {
    previewEntry(); previewEntry(meaning: germanLong); previewEntry(empty: true)
}

#Preview("Extra large", as: .systemExtraLarge) {
    TodayWidget()
} timeline: {
    previewEntry(); previewEntry(meaning: germanLong); previewEntry(empty: true)
}

#Preview("Circular", as: .accessoryCircular) {
    TodayWidget()
} timeline: {
    previewEntry(); previewEntry(meaning: germanLong); previewEntry(empty: true)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    TodayWidget()
} timeline: {
    previewEntry(); previewEntry(meaning: germanLong); previewEntry(empty: true)
}

#Preview("Inline", as: .accessoryInline) {
    TodayWidget()
} timeline: {
    previewEntry(); previewEntry(meaning: germanLong); previewEntry(empty: true)
}
