import SwiftUI
import SwiftData

/// The lesson screen (design 2a): a per-word standing bar, the Practice hero, the
/// other modes as status-carrying rows, and the Challenge ladder as a chip strip
/// with one "next up" card and one "worth retrying" card.
///
/// A custom scroll page rather than a `List`: the hero is a dark card, the ladder is
/// horizontal, and the rows carry trailing status — three things a `List` fights.
struct SelectModeView: View {
    let lesson: Lesson
    @AppStorage(Pref.translationLanguage) private var language = VocabStore.deviceDefaultLanguage
    @Environment(Store.self) private var store
    @Environment(Unlock.self) private var unlock
    @Environment(PracticeProgress.self) private var practice
    @Environment(\.modelContext) private var context
    @State private var showPaywall = false
    /// Which row opened the paywall — a locked mode or a locked challenge rung. Every
    /// presenting path overwrites this before the sheet appears, so the initial value
    /// is unreachable on purpose; it exists only so the property needs no optional.
    @State private var paywallSource = "locked_mode"
    @State private var results: [Int: ChallengeResult] = [:]
    /// Whether the previous lesson's ladder is fully passed — see
    /// `ChallengeResult.previousLessonCleared`. Defaults open so lesson 1 (and the
    /// first render before `reloadResults`) never flashes a lock it doesn't mean.
    @State private var previousCleared = true
    /// Which modes this lesson has seen — drives the rows' trailing status.
    @State private var visits: Set<String> = []

    // Re-resolve so entering a mode uses the current Meanings language.
    private var current: Lesson { VocabStore.lesson(lesson.number, language) }

    /// The one place lesson gating is enforced: locked rows open the paywall instead of
    /// navigating, so no practice screen has to police access itself.
    private var locked: Bool {
        Gating.isLocked(lesson: lesson.number, isPremium: store.isPremium,
                        earnedFirstGroup: unlock.earnedFirstGroup)
    }

