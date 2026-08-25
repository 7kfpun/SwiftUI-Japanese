# 04 — Lessons tab

The core study engine: 50 Minna no Nihongo lessons. Each lesson offers **five
untested practice modes** — Practice, Vocab List, Flashcards, Match, Learn — **plus the
scored Challenge ladder**, which is the only thing that records a result. The ladder has its
own doc (`02-challenge-ladder.md`); this one covers everything around it.

## Browser (`nihongo/Lessons/LessonListView.swift`)

- **No search text**: a segmented `Picker` over 4 fixed groups — Beginning 1
  (1–13), Beginning 2 (14–25), Advanced 1 (26–38), Advanced 2 (39–50) — above a
  `List` of lesson-number rows for the selected group.
- **With search text**: the group picker disappears and the list becomes a
  flat, lesson-tagged result list from `searchVocab(_:in:)` (simple
  case-insensitive `contains` across kanji/kana/romaji/translation — see
  `01-data-model.md`). Input is debounced 600ms before logging a
  `search_vocab` analytics event; the filtering itself is synchronous.
- **No "Free" badge on the lesson rows** — removed 2026-08 at kf's request. Lessons 1–5
  briefly wore one (framing the course as generous rather than fenced); the rows now
  carry no gating mark at all and the paywall speaks for itself at the point of entry.
  The rule that survives it: `CLAUDE.md` still forbids a free-lesson count in App Store
  or website copy.
- **Search that finds nothing says so in words**, naming the query and the four things
  the corpus matches on (kana, kanji, romaji, meaning). "0 results" alone leaves a
  learner unsure whether the word is absent or whether they typed the wrong script.
- **Each row carries a slim challenge progress bar**, not a ring: passed rungs over the
  lesson's rung count. It sits on the list you see most rather than one level in,
  because the bar is the reason to come back. Untouched lessons show **no bar at all** —
  an empty track on all 50 rows would read as "nothing works" rather than "nothing
  started" — and the bar has a fixed width so the bars line up down the list instead of
  jittering with each row's title length.
- The counts come from **one** `ChallengeResult` fetch per appear
  (`reloadProgress`), tallied per lesson, collapsing duplicate rows by rung first — a
  CloudKit merge can leave two rows for one rung and counting both would overfill the
  bar. Refreshing on appear is what makes the bar update behind you when you finish a
  rung and navigate back.
- **The navigation stack lives on `Router`**, not in the view, so the widget's
  "Ready for Challenge N?" link can push a lesson into a tab the user isn't on. Row taps
  append to the same path, so a deep link and a tap leave the user in the same place with
  a working back button either way.
- `VocabRow` (also reused by search results, `VocabListView` and `BookmarksView`) is
  **one left-aligned stack** — kana, kanji, then the meaning under the word it belongs
  to (design 3a; the old layout pushed the meaning to the row's far edge, splitting each
  entry into two ends of a rubber band) — plus a fixed 40pt trailing column holding the
  speaker over the bookmark star. The speaker is body-sized in a real 36×30 frame; it
  was a caption-sized ~20pt target, the row's most-used control at its smallest.
  Tapping the row or the speaker speaks the word and logs `play_vocab`. With
  `Pref.examplesShown` on, the example sentence unfolds under the row as a
  `Theme.canvas` inset pane; tapping it speaks the *sentence*.
- **The star is a sibling in that column, never an overlay.** It was
  `.overlay(alignment: .topTrailing)`, which takes no layout space, so its position
  followed the row's height: a two-line row (kanji shown) left it hovering above the
  speaker and a one-line row put it straight on top. It is also **one glyph plus a
  numeral** (`★2`), not one glyph per tier — three repeated stars is a variable-width
  control, and in a list that means nothing lines up. Both are separate buttons: tapping
  a star must never also play audio. It uses `.buttonStyle(.plain)` deliberately: the
  default style tints the whole label with the accent colour and beats a
  `.foregroundStyle(.primary)` applied inside, so only the style change keeps the
  vocabulary reading as text rather than as a link.

## Select-mode (`SelectModeView`)

A `ScrollView`, **not a `List`** (design 2a): the hero is a dark card, the ladder runs
horizontally and the mode rows carry trailing status — three things a `List` fights.
Four blocks, top to bottom:

