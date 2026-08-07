import WidgetKit
import SwiftUI

// Cycles through Today's 7 words, read from the App Group snapshot the app writes.

struct TodayEntry: TimelineEntry {
    let date: Date
    let word: TodayShared.Word?
    let lesson: Int
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
    private func currentWords() -> (words: [TodayShared.Word], lesson: Int) {
        let snap = TodayShared.read()
        if let snap, !snap.words.isEmpty { return (snap.words, snap.lesson) }
        return (Self.sampleWords, 1)
    }

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), word: Self.sampleWords[0], lesson: 1)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let (words, lesson) = currentWords()
        completion(TodayEntry(date: Date(), word: words[0], lesson: lesson))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let (words, lesson) = currentWords()
        let now = Date()
        let entries = (0..<min(words.count, 12)).map { i in
            TodayEntry(date: Calendar.current.date(byAdding: .hour, value: i, to: now) ?? now,
                       word: words[i % words.count], lesson: lesson)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct TodayWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TodayEntry
    private let accent = Color(red: 0.06, green: 0.69, blue: 0.75)

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
                VStack(spacing: 4) {
                    Text("Lesson \(entry.lesson)")
                        .font(.caption2).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
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
                    Spacer(minLength: 0)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
        }
        .containerBackground(.background, for: .widget)
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
    TodayEntry(date: .now, word: .init(kana: "がくせい", kanji: "学生", romaji: "gakusei", meaning: "student"), lesson: 1)
}
