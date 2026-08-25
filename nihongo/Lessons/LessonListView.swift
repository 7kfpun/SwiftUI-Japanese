import SwiftUI
import SwiftData

struct LessonListView: View {
    @AppStorage(Pref.translationLanguage) private var language = VocabStore.deviceDefaultLanguage
    @State private var query = ""
    @State private var group = 0
    @State private var searchDebounce: Task<Void, Never>?
    @Environment(\.modelContext) private var context
    /// challenges passed, keyed by lesson — one fetch for the whole list rather than
    /// a query per visible row.
    @State private var passed: [Int: Int] = [:]
    /// The stack lives on the router so the widget's "Ready for Challenge N?" link can
    /// push lesson + rung directly. Row taps append to the same path.
    @Environment(Router.self) private var router
    private static let groups = Course.current.groups

    /// Search hits for the current query.
    ///
    /// **Evaluate this once per body pass**, into a `let`, and use that for both the rows
    /// and the count — see `body`. Each call rebuilds the flattened corpus and lowercases
    /// four fields per entry, which is ~8k allocations for Minna and ~32k for JLPT; read
    /// as a computed property from three places it ran that three times per keystroke and
    /// stuttered the keyboard.
    private var results: [Vocab] { searchVocab(query, in: VocabStore.allVocab(language)) }

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.lessonPath) {
            VStack(spacing: 0) {
                if query.isEmpty {
                    Picker("", selection: $group) {
                        ForEach(Self.groups.indices, id: \.self) { i in
                            Text(L.t(Self.groups[i].name)).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // What the band adds up to, under the band's own control. The rows
                    // each carry a lesson's standing; this is the only place that says
                    // how the *group* is going, which is the question the picker asks.
                    Text(groupSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }

                List {
                    if query.isEmpty {
                        ForEach(Self.groups[group].range, id: \.self) { n in
                            NavigationLink(value: VocabStore.lesson(n, language)) {
                                LessonRow(number: n,
                                          done: passed[n] ?? 0,
                                          total: Challenge.count(
                                            wordCount: VocabStore.lesson(n, language).entries.count))
                            }
                        }
                    } else {
                        // One evaluation, shared by the rows and the header count.
                        let hits = results
                        Section {
                            if hits.isEmpty {
                                // Names the query and what is searchable. "0 results"
                                // alone leaves a learner unsure whether the word is
                                // absent or whether they typed in the wrong script —
                                // and this corpus takes all four.
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(L.t("Nothing matched “%@”.", query))
                                        .font(.subheadline)
                                    Text(L.t("Try kana, kanji, romaji or the meaning."))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6)
                                .listRowSeparator(.hidden)
                            }
                            ForEach(hits) { v in
                                VocabRow(vocab: v, showLesson: true)
                            }
                        } header: {
                            // Spelled out rather than `Section(_ title:)` so the count
                            // can take the section-header face like every other header.
                            Text(L.t("%@ results", "\(hits.count)"))
                                .font(Theme.title(.footnote))
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))   // match the grouped List behind the picker
            .navigationTitle(L.t("Lessons"))
            .onAppear { Track.screen("lessons"); reloadProgress() }
            .onChange(of: group) { Track.event("lesson_group", ["group": group]) }
            .navigationDestination(for: Lesson.self) { SelectModeView(lesson: $0) }
            .searchable(text: $query, prompt: L.t("Search vocabulary"))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onChange(of: query) {
                searchDebounce?.cancel()
                let q = query
                searchDebounce = Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled, !q.isEmpty else { return }
                    // Counted *inside* the debounce. Reading `results.count` here cost a
                    // whole extra corpus pass on every keystroke, to fill a param on an
                    // event that only fires once the typing stops.
                    Track.event("search_vocab", ["query_length": q.count,
                                                 "results": searchVocab(q, in: VocabStore.allVocab(language)).count])
                }
            }
        }
    }

    /// One fetch of every passed challenge, tallied per lesson. Refreshed on appear so
    /// finishing a challenge and navigating back updates the bar behind you. Collapse
    /// by challenge id first: a CloudKit merge can leave duplicate rows for the same
    /// rung, and counting both would overfill the bar.
    /// "Lesson 1–13 · 13 lessons · 6 challenges passed" — the band's range, its size,
    /// and how much of it is behind you.
    ///
    /// Counted from the same `passed` tally the rows use, so the summary and the bars
    /// can never disagree; a second fetch here would be a second source of truth for one
    /// number.
    private var groupSummary: String {
        let band = Self.groups[group]
        let cleared = band.range.reduce(0) { $0 + (passed[$1] ?? 0) }
        let lessons = L.t("%@ lessons", "\(band.range.count)")
        let rungs = L.t("%@ challenges passed", "\(cleared)")
        return "\(L.t("Lesson %@", "\(band.first)–\(band.last)")) · \(lessons) · \(rungs)"
    }

    private func reloadProgress() {
        let descriptor = FetchDescriptor<ChallengeResult>()
        let rows = (try? context.fetch(descriptor)) ?? []
        let unique = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: ChallengeResult.better)
        passed = unique.values.filter(\.isPassed).reduce(into: [:]) { tally, row in
            tally[row.lesson, default: 0] += 1
        }
    }
}

