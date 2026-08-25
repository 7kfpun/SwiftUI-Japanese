import SwiftUI

/// Read along — the whole lesson read out, as a player rather than as a list that
/// happens to be talking (design 3b).
///
/// The old shape was a toolbar menu that started audio behind the vocabulary list, with
/// a bar pinned to the bottom. That reads as a background process: what is playing now,
/// how far in it is, and what is coming were all inferred from a highlighted row. Here
/// the deck *is* the screen — the current word large, the queue under it, and the two
/// controls that change what you hear (speed, and whether meanings are read) stated on
/// the surface instead of hidden behind a "⋯".
struct ReadAlongView: View {
    let lesson: Lesson
    /// The words to read — whatever cut the vocab list was showing, so "play what I
    /// filtered to" survives the trip to this screen.
    let words: [Vocab]

    @AppStorage(Pref.translationLanguage) private var language = VocabStore.deviceDefaultLanguage
    @AppStorage(Pref.playbackRate) private var playbackRate = 1.0
    @Environment(Store.self) private var store
    @Environment(\.pronouncer) private var pronouncer
    @State private var player = LessonPlayer()
    @State private var showPaywall = false
    /// Which gate opened the paywall — the meanings preview running out, or the speed
    /// dial. One sheet, two reasons, and the funnel is worthless if they report as one.
    @State private var paywallSource = "read_all_meanings"

    /// The speeds offered. 0.8 is the design's ask (shadowing a clip is easier slowed a
    /// notch); the faster two are for review laps. No 0.5 — Kyoko and WhiteCUL both
    /// smear into mush below ~0.7.
    private static let rates: [Double] = [0.8, 1.0, 1.2, 1.5]

    /// The playlist's leading gutter — the track number, or the playing bars. Named
    /// because the expanded row's second line has to indent by exactly this much to sit
    /// under the word rather than under the number.
    private static let gutterWidth: CGFloat = 22
    private static let gutterGap: CGFloat = 12

    /// Reading the meanings aloud is premium **on every lesson**, not only on locked
    /// ones — the same feature should not behave differently depending on where it was
    /// opened from. The list itself stays free, and so does Japanese-only; this gates
    /// one segment.
    private var meaningLocked: Bool { !store.isPremium }