1. **The standing bar** — one proportional bar over the lesson's words: memorized on
   the accent, recognized on a faded accent, unseen on `Theme.line`, with the three
   counts spelled out under it (`PracticeProgress.counts`; `seen` folds into unseen, so
   it understates rather than overstates). Proportional, not one pip per word: JLPT
   lessons run to dozens of words and forty hairlines read as texture, not progress.
2. **The Practice hero** — the page's one heavy card (`Color.primary` on the canvas, so
   it inverts cleanly in dark mode; everything on it takes `systemBackground`). Carries
   "Up next", a rough time-and-card estimate for the session Practice would deal right
   now (~20s per card), the mode name and subtitle, a **Start** capsule, and a thin bar
   showing how much of the lesson is memorized.
3. **Other ways to practice** — Vocab List, Match, Learn as rows in one `Theme.surface`
   group, each with a trailing **Tried / Not tried yet** label from `ModeVisits`
   (`Prefs.swift`): a UserDefaults set of `"lesson/mode"` strings, marked on each mode's
   `onAppear`. It records *opened*, nothing more — inventing a completion state for
   modes that are deliberately endless would be a lie with a progress bar.
4. **The Challenge ladder** — a horizontal **chip strip** (`n / m ★` in the header):
   passed rungs show their `StarRow`, the next one is the filled accent chip labelled
   "Next up", later ones sit behind a lock at reduced opacity. Under it, up to two
   cards: **next up** (which rung, how many mixed questions) and **retry** — the passed
   rung most worth another run, chosen by `SelectModeView.retryTarget` (fewest stars
   first, later rung on a tie; nil once every passed rung is three-starred).

Re-resolves the lesson from the current `Pref.translationLanguage` on push, so
switching the Meanings language mid-session and re-entering a lesson shows the new
language immediately.

**This is the one place lesson gating is enforced for the practice modes and the
ladder** — a locked row (the hero and every rung chip included) opens the paywall
instead of navigating, so no practice screen has to police access itself. The hero logs
the same `locked_mode` event with `mode: "practice"`; chips log `locked_challenge`.
(`VocabListView` is the only other enforcement point, and only for reading meanings
aloud — see `06-monetization.md`.)

On a **free** lesson the Challenge section's footer also carries the earned unlock: the
offer, a progress bar and an `n / m three-starred` count. It is hidden once won, for
subscribers, and on locked lessons — where it would read as a taunt rather than an
offer.

## §1 Practice — cards then quizzes (`Lessons/PracticeView.swift`)

**The merge of the old Flashcards and Train** (design 2b/2c): they were one gesture
with two scorers — the learner (flashcards) or the app (train) — and beginners couldn't
tell which to tap. One queue now deals both *faces*:

- **Which face a word gets on entry**: never met (`.unseen`) → card; **met before →
  straight to the quiz**. That is the merge's rule — "沒見過的字給卡片正面＋自評，見過的
  字直接變成二選一" — and the threshold was briefly `.recognized`, which made a word you
  had merely met keep showing its flashcard until you explicitly said "Got it". The
  escape hatches override it *inside* a session: Again, "Not sure" and a wrong answer all
  re-queue a card whatever the stage says. Stage decides where a word enters; what the
  learner does decides the rest (`PracticeTests.seenWordsEnterAsQuizzesAndOnlyNewOnesAsCards`).
- **Only the app scores. There is no "I know it" / "I don't".** A left/right swipe
  always means *this answer*. Self-assessment was the one difference between the two
  modes this replaced — and the thing beginners could not choose between — and it
  measures confidence rather than recall, so every rung is earned by answering.
- **Card face** for words not yet met: it *teaches*, showing kana(+kanji), meaning,
  romaji and the example all at once (no "Show meaning" gate — that button existed to let
  you try recall before grading yourself, and with the grading gone it only stands
  between the learner and what they came to read). One button, **Quiz me on this**, or a
  swipe either way — both mean the same thing, since neither direction carries a verdict.
  It marks the word `.seen` and re-queues it **as a quiz** a few cards later
  (`requeueWindow`, drawn per word from 3…8).

  **The distance is drawn, not fixed**: a fixed offset preserves order, so every quiz
  landed in the same order its card did and a fresh lesson played as a block of ten cards
  then a block of ten quizzes — Flashcards for a stretch, then Train for a stretch, the
  exact split the merge exists to remove. Pinned by
  `PracticeTests.facesInterleaveRatherThanBlock`.