    private var challengeCount: Int { Challenge.count(wordCount: current.entries.count) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                standing
                practiceHero
                otherWays
                challengeSection
            }
            .padding(16)
        }
        // A results card is a fixed shape, not a document —
        // the bar sat over the content and reported a position nobody needed.
        .scrollIndicators(.hidden)
        .background(Theme.canvas)
        .navigationTitle(L.t("Lesson %@", "\(lesson.number)"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Track.screen("select_mode", ["lesson": lesson.number])
            reloadResults()
            visits = ModeVisits.all(lesson: lesson.number)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: paywallSource, lesson: lesson.number)
        }
    }

    // MARK: - Standing (the per-word bar)

    /// Where the lesson stands, word by word: one proportional bar — memorized solid,
    /// recognized faded, unseen on the line colour — and the counts spelled out under
    /// it. Proportional rather than one segment per word, because JLPT lessons run to
    /// dozens of words and forty hairline pips read as texture, not progress.
    private var standing: some View {
        let counts = practice.counts(for: current.entries)
        let total = max(current.entries.count, 1)
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 3) {
                    segment(geo, count: counts.memorized, total: total, color: Theme.accent)
                    segment(geo, count: counts.recognized, total: total, color: Theme.accent.opacity(0.35))
                    segment(geo, count: counts.unseen, total: total, color: Theme.line)
                }
            }
            .frame(height: 6)
            Text(L.t("%@ memorized · %@ recognized · %@ unseen",
                     "\(counts.memorized)", "\(counts.recognized)", "\(counts.unseen)"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func segment(_ geo: GeometryProxy, count: Int, total: Int, color: Color) -> some View {
        if count > 0 {
            Capsule().fill(color)
                .frame(width: max(6, geo.size.width * CGFloat(count) / CGFloat(total) - 3))
        }
    }

    // MARK: - The hero

    /// The default next action gets the page's one heavy card — `Color.primary` on the
    /// canvas, so it inverts cleanly in dark mode. Everything on it takes the inverse
    /// (`systemBackground`) foreground.
    private var practiceHero: some View {
        Group {
            if locked {
                Button {
                    paywallSource = "locked_mode"
                    showPaywall = true
                    Track.event("locked_mode", ["mode": "practice", "lesson": lesson.number])
                } label: { heroCard }
            } else {
                NavigationLink {
                    Deferred { PracticeView(lesson: current, progress: practice) }
                } label: { heroCard }
            }
        }
        .buttonStyle(.plain)
    }

    private var heroCard: some View {
        let counts = practice.counts(for: current.entries)
        let total = max(current.entries.count, 1)
        // The session Practice would deal right now: the non-memorized words — or the
        // whole lesson again, as review, once everything is memorized.
        let cards = counts.recognized + counts.unseen
        let queue = cards == 0 ? total : cards
        // ~20s per card-then-quiz round trip; a rough promise, deliberately rounded up.
        let minutes = max(1, Int((Double(queue) * 20 / 60).rounded(.up)))

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L.t("Up next"))
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                Spacer()
                Text(L.t("About %@ min · %@ cards", "\(minutes)", "\(queue)"))
                    .font(.caption)
                    .monospacedDigit()
            }
            .opacity(0.65)

            HStack(spacing: 12) {
                // Not the card-stack glyph any more — Flashcards owns that, and it *is*
                // a stack of cards. Practice is the one that teaches and tests.
                Image(systemName: "graduationcap")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("Practice")).font(Theme.title(.title2))
                    Text(L.t("Cards first, then a quick quiz"))
                        .font(.footnote)
                        .opacity(0.65)
                }
                Spacer(minLength: 12)
                if locked {
                    Image(systemName: "lock.fill").font(.subheadline).opacity(0.7)
                } else {
                    // The stated verb. Visual only — the whole card is the link.
                    Text(L.t("Start"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color(.systemBackground)))
                }
            }

            // How much of the lesson is banked, drawn on the card itself.
            // `total` is already `max(count, 1)`, and `CapsuleBar` clamps — no guard.
            CapsuleBar(fraction: Double(counts.memorized) / Double(total),
                       height: 4,
                       track: Color(.systemBackground).opacity(0.25),
                       fill: Color(.systemBackground))
                .accessibilityLabel(L.t("%@ memorized · %@ recognized · %@ unseen",
                                        "\(counts.memorized)", "\(counts.recognized)",
                                        "\(counts.unseen)"))
        }
        .foregroundStyle(Color(.systemBackground))
        .padding(18)
        .background(Color.primary, in: RoundedRectangle(cornerRadius: 22))
    }

    // MARK: - The other modes

    private var otherWays: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("Other ways to practice"))
                .font(Theme.title(.footnote))
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                // Vocab List is free on every lesson — browsing and search stay open.
                NavigationLink { Deferred { VocabListView(lesson: current) } } label: {
                    wayRow(key: "vocab_list", icon: "list.bullet", title: L.t("Vocab List"),
                           subtitle: L.t("Browse & hear all words"), gated: false)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 56)
                // Second because it asks *nothing*: a deck to page through before
                // anything starts testing you.
                way(key: "flashcards", icon: "rectangle.on.rectangle.angled",
                    title: L.t("Flashcards"),
                    subtitle: L.t("Swipe through the words")) { FlashcardView(lesson: current) }
                Divider().padding(.leading, 56)
                way(key: "match", icon: "link", title: L.t("Match"),
                    subtitle: L.t("Pair each word with its meaning")) { MatchView(lesson: current) }
                Divider().padding(.leading, 56)
                way(key: "learn", icon: "square.grid.2x2", title: L.t("Learn"),
                    subtitle: L.t("Rebuild the reading from tiles")) { LearnView(lesson: current) }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    /// A premium-gated mode row: navigates when unlocked, opens the paywall when not.
    /// `key` is the analytics name and the visit key; `title` is the on-screen one.
    @ViewBuilder
    private func way<D: View>(key: String, icon: String, title: String, subtitle: String,
                              @ViewBuilder destination: @escaping () -> D) -> some View {
        if locked {
            Button {
                paywallSource = "locked_mode"
                showPaywall = true
                Track.event("locked_mode", ["mode": key, "lesson": lesson.number])
            } label: {
                wayRow(key: key, icon: icon, title: title, subtitle: subtitle, gated: true)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink { Deferred(destination) } label: {
                wayRow(key: key, icon: icon, title: title, subtitle: subtitle, gated: false)
            }
            .buttonStyle(.plain)
        }
    }

    /// Icon, name, one-line description — and on the trailing edge, whether this lesson
    /// has tried the mode yet. Honest data only: "tried", not a made-up completion.
    private func wayRow(key: String, icon: String, title: String, subtitle: String,
                        gated: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 30)
                .foregroundStyle(gated ? Color.secondary : Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.title(.headline))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 10)
            if gated {
                Image(systemName: "lock.fill").font(.footnote).foregroundStyle(.secondary)
            } else if visits.contains(key) {
                Text(L.t("Tried"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
            } else {
                Text(L.t("Not tried yet"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .foregroundStyle(.primary)
    }

    // MARK: - The ladder

    private var earnedStars: Int { results.values.reduce(0) { $0 + $1.stars } }

    /// The first rung that is unlocked but not yet passed — the ladder's "next up".
    private var nextIndex: Int? {
        (1...challengeCount).first {
            ChallengeResult.isUnlocked(index: $0, results: results) && !(results[$0]?.isPassed ?? false)
        }
    }

    /// The passed rung most worth another run: fewest stars first, later rung on a tie —
    /// the freshest gap. Nil once everything passed is three-starred.
    static func retryTarget(results: [Int: ChallengeResult]) -> Int? {
        results.values
            .filter { $0.isPassed && $0.stars < 3 }
            .sorted { ($0.stars, -$0.index) < ($1.stars, -$1.index) }
            .first?.index
    }

    private var challengeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L.t("Challenge"))
                    .font(Theme.title(.footnote))
                    .foregroundStyle(.secondary)
                Spacer()
                // Numerals and a star — no localization to drift.
                Text("\(earnedStars) / \(challengeCount * 3) ★")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            rungStrip

            // The gate's one sentence, where the locked chips point at it. Numerals
            // interpolate, so 19 languages carry one string.
            if !locked, !previousCleared {
                Text(L.t("Clear every challenge in Lesson %@ first", "\(lesson.number - 1)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !locked, previousCleared, let next = nextIndex {
                nextCard(next)
            }
            if !locked, previousCleared, let retry = Self.retryTarget(results: results) {
                retryCard(retry)
            }

            earnHint
        }
    }

    /// Every rung as a chip: passed ones show their stars, the next one is the filled
    /// call to action, later ones wait behind a lock. Passed and next chips push the
    /// run directly — the strip is the ladder, not a diagram of it.
    private var rungStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(1...challengeCount, id: \.self) { i in rungChip(i) }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func rungChip(_ i: Int) -> some View {
        let result = results[i]
        let passed = result?.isPassed ?? false
        let isNext = nextIndex == i

        if locked {
            Button {
                paywallSource = "locked_challenge"
                showPaywall = true
                Track.event("locked_challenge", ["lesson": lesson.number, "index": i,
                                                 "reason": "paywall"])
            } label: {
                chipBody(i, star: nil, isNext: false, lockedIcon: true)
            }
            .buttonStyle(.plain)
        } else if !previousCleared {
            // Sequence-locked: the previous lesson's ladder isn't finished. Nothing to
            // open — the line under the strip says why — but the tap still logs:
            // without it the two newest gates were the only ones the dashboard
            // couldn't see anyone bounce off. Earned stars still show, so progress
            // made before the rule (or on another device) isn't drawn as if it never
            // happened.
            chipBody(i, star: result?.stars, isNext: false, lockedIcon: !passed)
                .opacity(0.55)
                .onTapGesture {
                    Track.event("locked_challenge", ["lesson": lesson.number, "index": i,
                                                     "reason": "previous_lesson"])
                }
        } else if passed || isNext {
            NavigationLink {
                Deferred { ChallengeView(lesson: current, index: i, total: challengeCount) }
            } label: {
                chipBody(i, star: result?.stars, isNext: isNext, lockedIcon: false)
            }
            .buttonStyle(.plain)
        } else {
            chipBody(i, star: nil, isNext: false, lockedIcon: true)
                .opacity(0.55)
                .onTapGesture {
                    Track.event("locked_challenge", ["lesson": lesson.number, "index": i,
                                                     "reason": "not_unlocked"])
                }
        }
    }

    private func chipBody(_ i: Int, star: Int?, isNext: Bool, lockedIcon: Bool) -> some View {
        VStack(spacing: 5) {
            Text("\(i)")
                .font(.headline.monospacedDigit())
            if isNext {
                Text(L.t("Next up"))
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            } else if let star {
                StarRow(stars: star, size: 8)
            } else if lockedIcon {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 56)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .foregroundStyle(isNext ? Color(.systemBackground) : Color.primary)
        .background(isNext ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(isNext ? Color.clear : Theme.line, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityLabel(L.t("Challenge %@", "\(i)"))
    }

    /// The forward step, as a card: which rung, and what it will ask.
    private func nextCard(_ i: Int) -> some View {
        let questions = min(Challenge.questionsPerChallenge,
                            Challenge.pool(current.entries, index: i).count)
        return NavigationLink {
            Deferred { ChallengeView(lesson: current, index: i, total: challengeCount) }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Theme.accent).frame(width: 32, height: 32)
                    Text("\(i)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(.systemBackground))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("Challenge %@", "\(i)")).font(Theme.title(.headline))
                    Text("\(L.t("Next up")) · \(L.t("%@ mixed questions", "\(questions)"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
            .padding(14)
            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.accent, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    /// The gap most worth closing: a passed rung still short of three stars.
    private func retryCard(_ i: Int) -> some View {
        let result = results[i]
        return NavigationLink {
            Deferred { ChallengeView(lesson: current, index: i, total: challengeCount) }
        } label: {
            HStack(spacing: 12) {
                StarRow(stars: result?.stars ?? 0, size: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.t("Retry Challenge %@", "\(i)")).font(Theme.title(.headline))
                    Text("\(L.t("Best %@%", "\(result?.bestScore ?? 0)")) · \(L.t("Earn %@ more ★", "\(3 - (result?.stars ?? 0))"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    /// The offer, stated where the work happens.
    ///
    /// Shown on the free lessons only, and only to non-premium users: on a locked lesson
    /// it would read as a taunt, and to a subscriber it describes something they already
    /// have. It disappears the moment it's won — an achieved goal left on screen stops
    /// being encouragement and starts being clutter.
    @ViewBuilder
    private var earnHint: some View {
        if !store.isPremium, !unlock.earnedFirstGroup, lesson.number <= Gating.freeLessonLimit,
           let band = Gating.earnableGroup, unlock.totalRungs > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(L.t("Three-star every challenge in lessons 1–%@ and all of %@ unlocks, free.",
                             "\(Gating.freeLessonLimit)", L.t(band.name)))
                } icon: {
                    Image(systemName: "lock.open").foregroundStyle(Color.streak)
                }
                // The number is the point: a bar with a count turns "some day" into
                // "four more", which is the difference between a nice idea and a plan.
                ProgressView(value: Double(unlock.swept), total: Double(unlock.totalRungs))
                    .tint(Color.streak)
                Text(L.t("%@ / %@ three-starred", "\(unlock.swept)", "\(unlock.totalRungs)"))
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
        }
    }

    /// Re-read on every appear so a challenge finished and popped back updates the strip.
    private func reloadResults() {
        results = ChallengeResult.byIndex(lesson: lesson.number, context: context)
        previousCleared = ChallengeResult.previousLessonCleared(lesson: lesson.number,
                                                                context: context)
        // A rung finished on the pushed screen may have completed the sweep, and this
        // view is what draws the locks — so the two have to be re-read together.
        unlock.refresh(context: context)
    }
}
