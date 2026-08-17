import SwiftUI

/// A spaced-repetition-lite deck over any element type. Cards start in random order.
/// Swipe right = "know it" (retired); swipe left = "don't know" (sent to the back to
/// see again). Repeats until every card has been swiped right. Shared by the Lessons
/// (vocab) and Kana flashcards.
@Observable
final class FlashDeck<Element> {
    private let all: [Element]
    private(set) var deck: [Element]
    private(set) var mastered = 0

    let total: Int

    init(_ items: [Element]) {
        all = items
        deck = items.shuffled()
        total = items.count
    }

    var current: Element? { deck.first }
    var isDone: Bool { deck.isEmpty }
    var remaining: Int { deck.count }

    /// Up to `n` cards after the current one — purely decorative, for the peek of
    /// cards waiting behind the top one.
    func peek(_ n: Int) -> [Element] { Array(deck.dropFirst().prefix(n)) }

    /// Swipe right — known, retire it.
    func know() {
        guard !deck.isEmpty else { return }
        deck.removeFirst()
        mastered += 1
    }

    /// Swipe left — unknown, send to the back to revisit later.
    func dontKnow() {
        guard !deck.isEmpty else { return }
        deck.append(deck.removeFirst())
    }

    func restart() {
        deck = all.shuffled()
        mastered = 0
    }
}

/// The shared Tinder-style flashcard screen: drag/tap gestures, grade buttons, the
/// top count, auto-play, reveal, and the done screen. Callers supply only what's
/// type-specific: the card face, an id (for auto-play change detection), the audio
/// action, and the reveal/summary text.
struct FlashcardScreen<Element, Face: View>: View {
    @State private var deck: FlashDeck<Element>
    @State private var drag: CGSize = .zero
    @State private var revealed = false
    @State private var animating = false   // guards double-grades mid-animation
    @AppStorage(Pref.soundOn) private var soundOn = true

    private let idOf: (Element) -> String
    private let speak: (Element) -> Void
    private let revealLabel: String
    private let summary: (Int) -> String
    private let trackName: String?
    /// Merged into this screen's own two events. It exists so the caller can name what the
    /// deck is *of* — the lesson number, for the vocab deck — which this screen has no way
    /// to know: it is generic over its element and holds nothing but cards. Kana passes
    /// none, because a kana deck is the whole chart and there is nothing to distinguish.
    private let trackParams: [String: Any]
    private let reportItem: ((Element) -> Feedback.Item)?
    private let face: (Element, Bool) -> Face

    private let threshold: CGFloat = 100

    /// `report` is what the flag in the toolbar sends: how to name the card on screen as a
    /// reportable entry. Optional so a caller can decline the affordance entirely; both of
    /// this screen's two callers supply one, which is what makes wiring it here cover both
    /// the Lessons and the Kana flashcards at once.
    init(deck: FlashDeck<Element>,
         id: @escaping (Element) -> String,
         revealLabel: String,
         summary: @escaping (Int) -> String,
         trackName: String? = nil,
         trackParams: [String: Any] = [:],
         speak: @escaping (Element) -> Void,
         report: ((Element) -> Feedback.Item)? = nil,
         @ViewBuilder face: @escaping (Element, Bool) -> Face) {
        _deck = State(initialValue: deck)
        self.idOf = id
        self.revealLabel = revealLabel
        self.summary = summary
        self.trackName = trackName
        self.trackParams = trackParams
        self.speak = speak
        self.reportItem = report
        self.face = face
    }

