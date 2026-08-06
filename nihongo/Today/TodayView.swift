import SwiftUI
import WidgetKit

/// Pure daily-picker: restore a saved selection by id (order preserved), else pick
/// `count` at random. Pure so it's unit-testable.
enum DailyPicker {
    static func pick(from all: [Vocab], count: Int, savedIDs: [String]) -> [Vocab] {
        let restored = savedIDs.compactMap { id in all.first { $0.id == id } }
        return restored.isEmpty ? Array(all.shuffled().prefix(count)) : restored
    }
}

/// A card browser (à la the RN "Today"): shows **7 random words** from the chosen lesson,
/// one per card, with the field toggles, swipe to move, tap to hear. The same 7 feed the
/// home-screen widget. Pick a lesson from the top-right text menu — 1–5 free, 6–50 Premium.
struct TodayView: View {
    @AppStorage(Pref.translationLanguage) private var language = VocabStore.defaultLanguage
    @AppStorage(Pref.todayLesson) private var lessonNumber = 1
    @AppStorage(Pref.todaySelection) private var selectionJSON = ""   // {lesson, romaji:[...]}
    @AppStorage(Pref.kanjiShown)       private var showKanji = true
    @AppStorage(Pref.kanaShown)        private var showKana = true
    @AppStorage(Pref.romajiShown)      private var showRomaji = true
    @AppStorage(Pref.translationShown) private var showTranslation = true
    @AppStorage(Pref.soundOn)          private var soundOn = true
    @Environment(\.pronouncer) private var pronouncer
    @Environment(Store.self) private var store

    @State private var picks: [Vocab] = []
    @State private var index = 0
    @State private var showPaywall = false
    private let dailyCount = 7

    private struct Selection: Codable { let lesson: Int; let ids: [String] }
    private var current: Vocab? { picks.indices.contains(index) ? picks[index] : picks.first }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                CardOptionsBar()
                if let word = current { card(word) } else { ProgressView().frame(maxHeight: .infinity) }
            }
            .padding()
            .background(Theme.canvas)
            .navigationTitle(L.t("Today"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { lessonMenu } }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .onAppear { clampIfLocked(); loadPicks(); autoPlay(); Track.screen("today", ["lesson": lessonNumber]) }
            .onChange(of: index) { autoPlay() }
            .onChange(of: lessonNumber) {
                loadPicks(reshuffle: true); autoPlay()
                Track.event("today_lesson", ["lesson": lessonNumber])
            }
            .onChange(of: language) { loadPicks() }
            .onChange(of: store.isPremium) { clampIfLocked() }
        }
    }

    /// Text label (no icon). Free users can pick 1–5; locked lessons open the paywall.
    private var lessonMenu: some View {
        Menu {
            ForEach(1...50, id: \.self) { n in
                Button {
                    if Gating.isLocked(lesson: n, isPremium: store.isPremium) { showPaywall = true }
                    else { lessonNumber = n }
                } label: {
                    if n == lessonNumber {
                        Label(L.t("Lesson %@", "\(n)"), systemImage: "checkmark")
                    } else if Gating.isLocked(lesson: n, isPremium: store.isPremium) {
                        Label(L.t("Lesson %@", "\(n)"), systemImage: "lock.fill")
                    } else {
                        Text(L.t("Lesson %@", "\(n)"))
                    }
                }
            }
        } label: {
            Text(L.t("Lesson %@", "\(lessonNumber)")).fontWeight(.semibold)
        }
    }

    private func card(_ word: Vocab) -> some View {
        VStack(spacing: 12) {
            if showKanji && word.displaysKanji {
                Text(word.kanji).font(.title2).foregroundStyle(.secondary)
            }
            if showKana {
                Text(word.kana).font(.system(size: 46, weight: .light))
                    .minimumScaleFactor(0.4).multilineTextAlignment(.center)
            }
            if showRomaji {
                Text(word.romaji).font(.title3).foregroundStyle(.secondary)
            }
            if showTranslation {
                Text(word.translation).font(.title3).foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .bottom) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.compact.left")
                Text(L.t("Swipe"))
                Image(systemName: "chevron.compact.right")
            }
            .font(.caption).foregroundStyle(.tertiary).padding(.bottom, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { pronouncer.speak(word) }
        .cardPager(canPage: { picks.count > 1 }) { dir in
            let count = picks.count
            index = dir > 0 ? (index + 1) % count : (index - 1 + count) % count
        }
    }

    /// Choose 7 random words for the lesson (stable per lesson via `todaySelection`), or
    /// re-map the stored 7 into the current language. `reshuffle` forces a fresh pick.
    private func loadPicks(reshuffle: Bool = false) {
        let all = VocabStore.lesson(lessonNumber, language).entries
        var savedIDs: [String] = []
        if !reshuffle,
           let data = selectionJSON.data(using: .utf8),
           let sel = try? JSONDecoder().decode(Selection.self, from: data),
           sel.lesson == lessonNumber {
            savedIDs = sel.ids
        }
        picks = DailyPicker.pick(from: all, count: dailyCount, savedIDs: savedIDs)
        if let data = try? JSONEncoder().encode(Selection(lesson: lessonNumber, ids: picks.map(\.id))),
           let str = String(data: data, encoding: .utf8) {
            selectionJSON = str
        }
        if index >= picks.count { index = 0 }
        publishWidget()
    }

    /// Free users can't stay on a locked lesson — snap back to lesson 1.
    private func clampIfLocked() {
        if Gating.isLocked(lesson: lessonNumber, isPremium: store.isPremium) {
            lessonNumber = 1; index = 0
        }
    }

    /// Publish today's 7 words to the App Group so the widget cycles them.
    private func publishWidget() {
        let words = picks.map {
            TodayShared.Word(kana: $0.kana, kanji: $0.kanji, romaji: $0.romaji, meaning: $0.translation)
        }
        TodayShared.write(.init(lesson: lessonNumber, words: words))
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func autoPlay() {
        if soundOn, let word = current { pronouncer.speak(word) }
    }
}