- **Quiz face** for every word already met: the old Train — two options drawn at
  random from the lesson (`optionCount`), one swipe. **Two correct answers, not one**:
  with two options a coin flip is right half the time, so the first correct answer
  promotes one rung (`.seen` → `.recognized`) and only the second reaches `.memorized`
  and retires the word for the session. A wrong answer drops it to `.seen` and the
  teaching card returns.
  **"Not sure — show the card"** under the chips is a free look: no stage change, no
  verdict, card comes back (`practice_not_sure`). The card states the question in words
  ("What does this word mean?"), carries a speaker button, and on a **kanji prompt**
  offers **Show kana** — a kanji you cannot yet read makes the question unanswerable,
  and since nothing here is scored a hint beats a wrong answer. Options carry the
  gesture in words ("Swipe left" / "Swipe right", `SwipeOptionChip.hint`), hidden once
  answered. **The quiz face is a question, not a deck** (design 2b): a compact card sized
  to its content with no peek layers and no swipe hint, the two answers directly beneath
  it, and the escape hatch at the bottom edge. It used to be a full-height card, which
  marooned the word in white space and put the answers a screen away from the question.
  The card face keeps the deck — peek behind, hint on it — because self-assessing really
  is dealing through a stack.
- **The stage readout** (`StageLadder`) sits above every card: three dots filled to the
  word's rung, and the name of that rung. It began as three labelled pills with
  connectors — ~250pt of furniture for one fact, which pushed the pair control onto a
  second line in most languages and read as a control the learner was meant to operate.
  It is a *status*: the dots carry the progression (the same fill language `StageDot`
  uses in the vocab list) and only the current rung is named. A thin **session bar**
  above it tracks `fractionDone` — answer-weighted workload (a word owes two correct
  answers below `.recognized`, one above), because a bar drawn from `retired` sat at
  zero through the whole first pass and read as broken. The printed count stays
  `retired / sessionTotal`: the number that only moves when a word is truly done.
- **Hold the card to turn it over, release to turn it back.** The back carries the
  meaning, reading and example. Press-and-hold rather than a toggle: a peek should cost
  something to keep, and a flipped card would just sit there answered. The tap stays
  free to speak the word. Peeking is deliberately *visible and costly*: the back
  says "this one comes back", and a right answer given afterwards moves nothing up the
  ladder (`PracticeModel.resolve(credited:)`) — reading the answer is not evidence of
  knowing the word. A wrong answer still demotes, peeked or not: missing it with the
  meaning in front of you is if anything the clearer signal. Pinned by
  `PracticeTests.peekingCostsTheRoundButNotThePunishment`.
