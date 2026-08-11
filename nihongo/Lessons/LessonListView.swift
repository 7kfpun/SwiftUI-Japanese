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
                        Section {
                            ForEach(results) { v in
                                VocabRow(vocab: v, showLesson: true)
                            }
                        } header: {
                            // Spelled out rather than `Section(_ title:)` so the count
                            // can take the section-header face like every other header.
                            Text(L.t("%@ results", "\(results.count)"))
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
                let q = query, count = results.count
                searchDebounce = Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled, !q.isEmpty else { return }
                    Track.event("search_vocab", ["query_length": q.count, "results": count])
                }
            }
        }
    }

    /// One fetch of every passed challenge, tallied per lesson. Refreshed on appear so
    /// finishing a challenge and navigating back updates the bar behind you. Collapse
    /// by challenge id first: a CloudKit merge can leave duplicate rows for the same
    /// rung, and counting both would overfill the bar.
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

            // Untouched lessons show no bar at all — an empty track on all 50 rows
            // would read as "nothing works" rather than "nothing started".
            if done > 0 {
                ProgressBar(fraction: fraction)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(done > 0
                            ? L.t("Lesson %@", "\(number)") + ", \(done) / \(total)"
                            : L.t("Lesson %@", "\(number)"))
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
    @Environment(\.pronouncer) private var pronouncer

    var body: some View {
        Button {
            pronouncer.speak(vocab)
            Track.event("play_vocab", ["lesson": vocab.lesson])
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vocab.kana).font(.headline)
                    if vocab.displaysKanji {
                        Text(vocab.kanji).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(vocab.translation)
                        .font(.subheadline)
                        .multilineTextAlignment(.trailing)
                    if showLesson {
                        Text("L\(vocab.lesson)").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Image(systemName: "speaker.wave.2")
                    .font(.caption).foregroundStyle(Theme.accent)
            }
            .contentShape(Rectangle())
        }
        // Plain style so the words read as text, not as a link. The default button
        // style tints its whole label with the accent color, and that tint beats a
        // `.foregroundStyle(.primary)` applied inside the label — only the style
        // change actually keeps the vocabulary black. The speaker icon opts back in
        // to the accent explicitly above.
        .buttonStyle(.plain)
    }
}

#Preview {
    // Needs the container: the rows read challenge progress for their bars.
    LessonListView()
        .tint(Theme.accent)
        .modelContainer(for: ChallengeResult.self, inMemory: true)
}
