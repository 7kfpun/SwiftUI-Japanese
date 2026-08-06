import SwiftUI

struct LessonListView: View {
    @AppStorage("translationLanguage") private var language = VocabStore.defaultLanguage
    @State private var query = ""
    @State private var group = 0

    private static let groups: [(String, ClosedRange<Int>)] = [
        ("Beginning 1", 1...13),
        ("Beginning 2", 14...25),
        ("Advanced 1", 26...38),
        ("Advanced 2", 39...50),
    ]

    private var results: [Vocab] { searchVocab(query, in: VocabStore.allVocab(language)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if query.isEmpty {
                    Picker("", selection: $group) {
                        ForEach(Self.groups.indices, id: \.self) { i in
                            Text(L.t(Self.groups[i].0)).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                List {
                    if query.isEmpty {
                        ForEach(Self.groups[group].1, id: \.self) { n in
                            NavigationLink(value: VocabStore.lesson(n, language)) {
                                Text(L.t("Lesson %@", "\(n)"))
                            }
                        }
                    } else {
                        Section(L.t("%@ results", "\(results.count)")) {
                            ForEach(results) { v in
                                VocabRow(vocab: v, showLesson: true)
                            }
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))   // match the grouped List behind the picker
            .navigationTitle(L.t("Lessons"))
            .onAppear { Track.screen("lessons") }
            .onChange(of: group) { Track.event("lesson_group", ["group": group]) }
            .navigationDestination(for: Lesson.self) { SelectModeView(lesson: $0) }
            .searchable(text: $query, prompt: L.t("Search vocabulary"))
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
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
            .foregroundStyle(.primary)   // keep text neutral; the row still greys on tap
        }
    }
}

#Preview { LessonListView().tint(Theme.accent) }