/// A lesson row with its challenge progress — the bar is the reason to come back, so
/// it sits on the screen you see most rather than one level in. Laid out to match the
/// promo site's lesson list: numbered badge, title, then the bar trailing.
private struct LessonRow: View {
    let number: Int, done: Int, total: Int

    private var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            // The row's name, so it takes the title face — but at the weight it already
            // had. `Theme.title`'s default semibold across all fifty rows reads as fifty
            // headings competing with each other rather than a list.
            Text(L.t("Lesson %@", "\(number)"))
                .font(Theme.title(.body, weight: .regular))

            Spacer(minLength: 12)

            // Untouched lessons show nothing at all — an empty track and a "0 / 6" on
            // all fifty rows would read as "nothing works" rather than "nothing
            // started". Once a lesson is under way the count leads the bar: the bar
            // says *roughly how far*, the numbers say exactly, and on a ladder of six
            // rungs the difference between 4 and 5 is worth reading rather than
            // estimating from 16pt of fill.
            if done > 0 {
                Text("\(done) / \(total)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                ProgressBar(fraction: fraction)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(done > 0
                            ? L.t("Lesson %@", "\(number)") + ", \(done) / \(total)"
                            : L.t("Lesson %@", "\(number)"))
    }
}

/// Where a word stands, as one dot before its reading.
///
/// Three states drawn as fill rather than as three different glyphs: down a list of
/// forty-six rows the eye is scanning for *pattern*, and a solid/hollow/outline
/// progression reads at a glance where three icons would each have to be identified.
/// It is the same `PracticeProgress` stage the lesson screen counts and the Practice
/// ladder shows — one fact, three surfaces.
struct StageDot: View {
    let stage: WordStage

    var body: some View {
        Circle()
            .fill(stage == .memorized ? Theme.accent
                  : stage >= .seen ? Theme.accent.opacity(0.35) : Color.clear)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(stage == .unseen ? Theme.line : .clear, lineWidth: 1))
            .padding(.top, 6)   // sits with the reading's cap height, not the row's centre
            .accessibilityHidden(true)
    }
}

/// A slim capsule progress bar. Fixed width so the bars line up down the list instead
/// of jittering with each row's title length.
private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.18))
            .frame(width: 92, height: 6)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * max(0, min(fraction, 1)))
                }
            }
            .accessibilityHidden(true)   // the row's combined label already says n / m
    }
}

/// A single vocabulary row (used in vocab lists and search results).
struct VocabRow: View {
    let vocab: Vocab
    var showLesson = false
    /// Whether to show the example sentence under the word. Driven by the screen's
    /// one global toggle, never per-row state — tapping rows open was tried and read
    /// as the tap doing two unrelated things at once.
    var showExample = false
    /// The word's Practice stage, drawn as a dot before the reading. Optional because
    /// only the vocab list has a stage to show — search results span lessons and the
    /// bookmarks shelf is about the user's own filing, so neither wants the mark.
    var stage: WordStage? = nil
    /// The word's tier, when the *screen* tracks one.
    ///
    /// The vocab list keeps a tier map for its cut counts, so passing it in makes the
    /// list the single source and `BookmarkStars` the view of it — otherwise the
    /// control's own fetched state and the list's map drift apart. Nil elsewhere, where
    /// the control simply reads its own.
    var savedTier: Int?? = nil
    /// Called when the row's own control changes the tier, so the list can re-read its
    /// map — the counts on the cut chips depend on it.
    var onTierChange: ((Int?) -> Void)? = nil
    @Environment(\.pronouncer) private var pronouncer

