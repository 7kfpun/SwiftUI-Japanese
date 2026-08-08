import SwiftUI

/// One word at a time from the current lesson — the wrist-sized version of TodayView.
///
/// A vertical-page `TabView` carries the paging: the Digital Crown drives it natively,
/// with detents and haptics, which is worth more than a hand-rolled crown binding. Tap is
/// wired on top of it because a tap is what people try first on a card.
struct WatchTodayView: View {
    let today: WatchToday
    @State private var index = 0

    var body: some View {
        TabView(selection: $index) {
            // Indexed rather than keyed by the word: a deck can legitimately repeat a
            // word, and duplicate ids make a TabView selection ambiguous.
            ForEach(Array(today.words.enumerated()), id: \.offset) { position, word in
                card(word).tag(position)
            }
        }
        .tabViewStyle(.verticalPage)
        .onChange(of: today.words) {
            // A shorter deck just arrived from the phone — don't leave selection past
            // its end, which strands the TabView on a page that no longer exists.
            if index >= today.words.count { index = 0 }
        }
    }

    private func card(_ word: TodayShared.Word) -> some View {
        VStack(spacing: 2) {
            header
            Spacer(minLength: 0)
            // Kanji sits above the kana exactly as it does on the phone card, and hides
            // when the source has none (or repeats the kana), same rule as `displaysKanji`.
            if !word.kanji.isEmpty, word.kanji != word.kana {
                Text(word.kanji)
                    .font(WatchTheme.jp(17)).foregroundStyle(.secondary)
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
            // The one thing that has to stay readable at 41mm, so it gets the size budget
            // and the most aggressive scale floor.
            Text(word.kana)
                .font(WatchTheme.jp(30))
                .minimumScaleFactor(0.35).lineLimit(2)
            if !word.romaji.isEmpty {
                Text(word.romaji)
                    .font(.caption2).foregroundStyle(.secondary)
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
            Text(word.meaning)
                .font(.footnote).foregroundStyle(WatchTheme.accent)
                .minimumScaleFactor(0.5).lineLimit(2)
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: advance)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text("Lesson \(today.lesson)")
            if !today.isSynced {
                // Says "these are the starter words" without an alert or an empty state —
                // the deck is still worth reading while the phone catches up.
                Text("· sample").foregroundStyle(.tertiary)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1).minimumScaleFactor(0.7)
    }

    private func advance() {
        guard today.words.count > 1 else { return }
        withAnimation { index = (index + 1) % today.words.count }
    }
}

#Preview {
    WatchTodayView(today: WatchToday())
}
