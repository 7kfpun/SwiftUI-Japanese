import WidgetKit
import SwiftUI

// Complications for the watch face. Same job as the Lock Screen accessory families on
// iOS, and deliberately the same code shape: read the App Group snapshot, cycle it.
// The difference is who filled that snapshot — here it's the watch app relaying what
// arrived over WatchConnectivity, because the phone's container stops at iOS.

struct WatchTodayEntry: TimelineEntry {
    let date: Date
    let word: TodayShared.Word?
    let lesson: Int
}

struct WatchTodayProvider: TimelineProvider {
    /// Built-in fallback deck (lesson 1 classics) — shown in the complication gallery and
    /// whenever nothing has synced from the phone yet, so a face is never blank.
    static let sampleWords: [TodayShared.Word] = [
        .init(kana: "わたし", kanji: "私", romaji: "watashi", meaning: "I"),
        .init(kana: "せんせい", kanji: "先生", romaji: "sensei", meaning: "teacher"),
        .init(kana: "がくせい", kanji: "学生", romaji: "gakusei", meaning: "student"),
        .init(kana: "ほん", kanji: "本", romaji: "hon", meaning: "book"),
        .init(kana: "とけい", kanji: "時計", romaji: "tokei", meaning: "watch, clock"),
        .init(kana: "でんわ", kanji: "電話", romaji: "denwa", meaning: "telephone"),
        .init(kana: "くるま", kanji: "車", romaji: "kuruma", meaning: "car"),
    ]

    /// The synced snapshot, or the sample deck when nothing has arrived yet.
    private func currentWords() -> (words: [TodayShared.Word], lesson: Int) {
        let snap = TodayShared.read()
        if let snap, !snap.words.isEmpty { return (snap.words, snap.lesson) }
        return (Self.sampleWords, 1)
    }

    func placeholder(in context: Context) -> WatchTodayEntry {
        WatchTodayEntry(date: Date(), word: Self.sampleWords[0], lesson: 1)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchTodayEntry) -> Void) {
        let (words, lesson) = currentWords()
        completion(WatchTodayEntry(date: Date(), word: words[0], lesson: lesson))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchTodayEntry>) -> Void) {
        let (words, lesson) = currentWords()
        let now = Date()
        // One entry per word, so the rotation eventually reaches the whole deck. This
        // was capped at 12 when a deck was one rung's ~7 new words; a challenge pool
        // runs to the mid-twenties, and with no cursor to page by hand the cap meant
        // the tail of the deck was simply unreachable on the wrist. The 30 matches the
        // iOS widget and is a backstop against a pathological deck, not a design.
        let entries = (0..<min(words.count, 30)).map { i in
            WatchTodayEntry(date: Calendar.current.date(byAdding: .hour, value: i, to: now) ?? now,
                            word: words[i % words.count], lesson: lesson)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct WatchTodayWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WatchTodayEntry
    // Mirrors Theme.accent's dark variant — watch faces have no light appearance.
    private let accent = Color(red: 0.25, green: 0.78, blue: 0.84)

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                // One line beside the face's other inline slot.
                if let w = entry.word {
                    Text("\(w.kana) · \(w.meaning)")
                } else {
                    Text("Japanese Daily")
                }
            case .accessoryCircular:
                // A circle fits the word and nothing else, so the kana carries it alone —
                // the meaning is one tap away in the app.
                // A text style rather than a fixed 17pt: complications have to honour
                // the watch's text-size setting, and a hard size just ignores it.
                Text(entry.word?.kana ?? "日本")
                    .font(.headline.weight(.semibold))
                    .minimumScaleFactor(0.35).lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(2)
            default:
                // accessoryRectangular — same three-line block as the iOS Lock Screen.
                VStack(alignment: .leading, spacing: 1) {
                    if let w = entry.word {
                        Text(w.kana)
                            .font(.headline)
                            .minimumScaleFactor(0.6).lineLimit(1)
                        if !w.romaji.isEmpty {
                            Text(w.romaji).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text(w.meaning).font(.caption).foregroundStyle(accent).lineLimit(1)
                    } else {
                        Text("Open Japanese Daily").font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .containerBackground(for: .widget) {
            // Only the circular family sits as a disc on the face and wants the system's
            // frosted backing; the other two draw straight onto the face.
            if family == .accessoryCircular { AccessoryWidgetBackground() }
        }
        // No `widgetURL`: tapping a complication already launches the watch app, and the
        // watch app has no deep-link surface worth routing to.
    }
}

struct WatchTodayWidget: Widget {
    let kind = "WatchTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchTodayProvider()) { entry in
            WatchTodayWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Japanese Daily")
        .description("A word from your current lesson.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .accessoryRectangular) {
    WatchTodayWidget()
} timeline: {
    WatchTodayEntry(date: .now, word: .init(kana: "がくせい", kanji: "学生", romaji: "gakusei", meaning: "student"), lesson: 1)
}