    /// One action, three tappable surfaces (word line, meaning line, speaker glyph):
    /// the row *is* the word, so all its text speaks it.
    private func speakWord() {
        pronouncer.speak(vocab)
        Track.event("play_vocab", ["lesson": vocab.lesson])
    }

    var body: some View {
        // Two lines, each pairing its text with its control: the word with the
        // speaker, the meaning with the star. The controls used to sit in one trailing
        // column centred on the whole row, which meant neither icon lined up with the
        // line it belonged to — the speaker floated between the two lines and the star
        // hung below the meaning. Per-line alignment is what makes the row read as two
        // facts with two affordances rather than a text block with a gadget rail.
        //
        // The word text and the speaker are two sibling buttons doing the same thing —
        // never nested: nested buttons in a `List` row make the whole row ambiguous to
        // hit, and tapping a star must not also play audio.
        VStack(alignment: .leading, spacing: 2) {
        HStack(alignment: .center, spacing: 8) {
            Button(action: speakWord) {
                // One left-aligned stack (design 3a): the meaning sits under the word
                // it belongs to. The old layout pushed it to the row's far edge, so on
                // a wide screen the eye crossed a gulf of whitespace per word — a list
                // is scannable when each entry is one shape, not two ends of a rubber
                // band.
                HStack(alignment: .top, spacing: 10) {
                    if let stage { StageDot(stage: stage) }
                    // Kanji beside the reading rather than under it: the pair is one
                    // word, and stacked they read as two entries.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(vocab.kana).font(.headline)
                        if vocab.displaysKanji {
                            Text(vocab.kanji).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            // Plain style so the words read as text, not as a link. The default button
            // style tints its whole label with the accent color, and that tint beats a
            // `.foregroundStyle(.primary)` applied inside the label — only the style
            // change actually keeps the vocabulary black. The speaker opts back in below.
            .buttonStyle(.plain)

            Button(action: speakWord) {
                // Body-sized with a real frame: the caption-sized glyph was a
                // ~20pt target for the row's most-used control.
                Image(systemName: "speaker.wave.2")
                    .font(.body).foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }

        HStack(alignment: .center, spacing: 8) {
            Button(action: speakWord) {
                HStack(spacing: 6) {
                    Text(vocab.translation)
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                    if showLesson {
                        Text("L\(vocab.lesson)").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                // Indented under the word, past the stage dot's slot, so both lines
                // start at the same x and the dot stays the row's only left-edge mark.
                .padding(.leading, stage != nil ? 18 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // In swipe-first mode the control appears once the word is saved, and
            // is then tappable as many times as it takes — see `savedTier`.
            // One tap cycles ★1 → ★2 → ★3 → none. `tier`/`onTierChange` are how a
            // screen that keeps its own tier map (the vocab list, for its cut counts)
            // stays the single source. Constant width, so it sits flush under the
            // speaker at any tier.
            BookmarkStars(vocab: vocab, tier: savedTier, onChange: onTierChange)
                .frame(width: 40)
        }

        // The example, unfolded under the row. Its own button — tapping the sentence
        // speaks the *sentence*, where tapping the row speaks the word — and live TTS
        // for now, so nothing here depends on the unbundled sentence clips.
        if showExample, let example = vocab.example {
            Button {
                pronouncer.speak(example: vocab)
                Track.event("play_example", ["lesson": vocab.lesson,
                                             "surface": "vocab_list"])
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    ExampleSentenceView(example: example)
                    if let tr = vocab.exampleTranslation {
                        Text(tr).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                // An inset pane, so the sentence reads as the row's attachment rather
                // than another row — Theme.canvas on the Theme.surface card, per the
                // house rule that inset panes take canvas.
                .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        }
        }
    }
}

#Preview {
    // Needs the container: the rows read challenge progress for their bars.
    LessonListView()
        .tint(Theme.accent)
        .modelContainer(for: ChallengeResult.self, inMemory: true)
}