    var body: some View {
        VStack(spacing: 0) {
            playerCard
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            Text(L.t("Playlist"))
                .font(Theme.title(.footnote))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)

            playlist
        }
        .padding(.top, 12)
        .background(Theme.canvas)
        .navigationTitle(L.t("Read along"))
        .navigationBarTitleDisplayMode(.inline)
        // Pause, not the sound toggle. This screen exists to play a lesson; muting it
        // leaves a player that is running and silent, which is a state nobody wants and
        // the one control the screen was missing (there was no way to stop without
        // leaving). The global auto-play setting still lives in Settings, where it
        // governs the screens that speak *incidentally*.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let pausing = !player.isPaused
                    Track.event("read_all_pause", ["lesson": lesson.number,
                                                   "paused": pausing])
                    if pausing { player.pause() } else { player.resume() }
                } label: {
                    Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                        .foregroundStyle(Theme.accent)
                }
                .disabled(!player.isPlaying)
                .accessibilityLabel(player.isPaused ? L.t("Resume") : L.t("Pause"))
            }
        }
        .onAppear {
            Track.screen("read_along", ["lesson": lesson.number])
            ModeVisits.mark(lesson: lesson.number, mode: "read_along")
            // Opening this screen is the request: nobody arrives here to look at a
            // stopped player. The old menu made starting a second, separate decision.
            if !player.isPlaying { start(.japanese) }
        }
        .onDisappear { player.stop(); player.onFinished = nil; player.onLap = nil }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: paywallSource, lesson: lesson.number)
        }
    }

    // MARK: - The player card

    private var playerCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                PlayingBars(active: player.isPlaying)
                    .frame(width: 22, height: 22)
                    .foregroundStyle(Theme.accent)

                VStack(alignment: .leading, spacing: 3) {
                    Text(player.currentWord?.kana ?? words.first?.kana ?? "")
                        .font(Theme.jp(28))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(L.t("Word %@ of %@",
                             "\((player.currentIndex ?? 0) + 1)", "\(max(player.count, words.count))"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                speedMenu
            }

            modePicker

            HStack {
                Text(modeCaption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(16)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1))
    }

    /// Spelled out under the card, because the short segment labels are cumulative and
    /// "+ Example" has to be readable as *including* the meaning rather than replacing
    /// it. The caption is where that promise is made in full.
    private var modeCaption: String {
        switch player.mode {
        case .japanese:    return L.t("Japanese only")
        case .withMeaning: return L.t("Each word, then its meaning")
        case .withExample: return L.t("Each word and meaning, then a sentence and its meaning")
        }
    }

    /// What the player is actually told. A stored 1.2× belongs to a subscription, so a
    /// lapsed one falls back to normal speed rather than quietly keeping the benefit —
    /// see `Gating.rate`.
    private var effectiveRate: Double {
        Gating.rate(playbackRate, isPremium: store.isPremium)
    }

    /// Premium, and it says so before the tap rather than after. A free listener still
    /// hears the whole lesson at normal speed; the dial is the paid part.
    @ViewBuilder
    private var speedMenu: some View {
        if store.isPremium {
            Menu {
                ForEach(Self.rates, id: \.self) { r in
                    Button {
                        playbackRate = r
                        player.rate = r
                        Track.event("read_all_speed", ["rate": r, "lesson": lesson.number])
                    } label: {
                        if r == playbackRate {
                            Label(Self.rateLabel(r), systemImage: "checkmark")
                        } else {
                            Text(Self.rateLabel(r))
                        }
                    }
                }
            } label: {
                ratePill(Self.rateLabel(playbackRate), locked: false)
            }
        } else {
            Button {
                Track.event("locked_speed", ["lesson": lesson.number])
                paywallSource = "playback_speed"
                showPaywall = true
            } label: {
                ratePill(Self.rateLabel(Gating.normalRate), locked: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L.t("Playback speed"))
            .accessibilityHint(L.t("PRO"))
        }
    }

    private func ratePill(_ text: String, locked: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            if locked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.streak)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.canvas, in: Capsule())
        .contentShape(Capsule())
    }

    /// "1×", "0.8×" — numerals and a multiplication sign, the same in every language.
    static func rateLabel(_ r: Double) -> String {
        r == r.rounded() ? "\(Int(r))×" : "\(r)×"
    }

    /// The one choice that changes what you hear, on the surface instead of inside a
    /// menu — and the PRO badge names the gate before the tap rather than after, which
    /// is the difference between an offer and a trap.
    /// What gets read, as one cumulative control.
    ///
    /// The three modes are not parallel choices — each **adds a leg** to the one before:
    /// the word, then its meaning, then a sentence. Spelling that out three times
    /// ("Japanese only" / "Japanese + meaning" / "Japanese + meaning + example") put
    /// three long labels in a row about 110pt wide each, which shrank to unreadable and
    /// then wrapped; and it hid the relationship behind repetition. The short cumulative
    /// labels say the same thing in a third of the width *and* show the ladder, with the
    /// full sentence spelled out once in the caption under the card.
    private var modePicker: some View {
        HStack(spacing: 6) {
            modeSegment(.japanese, title: L.t("Word"))
            modeSegment(.withMeaning, title: L.t("+ Meaning"))
            // Only where the dataset actually has sentences. JLPT carries none, so this
            // rung was a third of the control doing nothing there — and worse than
            // nothing, because it is the paid rung.
            if VocabStore.hasExamples {
                modeSegment(.withExample, title: L.t("+ Example"))
            }
        }
        .padding(3)
        .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 14))
    }

    private func modeSegment(_ mode: ReadMode, title: String) -> some View {
        let selected = player.mode == mode && player.isPlaying
        return Button {
            start(mode)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                // A lock glyph, not the word "PRO" — at this width the badge was wider
                // than the label it qualified.
                if mode.readsBeyondTheWord, meaningLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.streak)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        // Inside a tinted track the selected segment is the one that *lifts* — the
        // house's border rule is about selection on a plain surface, and a border here
        // would draw a box inside a box (see `07-ux-ui.md`).
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 11)
                    .fill(Theme.surface)
                    .shadow(color: Theme.shadow, radius: 2, y: 1)
            }
        }
        .foregroundStyle(selected ? Color.primary : .secondary)
    }

    // MARK: - The playlist

    private var playlist: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(words.enumerated()), id: \.element.id) { i, word in
                        row(i, word).id(word.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            // A results card is a fixed shape, not a document —
            // the bar sat over the content and reported a position nobody needed.
            .scrollIndicators(.hidden)
            .onChange(of: player.currentIndex) { _, new in
                guard let new, new < words.count else { return }
                withAnimation { proxy.scrollTo(words[new].id, anchor: .center) }
            }
        }
    }

    /// A queue row: position, word, meaning, and the bookmark star the vocab list
    /// already offers — filing a word you just heard is the obvious thing to want here.
    /// The playing row expands to add romaji, so the reading is visible for exactly the
    /// word being read and nowhere else.
    private func row(_ i: Int, _ word: Vocab) -> some View {
        let isCurrent = player.currentIndex == i && player.isPlaying
        return VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: Self.gutterGap) {
                    // The star is a **sibling** of the row button, never inside its
                    // label — a Button nested in a Button's label loses its taps to the
                    // outer one, so the star here was a drawn control that only ever
                    // jumped the playback. Same rule `VocabRow` documents.
                    Button {
                        // `i` indexes the *list on screen*, which is longer than the
                        // player's own when a free listener is inside the meanings
                        // preview — `play(word:)` bounds-checks and silently does
                        // nothing there, leaving every row past the seventh dead.
                        // Speaking the word is what a stopped player does anyway.
                        if player.isPlaying, i < player.count {
                            Track.event("read_all_jump", ["lesson": lesson.number,
                                                          "index": i])
                            player.play(word: i)
                        } else if !player.isPlaying {
                            // Only a *stopped* player's rows speak. While the free
                            // preview runs, rows past its end are inert — speaking
                            // there put a second voice over the running lesson.
                            pronouncer.speak(word)
                        }
                    } label: {
                        HStack(spacing: Self.gutterGap) {
                            Group {
                                if isCurrent {
                                    PlayingBars(active: true)
                                        .foregroundStyle(Theme.accent)
                                } else {
                                    Text("\(i + 1)")
                                        .font(.footnote.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: Self.gutterWidth, height: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(word.kana)
                                    .font(Theme.jp(isCurrent ? 20 : 17))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Text(word.translation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 8)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    BookmarkStars(vocab: word)
                }

                if isCurrent {
                    HStack(spacing: 8) {
                        if !word.romaji.isEmpty {
                            Text(word.romaji)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if meaningLocked, !player.mode.readsBeyondTheWord {
                            Text(L.t("PRO reads the meaning too"))
                                .font(.caption2)
                                .foregroundStyle(Color.streak)
                        }
                    }
                    // Indented past the number/bars gutter so the reading sits under the
                    // word it reads. Flush left it lined up with the track number
                    // instead, which made it look like a stray third field rather than
                    // part of the entry above it.
                    .padding(.leading, Self.gutterWidth + Self.gutterGap)
                }

                // The sentence, on every row, whenever the run is reading sentences.
                //
                // On the playing row only would defeat the point: this is *read along*,
                // and following a spoken sentence means having it in front of you before
                // it is spoken, not once it already has been. It appears with the mode
                // rather than on a toggle, because a mode that reads sentences and a
                // list that hides them is one screen disagreeing with itself.
                if player.mode == .withExample, let example = word.example {
                    ExampleSentenceView(example: example,
                                        translation: word.exampleTranslation,
                                        translationFont: .caption2,
                                        alignment: .leading,
                                        spacing: 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    // An inset pane on the row's card — `Theme.canvas` on `Theme.surface`,
                    // the house rule for a pane inside a card.
                    .background(Theme.canvas, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.leading, Self.gutterWidth + Self.gutterGap)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(isCurrent ? Theme.accent : Color.clear, lineWidth: 2))
    }

    // MARK: - Playback

    /// Start (or switch to) a mode. Without premium, the meanings mode gets
    /// `Gating.freeMeaningPreview` words and *then* the paywall — triggered by the
    /// preview reaching its end, never by a timer and never by the tap itself, so
    /// stopping early is left alone. Japanese-only stays free on every lesson and loops
    /// forever.
    private func start(_ mode: ReadMode) {
        let limit = Gating.wordsToRead(mode: mode, count: words.count,
                                       isPremium: store.isPremium)
        let list = Array(words.prefix(limit))
        let isPreview = limit < words.count
        let loops = Gating.loopsForever(mode: mode, isPremium: store.isPremium)

        player.onFinished = isPreview ? {
            Track.event("locked_read_all", ["lesson": lesson.number, "heard": list.count])
            paywallSource = "read_all_meanings"
            showPaywall = true
        } : nil
        // Whether anyone listens past one pass is the question this feature is a bet on,
        // so the lap is the param that matters — one row per wrap, not one per session.
        player.onLap = loops ? { lap in
            Track.event("read_all_loop", ["lesson": lesson.number, "mode": mode.rawValue,
                                          "lap": lap])
        } : nil

        player.rate = effectiveRate
        // No pre-emptive `stop()` here — `toggle` owns that. Stopping first made its
        // same-mode branch unreachable, so tapping the segment that was already playing
        // restarted the lesson from word 1 instead of stopping it: the one thing a
        // second tap on a lit control should never mean.
        let wasPlayingSameMode = player.isPlaying && player.mode == mode
        player.toggle(list, mode: mode, language: language, loops: loops)
        if player.isPlaying {
            Track.event("read_all", ["lesson": lesson.number, "mode": mode.rawValue,
                                     "preview": isPreview])
        } else if wasPlayingSameMode {
            // The second tap on the lit segment — a deliberate stop, not a mode switch,
            // and the only way to end a run without leaving the screen.
            Track.event("read_all_stop", ["lesson": lesson.number, "mode": mode.rawValue])
        }
    }
}

/// Three bars that rise and fall while audio plays — the design's playing indicator.
///
/// Drawn rather than an SF Symbol because the symbol that fits (`waveform`) is a static
/// shape: the point here is that motion says "this is the one playing" at a glance, in a
/// list where every other row looks the same. Stops moving under Reduce Motion, where it
/// keeps its shape and simply holds still.
struct PlayingBars: View {
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                    .scaleEffect(y: scale(i), anchor: .center)
                    .animation(animation(i), value: phase)
            }
        }
        .onAppear { if active && !reduceMotion { phase = true } }
        .onChange(of: active) { phase = active && !reduceMotion }
        .accessibilityHidden(true)
    }

    private func scale(_ i: Int) -> CGFloat {
        guard active, !reduceMotion else { return [0.5, 0.9, 0.65][i] }
        return phase ? [1.0, 0.45, 0.8][i] : [0.4, 1.0, 0.55][i]
    }

    private func animation(_ i: Int) -> Animation? {
        guard active, !reduceMotion else { return nil }
        return .easeInOut(duration: 0.42 + Double(i) * 0.07).repeatForever(autoreverses: true)
    }
}
