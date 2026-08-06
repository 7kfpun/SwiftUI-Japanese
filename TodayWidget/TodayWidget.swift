import WidgetKit
import SwiftUI

// Cycles through Today's 7 words, read from the App Group snapshot the app writes.

struct TodayEntry: TimelineEntry {
    let date: Date
    let word: TodayShared.Word?
    let lesson: Int
}

struct TodayProvider: TimelineProvider {
    private let sample = TodayShared.Word(kana: "わたし", kanji: "私", romaji: "watashi", meaning: "I")

    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), word: sample, lesson: 1)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let s = TodayShared.read()
        completion(TodayEntry(date: Date(), word: s?.words.first ?? sample, lesson: s?.lesson ?? 1))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let snap = TodayShared.read()
        let words = snap?.words ?? []
        let lesson = snap?.lesson ?? 1
        let now = Date()
        var entries: [TodayEntry] = []
        let count = max(1, min(words.count, 12))
        for i in 0..<count {
            let date = Calendar.current.date(byAdding: .hour, value: i, to: now) ?? now
            entries.append(TodayEntry(date: date, word: words.isEmpty ? nil : words[i % words.count], lesson: lesson))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct TodayWidgetEntryView: View {
    var entry: TodayEntry
    private let accent = Color(red: 0.06, green: 0.69, blue: 0.75)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, word: .init(kana: "がくせい", kanji: "学生", romaji: "gakusei", meaning: "student"), lesson: 1)
}