- **`PracticeProgress`** (`nihongo/PracticeProgress.swift`): per-word stages keyed by
  `Vocab.id` — unseen 0 → seen 1 → recognized 2 → memorized 3, raw values append-only.
  **Local-only by decision**, a JSON file in Application Support (not a CloudKit
  `@Model`, avoiding the StudyDay production-schema trap; not `UserDefaults`, because
  JLPT's 8k-word map would rewrite the whole plist per swipe). Debounced 1s atomic
  saves; `PracticeView.onDisappear` calls `saveNow()`. Injected via `.environment`
  from both app files.
- **The quiz pair sheet** (design 4a/5a, `PracticePairSheet`): a capsule above the card
  names what the quizzes ask (kana → meaning by default) and opens a sheet — two rows
  of face chips ("You see" / "You answer", the opposite row's face greyed), a **Mixed**
  option, and a live preview built from a real word and a real distractor. Faces are
  `PracticeModel.quizFaces` = kana/kanji/meaning — deliberately no romaji (a crutch) and
  no audio (the ladder's listening rungs). Persisted as `VForm.label` strings under
  `Pref.practiceFrom`/`To`/`practiceMixed`; committed via `setPair`, logged as
  `practice_pair`.

  **Every tap commits — there is no confirm button.** Three switches, not a form: each
  is instantly reversible by tapping another chip, and the whole result is already on
  screen in the preview below, so a confirm step would only ask the learner to approve
  something they can see.

  **Mixed draws from what each word supports, and this is the part that was wrong once.**
  `PracticeModel.faces(for:)` returns kana/meaning for a word with no kanji of its own
  and all three otherwise; `pair(for:)` enumerates the ordered pairs of *those* and draws
  uniformly. The first version drew one of the six combinations and then rewrote an
  impossible kanji slot into kana — which lands four of the six on kana→meaning, so on a
  katakana-heavy lesson Mixed asked the easiest direction about two-thirds of the time.
  Pinned by `PracticeTests.mixedDrawsEvenlyFromWhatEachWordSupports`. When a *fixed* pair
  hits the same wall, the degraded side moves and the side the learner explicitly chose
  survives (choosing to answer in kana keeps kana answers; the prompt becomes meaning).
- **Distractor rule** (from `TrainModel`): a candidate must differ from the answer on
  *both* faces. Matching the answer side makes a second right answer that would be
  marked wrong (shared glosses like なん/なに); matching the prompt side (homophones)
  makes the question unanswerable.
- **Audio-safety rule** (`VForm.promptAudioSafe`, in `Lessons/VForm.swift` — moved out
  of the deleted TrainView.swift because the Challenge ladder shares it): a card face
  always speaks; a quiz face auto-plays only when the prompt is the word itself, never
  when it's the meaning.
- A fully-memorized lesson re-enters whole as quiz review — wrong answers still
  demote, which is what gives the mode a reason to reopen. Restart rebuilds from
  current stages, so the queue shrinks as the lesson is learned.
- Ordered/random and form-cycling from Train are **gone**: the scheduler owns the
  order, the sheet owns the pair. `Pref.trainOrdered` is retired, key reserved.
- **Untested and unscored** beyond the session counter (retired / remaining / total,
  the flashcards' queue semantics — half the grades are the learner's own word).
  Results count only in the Challenge ladder; Practice does **not** write `StudyDay`.
- An interstitial ad is preloaded on entry and shown on the way out (throttled,
  non-premium only) if anything was graded — `PracticeModel.answered > 0`, the same
  shape as Match's `attempts > 0`. It was briefly queue arithmetic that collapsed to
  "memorized at least one word", which throttled on the wrong axis.

The Kana tab's flashcards are untouched: `FlashcardScreen`/`FlashDeck`
(`nihongo/Flashcards.swift`) live on as shared chrome, and Kana keeps the
"Flashcards" / "Swipe right if you know it" strings.

## §2 Vocab List (`Lessons/VocabListView.swift`)

A scannable list of every entry, with three **cut chips** pinned above it:
**All / Not memorized / Bookmarked** (that one starred), each with a live count. The
selected chip takes a **solid `Color.primary` fill** rather than the house's accent
border: the border rule exists to keep accent fills from competing with answer feedback,
and a row of four capsules separated only by border weight is hard to read at a glance —
this fill carries no verdict. "Not memorized" reads the
same `PracticeProgress` stages Practice writes; "Bookmarked" is the user's own shelf
(`Bookmark.all`, re-read on appear). The cut also decides **what Read along reads** —
playing the words you filtered to (your bookmarks, your gaps) is the point of
filtering. Cut changes log `vocab_cut`.

**Examples rides in the same row**, after a divider, as a label and a real `Toggle` —
not another chip. The chips answer "which words"; this answers "how much of each word",
and the switch is what says they are different questions. It belongs beside them rather
than behind a toolbar glyph (`Pref.examplesShown`, logs `examples_shown`; off by
default, since every sentence expanded left four words per screen). Under the row, one
quiet line teaches the swipe. Row taps stay what they always were: speak the word.

**Both the switch and the "+ Example" rung are hidden where the dataset has no
sentences.** `VocabStore.hasExamples` reads that off the decoded file rather than off
`Course.current`, because it is a property of the data: Minna carries a sentence for all
2,100 entries, **JLPT carries none for any of its 7,972** — so in Bonsai JLPT both
controls were buttons that revealed nothing, and the read-along one was the *paid* rung.
Deriving it from the file means the day `build-jlpt-data.py` starts emitting sentences
the features appear on their own, with no second place to remember. Per-*word* absence
was already handled everywhere by an `if let vocab.example`; this covers the *controls*,
which had nothing to nil-check. The example **translations** are a separate axis: only
`en`/`zh`/`zh-Hant` are written so far, and — unlike word meanings — they deliberately do
**not** fall back to English. A word with no meaning is a useless row; a sentence with no
translated line is still a sentence (kanji, furigana, romaji all shown), and English
under it for a Thai learner read as wrong-language data, not as a fallback. Every reader
nil-guards and the read-along's fourth leg skips itself (`VocabStore.build`).

**Each row carries its Practice stage as a dot** (`StageDot`): filled for memorized,
faded for met, hollow outline for unseen. Fill rather than three glyphs — down
forty-six rows the eye scans for pattern, and solid/faded/hollow reads at a glance where
three icons each have to be identified. It is the same `PracticeProgress` stage the
lesson screen counts and Practice's ladder shows: one fact, three surfaces. The dot is
opt-in on `VocabRow` (`stage:`), so search results and the bookmarks shelf — which span
lessons, or are about the user's own filing — don't carry it.

**The star saves; the swipe reports.** `BookmarkStars` sits under the speaker, always
present, one tap cycling ★1 → ★2 → ★3 → none (`BookmarksView` groups by those tiers).
A trailing `swipeAction` opens the **feedback sheet** for that entry instead.

Both halves were tried the other way round first, and each failed for a reason worth
keeping: a swipe *cannot* carry a cycle, because the drawer closes the moment its button
is tapped — reaching ★3 took three separate swipes. And hiding the star until a word was
saved kept unsaved rows clean but made tiers undiscoverable. So the tap control owns the
cycle, and the swipe took the job this screen had no room for: the vocab list is where a
learner reads the data closely enough to notice a wrong reading, and the flag previously
lived only on quiz screens.

`BookmarkStars` takes its tier **from the list** (`VocabRow.savedTier` / `onTierChange`)
rather than fetching its own. It loaded once into `@State`, which drifted from the tier
map the cut chips count — so the "Bookmarked" count went stale the moment a row changed.

**An empty cut says why**, and the three reasons differ: nothing starred yet, every word
memorized, or genuinely no words. An empty list under
a chip reading "Bookmarked 0" otherwise looks like a screen that failed to load.

The title is the screen's own name with the lesson and word count beneath it — it used
to *be* the lesson number, which said nothing about what the screen was. **Read along**
is a plain accent-tinted glyph beside it: iOS 26 wraps every toolbar item in its own
circular chrome, so a control that fills its own circle renders as a disc inside a disc
(see `07-ux-ui.md`). The tint is what marks it as the screen's action.

The list is **always free**, even on locked lessons — the one mode exempt from gating,
so browsing and search never lock. Its toolbar carries the examples toggle and one
control into **Read along**, which takes the current cut with it.

## §2b Read along (`Lessons/ReadAlongView.swift`)

The whole lesson read out, as a *player* rather than a list that happens to be talking
(design 3b). The earlier shape — a toolbar menu that started audio behind the list with
a bar pinned to the bottom — read as a background process: what was playing, how far in
it was and what came next were all inferred from one highlighted row.

- **The player card**: the current word large, "Word n of m", a **speed pill**
  (0.8× / 1× / 1.2× / 1.5×, **premium** — see `06-monetization.md`; persisted in
  `Pref.playbackRate`, applied live to clips via `enableRate` and to the TTS fallback by
  scaling utterance rate; logs `read_all_speed`, or `locked_speed` when tapped without it)
  and animated `PlayingBars`. **No clock** — it read as precision the screen had no use
  for, and the machinery behind it (a detached pass measuring every clip's real duration)
  went with it rather than being left orphaned.
- **The mode is on the surface**, as a *cumulative* segmented track: **Word /
  + Meaning / + Example**, switchable mid-run, with a lock glyph naming the gate before
  the tap (every non-subscriber, not only locked lessons — `Gating.wordsToRead` /
  `loopsForever`, preview then paywall, see `06-monetization.md`). The labels are short
  and additive because the modes *are*: each adds a leg to the one before. Spelling them
  out in full ("Japanese + meaning + example") put three long labels in a ~110pt row,
  where they shrank and then wrapped — and hid the ladder behind repetition. The caption
  under the card carries the full sentence once.
- **`withExample` reads four legs**: the word, its meaning, the **recorded** sentence
  (`VocabStore.exampleAudioURL`, synthesiser fallback), then the sentence's own
  translation. That last leg was missing at first, which left the one part of the
  sequence a learner could not work out for themselves as the only silent one.
- **The playlist**: numbered rows with kana, meaning and the bookmark star; the playing
  row expands to add romaji and auto-scrolls into view; tapping any row **jumps** to it
  (`LessonPlayer.play(word:)`). In the `withExample` mode every row also carries its
  sentence — on the playing row alone would defeat the point, since following a spoken
  sentence means having it in front of you *before* it is read.
- **Pause, not mute.** The toolbar's trailing control is pause/resume; the sound toggle
  that used to sit there left a player running silently, and this screen had no way to
  stop without leaving it. `resume()` restarts the current word rather than resuming
  mid-syllable — the synthesiser's pause lands wherever it lands, and half a word is
  worse than the word again.
- `LessonPlayer` itself is unchanged in kind: an
  `AVAudioPlayerDelegate`/`AVSpeechSynthesizerDelegate` that plays each word's clip in
  sequence and falls back to live TTS. It loops **only for subscribers**
  (`06-monetization.md`); a free listener hears the lesson through once.

## §2c Flashcards — a deck to page through (`Lessons/FlashcardView.swift`)

Back after the merge, and **browse-only**. Swipe to turn (`CardPager`, the same modifier
Learn pages with), ordered or random via a picker (`Pref.flashcardsOrdered` — its own key,
not Learn's, because the two are different sittings), **hold to flip** for the meaning,
romaji and example, release to turn back.

Two corrections worth keeping: the pager sat on the enclosing `ZStack`, so the peek
layers flung along with the front card and the deck left as one slab — it belongs on the
card, the trap `05` and `IntroView` both warn about. And Random used to get a full-width
**"Random" button** under the deck; it did what a swipe already does in that mode while
wearing the same word as the already-selected picker segment, so it read as a mode switch
that was already switched. Gone, and the long-press hint now shows in both modes. (Learn's
shuffle button is a different thing and stays — see §5.) Audio toggle and report flag in the toolbar; the
counter is `n / total` in the shared `ToolbarStatus`.

**It writes nothing.** No `PracticeProgress` stage, no `ChallengeResult`, no `StudyDay`.
Browsing is not evidence of knowing, and a screen that quietly promoted a word for being
looked at would make the ladder mean less.

**The grading is gone on purpose.** This mode used to ask "did you know it?" on every
card, and that self-assessment is exactly what Practice was built to remove — it measures
confidence, not recall. What survived is the part that never needed a verdict: meeting the
words one at a time, at your own pace. Ordered is the default here (Practice's queue
shuffles) because a first walk through a lesson wants the order the course teaches in.

`VocabFace` — the card back — is shared with Practice's reveal (`Components.swift`), so a
word looks the same wherever it is turned over.

## §3 Match — pair the columns (`Lessons/MatchView.swift`)

The header is the shared one: `ScoreBadge` in `ToolbarStatus`, captioned "Round 2 · 5
pairs" — the caption slot exists for exactly this, a run with a shape worth naming. The
board is a **`Grid`**, not two columns: each column used to distribute its own height, so
a long gloss on the right made that side's rows taller and the two lists drifted out of
step, leaving tiles opposite nothing on a screen whose whole job is pairing. A miss
shakes its tile (`ShakeEffect`, 0.22s — over before it can feel like a telling-off), a
new round deals in rather than appearing, and cleared tiles empty out while keeping their
footprint so nothing reflows under a thumb. The footer names the drag and the tap
fallback underneath it.


Endless pair-matching: `MatchModel.pairsPerRound` (5) words down the left, their
meanings shuffled down the right, dealt from the same no-repeat bag Train used. Tap one
from each side **or drag a line between them** (design 3d): tiles report their frames
through a `PreferenceKey` in the board's coordinate space, a `Canvas` overlay draws the
finger's live line plus one line per cleared pair — the round's record, kept on the
board. Cleared lines take the accent (the green flash is the feedback; a lingering
line is furniture), the just-matched line flashes `Theme.correct`, and a wrong or
dropped line just snaps back. Either side can start a drag or a tap — meanings-first is
recall, the more valuable direction. Matching compares vocab **ids**, never displayed
text, so two look-alike glosses can't false-match. Tap order is free; only the Japanese
side speaks. Logs `match_answer` per attempt; interstitial on the way out like
Practice.

## §4 Learn — tile reconstruction (`Lessons/LearnView.swift`) — signature mode

The learner rebuilds a word's kana reading by tapping shuffled character
tiles in order. It's last in the section because it's the deepest ask short of the
ladder: producing a reading from nothing rather than choosing between options.

- **Tile generation** (`LearnModel.loadTiles`): clean the target kana with
  `cleanWord`, then distractor count = `10 - cleanLength` (or `15 -
  cleanLength` if that's negative); if *still* negative the entry is
  sentence-length and gets **no tile game** (`isPlayable == false`) — the app
  shows the card with a "This entry is a full sentence — no tile game."
  message instead of crashing. Exactly one entry in the whole dataset hits
  this (lesson 14, a full sentence, clean length 16 > 15) — pinned by
  `LearnTests.sentenceLengthEntryBails`.
- Distractors are drawn from `KanaData.hiraganaPool`/`.katakanaPool` (whichever
  script the target's first character belongs to), shuffled together with the
  target's own characters so the correct answer is always buildable
  (`LearnTests.tileGenerationNeverCrashesAndKeepsAnswerBuildable` checks that on every
  entry of all 50 lessons).
- **Answer checking** (`LearnModel.tap`): append the tapped character; correct
  the instant the built string equals the target, **wrong the instant it's no
  longer a prefix of the target** — an out-of-order tap fails immediately
  rather than waiting for the full length. A wrong state disables the grid and
  surfaces a Clear button.
- **Card display**: `CardOptionsBar` toggles (kanji/kana/romaji/translation/
  sound, `@AppStorage`-backed) control what's shown around the assembled
  answer; a correct/wrong icon overlays once the state resolves. The assembled
  reading shrinks rather than wrapping (`Theme.jp(52)`, floor 0.35), because entries run
  to 15 characters and a fixed size that fits those would be tiny for the common short
  ones.
- **Navigation**: an Ordered/Random segmented control, persisted in `Pref.ordered` and
  defaulting to **ordered**. (Train's separate `Pref.trainOrdered` is retired with
  Train; Learn's key was always its own.) Ordered pages sequentially with
  swipe-to-turn (`CardPager` — see `05`); Random has a single shuffle button that
  drives the *same* animation through `CardPager`'s `fling` binding. Either way, paging
  speaks the new word explicitly in the page-turn handler (not via
  `.onChange(of: index)`, since a random jump can land on the same index and would
  silently skip the announcement).
- The tile grid computes an explicit square size from its measured width, the same
  measure-then-divide pattern as the Kana browser tiles (`07-ux-ui.md`).

## §5 The Challenge ladder

The scored half of a lesson, and the app's core loop — **fully documented in
`02-challenge-ladder.md`**. The short version: rungs of `questionsPerChallenge` (10)
questions, `passScore` (80%) to pass, 1–3 stars by score, and rung *N* unlocks only once
*N−1* is passed (`ChallengeResult.isUnlocked`). Prompt/answer pairs harden by rung —
recognition at 1, recall from 2, audio-with-no-visual-cue from 3 (`Challenge.forms`).
Only *best* results are kept, so a retry can raise a score but never lower it.

`SelectModeView`'s chip strip distinguishes **two kinds of lock**, on purpose, because
only one is something the user can fix by paying: a premium lock opens the paywall and
logs `locked_challenge`, while a rung locked by *progress* is simply dimmed behind a
padlock and isn't tappable. The next playable rung is the strip's one filled chip, so
"where am I" needs no reading.

**The run itself is three screens** (`ChallengeView`, design `Lesson - Challenge`):

- **Briefing** — the rung's number out of the lesson's total, what it will ask, the
  **pool laid out as the words themselves** (a `FlowLayout` of the same set Today deals
  as warm-up), the **star bands phrased in misses** — computed by
  `ChallengeView.allowedWrong` from the run's real question count, never hardcoded to
  ten — and, on a return visit, a "last time n% — k ★" banner. One black Start button,
  which is where `challenge_start` fires: a run begins when the learner says so.
- **Play** — a clock (`TimelineView`, ticking from the run's start), a `StarRow` of the
  stars *still reachable* under a **"Still winnable"** label (unlabelled, three greyed
  stars read as a result already earned rather than a stake), one thin pip per question,
  a spelled-out prompt label ("What does this word mean?"), the prompt card with a **"Tap
  to hear it"** hint (on a listening rung the tap is the only way to replay the question,
  so an invisible affordance is a real problem), options as full-width rows, and a **risk
  line** between options and the next button ("2 wrong — finish clean to keep 1 ★"; after
  answering, the verdict, in `Theme.wrong` only when correcting a miss). The Next button
  *appears* on answering rather than sitting there disabled.
- **Result** — `model.isDone`, not a phase, so no state bug can reach a score screen
  without the questions. Stars (celebrating), a stars-derived title, a **tappable cheer**
  (says the same phrase again — the tap people make is "once more so I can catch it",
  and the re-roll-on-tap swapped the words mid-listen, so it went 2026-08-26; variety
  comes from the fresh draw each result screen makes), three stat cards (this run / best / lesson stars, the last accented
  because it describes the lesson rather than the run), the missed words, a **what's-left
  banner** sized to the outcome (clean sweep → what remains in the lesson; pass → the
  third star is still there; miss → how many points short), then the forward step with
  Retry and Done side by side beneath it.

  **`Cheer.perfect` holds はなまる and かんぺき for three stars.** Both name full marks, so
  hearing one after two right out of three reads as the app not watching — praise that
  outranks the result is worth less than none
  (`ChallengeTests.fullMarksPhrasesAreHeldForACleanSweep`).

**A ladder miss demotes the word's Practice stage** to `.seen` when it was
`.recognized` or better, so the result screen's "missed words come back in Practice" is
literally true — the next Practice session re-deals them as cards.

## Mode-by-mode gating summary

| Mode | On a locked lesson |
|---|---|
| Vocab List | ✅ free on every lesson |
| Practice | locked |
| Flashcards | locked |
| Match | locked |
| Learn | locked |
| Challenge (every rung) | locked |

**One whole-lesson rule.** Lessons 1–`Gating.freeLessonLimit` (5) are free in full —
every mode, every rung — and the rest are locked outright. The earlier per-mode
card/page/question quotas are gone: a free user can *finish* the early lessons, fill the
progress bar and earn the stars, then meet the paywall carrying that momentum instead of
being cut off mid-practice.

The **one** exception is Read along's "Japanese + meaning", which is premium on *every*
lesson: without a subscription it reads `Gating.freeMeaningPreview` (7) words and then
shows the paywall. "Japanese only" is free everywhere; the speed dial is premium too. See `06-monetization.md` for `Gating`, the
products, the paywall and why that exception is the only one.

## What's *not* in this app

No `Lessons/QuizView.swift` or `TrainView.swift` — four-option multiple choice belongs
to the Challenge ladder, Listening became `VForm.audio` (a prompt form inside
`Challenge.forms`), and the *graded* halves of Flashcards and Train merged into
Practice. `Lessons/FlashcardView.swift` **does** exist again (§2c) — but as the
browse-only deck, not the graded one this paragraph used to deny.
Per-word progress on the Lessons side is `PracticeProgress` only — unscored study
stages, local-only, deliberately **not** a `KanaResult`-style CloudKit model
(`01-data-model.md`). No study reminders beyond the streak notification
(`05-shared-and-audio.md`). The old "Read All" mode is now Read along, reached from the
Vocab List rather than sitting beside it in the mode list — it reads a lesson, it
doesn't test it, so it is a surface of the list rather than a fifth way through.