    var body: some View {
        VStack(spacing: 16) {
            if let card = deck.current {
                cardView(card)
                graders
            } else {
                congrats
            }
        }
        .padding()
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { autoPlay() }
        .onChange(of: deck.current.map(idOf)) { autoPlay() }
        .onChange(of: soundOn) { if soundOn { autoPlay() } }
        // Same toolbar placement as every other quiz/practice screen: counter centered,
        // controls top-right.
        .toolbar {
            ToolbarItem(placement: .principal) { progress }
            // The flag leads the sound toggle, in that order on every screen carrying both.
            // Only while a card is up: on the done screen there is no word on screen for a
            // report to be about.
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let reportItem, let card = deck.current {
                    ReportItemButton(item: reportItem(card))
                }
                SoundToggle()
            }
        }
    }

    private var progress: some View {
        HStack(spacing: 14) {
            Label("\(deck.mastered)", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.correct)
            Label("\(deck.remaining)", systemImage: "rectangle.stack.fill").foregroundStyle(Theme.accent)
            Text("/ \(deck.total)").foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold).monospacedDigit())
    }

    /// The peek stack is a static backdrop — only `topCard` moves. Applying the
    /// drag offset/rotation to the whole ZStack would drag all three at once.
    private func cardView(_ element: Element) -> some View {
        ZStack {
            CardStackPeek(count: deck.peek(2).count)
            topCard(element)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func topCard(_ element: Element) -> some View {
        // Here a swipe is a self-assessment: right means "knew it".
        SwipeCard(drag: drag,
                  threshold: threshold,
                  leftStamp: ("xmark", Theme.wrong),
                  rightStamp: ("checkmark", Theme.correct)) {
            VStack(spacing: 14) {
                face(element, revealed)
                if !revealed {
                    Button { withAnimation { revealed = true } } label: {
                        Label(revealLabel, systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
            .padding(24)
        }
        .onTapGesture { speak(element) }
        .gesture(
            DragGesture()
                .onChanged { if !animating { drag = $0.translation } }
                .onEnded { value in
                    if value.translation.width > threshold { grade(right: true) }
                    else if value.translation.width < -threshold { grade(right: false) }
                    else { withAnimation(.spring) { drag = .zero } }
                }
        )
    }

    /// The grade buttons double as swipe legends: arrows on the outer edges point the
    /// way to swipe for each outcome (left = again, right = got it). Same chip chrome
    /// as the kana swipe quiz's option chips, so every Tinder-like screen matches.
    private var graders: some View {
        HStack(spacing: 12) {
            Button { grade(right: false) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                    Text(L.t("Again"))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.plain)
            .choiceChip(Theme.wrong)

            Button { grade(right: true) } label: {
                HStack(spacing: 6) {
                    Text(L.t("Got it"))
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.plain)
            .choiceChip(Theme.correct)
        }
        .font(Theme.title(.headline))
    }

    private var congrats: some View {
        VStack(spacing: 20) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 72))
                .foregroundStyle(Theme.accent)
            Text(L.t("All done!")).font(Theme.title(.largeTitle, weight: .bold))
            Text(summary(deck.total)).foregroundStyle(.secondary)
            Button {
                withAnimation { deck.restart(); revealed = false; drag = .zero }
                autoPlay()
            } label: {
                Label(L.t("Restart"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func grade(right: Bool) {
        guard !animating else { return }
        animating = true
        // `flashcard_grade` / `kana_flashcard_grade` — the name already says which deck,
        // which is why this stays two names rather than one with a param.
        if let n = trackName {
            Track.event("\(n)_grade", trackParams.merging(["known": right]) { a, _ in a })
        }
        withAnimation(.easeOut(duration: 0.25)) { drag.width = right ? 700 : -700 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if right { deck.know() } else { deck.dontKnow() }
            revealed = false
            drag = .zero
            animating = false
            // `total` because a finished deck of 12 and a finished deck of 60 are not the
            // same achievement, and `_done` carried nothing at all to tell them apart.
            if deck.isDone, let n = trackName {
                Track.event("\(n)_done", trackParams.merging(["total": deck.total]) { a, _ in a })
            }
            autoPlay()
        }
    }

    private func autoPlay() {
        if soundOn, let c = deck.current { speak(c) }
    }
}
