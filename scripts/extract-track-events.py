#!/usr/bin/env python3
"""Generate the iOS analytics catalog the Android `Track` is pinned to.

Reads every `Track.event("name"...)` and `Track.screen("name"...)` call in nihongo/*.swift, adds the
names the Swift source builds at run time (the order pickers, the kana flashcard deck, the two kana
quizzes, `audio_missing`), and writes android/app/src/test/resources/ios-track-catalog.txt:

    event <name>
    screen <name>

`TrackCatalogTest` fails when Android's `TrackEvents` and `TrackScreens` drift from this file.
Run it from anywhere after the Swift source changes; `--check` exits 1 when the file is stale.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "android/app/src/test/resources/ios-track-catalog.txt"

# Names the Swift source composes at run time, so no literal exists to grep. Each entry points at
# the construct that builds it; the script verifies the construct is still there.
DYNAMIC = {
    # Components.swift `OrderPicker(event:)`, passed by the two lesson decks.
    "learn_order_mode": 'event: "learn_order_mode"',
    "flashcard_order_mode": 'event: "flashcard_order_mode"',
    # Flashcards.swift logs "\(trackName)_reveal|_grade|_done|_restart"; only kana names itself.
    "kana_flashcard_reveal": 'trackName: "kana_flashcard"',
    "kana_flashcard_grade": 'trackName: "kana_flashcard"',
    "kana_flashcard_done": 'trackName: "kana_flashcard"',
    "kana_flashcard_restart": 'trackName: "kana_flashcard"',
    # KanaQuizView.swift: listening ? "kana_listening_answer" : "kana_classic_answer"
    "kana_listening_answer": '"kana_listening_answer"',
    "kana_classic_answer": '"kana_classic_answer"',
    # Track.audioMissing
    "audio_missing": 'event("audio_missing"',
}
# The one screen logged through a conditional: listening ? "kana_quiz_listening" : "kana_quiz_classic".
DYNAMIC_SCREENS = {
    "kana_quiz_listening": '"kana_quiz_listening"',
    "kana_quiz_classic": '"kana_quiz_classic"',
}


def build() -> str:
    sources = {p: p.read_text() for p in sorted((ROOT / "nihongo").rglob("*.swift"))}
    text = "\n".join(sources.values())
    events = set(re.findall(r'Track\.event\("([a-z0-9_]+)"', text))
    screens = set(re.findall(r'Track\.screen\("([a-z0-9_]+)"', text))
    for table, found in ((DYNAMIC, events), (DYNAMIC_SCREENS, screens)):
        for name, marker in table.items():
            if marker not in text:
                sys.exit(f"{name}: the Swift construct `{marker}` is gone; update DYNAMIC in this script")
            found.add(name)
    lines = [f"event {n}" for n in sorted(events)] + [f"screen {n}" for n in sorted(screens)]
    return "\n".join(lines) + "\n"


def main() -> None:
    content = build()
    if "--check" in sys.argv:
        if not OUT.is_file() or OUT.read_text() != content:
            sys.exit(f"{OUT.relative_to(ROOT)} is stale: run python3 scripts/extract-track-events.py")
        return
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(content)
    print(f"wrote {OUT.relative_to(ROOT)}: {content.count(chr(10))} lines")


if __name__ == "__main__":
    main()
