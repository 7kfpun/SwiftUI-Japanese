import WidgetKit
import SwiftUI
import AppIntents   // Button(intent:) — the next-word control

// Cycles through Today's 7 words, read from the App Group snapshot the app writes.

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
}

struct TodayProvider: TimelineProvider {
    /// Built-in fallback deck (lesson 1 classics) — shown in the widget gallery and
    /// whenever the app hasn't published a snapshot yet, so the widget is never empty.
    static let sampleWords: [TodayShared.Word] = [
        .init(kana: "わたし", kanji: "私", romaji: "watashi", meaning: "I"),
        .init(kana: "せんせい", kanji: "先生", romaji: "sensei", meaning: "teacher"),
        .init(kana: "がくせい", kanji: "学生", romaji: "gakusei", meaning: "student"),
        .init(kana: "ほん", kanji: "本", romaji: "hon", meaning: "book"),
        .init(kana: "とけい", kanji: "時計", romaji: "tokei", meaning: "watch, clock"),
        .init(kana: "でんわ", kanji: "電話", romaji: "denwa", meaning: "telephone"),
        .init(kana: "くるま", kanji: "車", romaji: "kuruma", meaning: "car"),
    ]

    /// The published snapshot, or the sample deck when nothing was published yet.
    /// (The sample claims challenge 1, so the gallery preview shows the CTA too.)
    private func currentWords() -> (words: [TodayShared.Word], lesson: Int, challenge: Int?) {
        let snap = TodayShared.read()
        if let snap, !snap.words.isEmpty { return (snap.words, snap.lesson, snap.challenge) }
        return (Self.sampleWords, 1, 1)
    }

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), word: Self.sampleWords[0], lesson: 1,
                   deckSize: Self.sampleWords.count, challenge: 1)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let (words, lesson, challenge) = currentWords()
        completion(TodayEntry(date: Date(), word: words[0], lesson: lesson,
                              deckSize: words.count, challenge: challenge))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let (words, lesson, challenge) = currentWords()
        let now = Date()
        // Start wherever the dots left the cursor, then keep cycling hourly from
        // there. Tapping and waiting move the same cursor, so a tap doesn't fight the
        // timeline and the widget never jumps back to a word you've already dismissed.
        let start = WidgetPosition.offset
        // One entry per word, so an hourly rotation eventually shows the whole deck.
        // This was capped at 12 when a deck was one rung's ~7 new words; a challenge
        // pool runs to the mid-twenties, and the cap meant the reload restarted at the
        // same cursor — the tail of the deck could never come up by waiting, only by
        // tapping. The 30 is a backstop against a pathological deck, not a design.
        let entries = (0..<min(words.count, 30)).map { i in
            let idx = WidgetPosition.wrapped(start &+ i, count: words.count)
            return TodayEntry(date: Calendar.current.date(byAdding: .hour, value: i, to: now) ?? now,
                              word: words[idx], lesson: lesson,
                              deckSize: words.count, wordIndex: idx, challenge: challenge)
        }
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
            default:
                // Home-screen small/medium — centered, like a little flashcard.
                // Interactive widgets are home-screen only: the Lock Screen accessory
                // families can't take a Button, so they keep cycling on the timeline
                // alone. WidgetKit has no gestures at all — a widget cannot scroll or
                // swipe, whatever the affordance looks like — so paging is explicit
                // buttons. Page dots were tried and read as swipeable, which they
                // aren't; arrows at least look like what they are. Hidden when there's
                // nothing to page through.
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
        }
        .containerBackground(.background, for: .widget)
        // Deep link so a widget tap is distinguishable from a cold launch — without
        // it the app can't tell whether the home-screen widget drives any returns.
        // The app answers this in `onOpenURL` (nihongoApp.swift).
        .widgetURL(URL(string: "nihongo://widget?lesson=\(entry.lesson)"))
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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, word: .init(kana: "がくせい", kanji: "学生", romaji: "gakusei", meaning: "student"),
               lesson: 1, deckSize: TodayProvider.sampleWords.count, wordIndex: 2)
}

#Preview(as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, word: .init(kana: "がくせい", kanji: "学生", romaji: "gakusei", meaning: "student"),
               lesson: 1, deckSize: TodayProvider.sampleWords.count, wordIndex: 2)
}
