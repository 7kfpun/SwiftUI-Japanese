#!/usr/bin/env python3
"""Dump the iOS Challenge ladder maths (nihongo/Lessons/Challenge.swift) as shared JSON fixtures.

The Android port (android/.../ladder/Challenge.kt) is asserted against the file this writes,
android/app/src/test/resources/challenge/ladder-fixtures.json, so both platforms cut, window, tier and
star a lesson identically.

How it runs the *real* Swift: it copies Challenge.swift to a temp dir, drops the `@Observable` macro
and widens `private static` to `static`, extracts `ChallengeView.allowedWrong` verbatim from
ChallengeView.swift, and compiles them with `swiftc` next to a small driver that stubs the four types
Challenge.swift leans on (`Vocab`, `VForm`, `Speech.Voice`, `cleanWord`). Inputs are the real 50
lessons of nihongo/Resources/MinnaData.json. No Xcode project, no simulator, no app build is involved.

Only the deterministic functions are fixtures. Question *selection* is random (shuffles, voices), so
the Android tests assert the same invariants the iOS tests do (ChallengeTests) over every rung instead.

Usage (macOS, Xcode command line tools):  python3 scripts/dump-challenge-fixtures.py
"""

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHALLENGE = ROOT / "nihongo" / "Lessons" / "Challenge.swift"
CHALLENGE_VIEW = ROOT / "nihongo" / "Lessons" / "ChallengeView.swift"
PRONOUNCER = ROOT / "nihongo" / "Pronouncer.swift"
VOCAB_STORE = ROOT / "nihongo" / "VocabStore.swift"
DATA = ROOT / "nihongo" / "Resources" / "MinnaData.json"
OUT = ROOT / "android" / "app" / "src" / "test" / "resources" / "challenge" / "ladder-fixtures.json"

STUBS = """
import Foundation

struct Vocab {
    let id: String
    let kana: String
    let kanji: String
    let romaji: String
    let translation: String
    let audio: String?
    let displaysKanji: Bool
}

enum VForm: Int, CaseIterable {
    case kana, kanji, romaji, translation, audio
    var label: String {
        switch self {
        case .kana: return "kana"; case .kanji: return "kanji"
        case .romaji: return "romaji"; case .translation: return "meaning"
        case .audio: return "audio"
        }
    }
    func value(_ v: Vocab) -> String {
        switch self {
        case .kana: return v.kana; case .kanji: return v.kanji
        case .romaji: return v.romaji; case .translation: return v.translation
        case .audio: return v.kana
        }
    }
}

enum Speech {
    enum Voice { case `default`, alternate
        static func random() -> Voice { Bool.random() ? .default : .alternate } }
}

"""

DRIVER = """
import Foundation

func labels(_ pairs: [(from: VForm, to: VForm)]) -> [String] {
    pairs.map { "\\($0.from.label)>\\($0.to.label)" }
}

let input = try! JSONSerialization.jsonObject(
    with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String: Any]]

var lessons: [[String: Any]] = []
for l in input {
    let number = l["number"] as! Int
    let words: [Vocab] = (l["words"] as! [[String: Any]]).map {
        Vocab(id: $0["id"] as! String, kana: $0["kana"] as! String, kanji: $0["kanji"] as! String,
              romaji: "", translation: "", audio: ($0["hasAudio"] as! Bool) ? "x" : nil,
              displaysKanji: $0["displaysKanji"] as! Bool)
    }
    let steps = Challenge.steps(wordCount: words.count)
    var rungs: [[String: Any]] = []
    for i in 1...steps.count {
        let r = Challenge.poolRange(wordCount: words.count, index: i)
        rungs.append([
            "index": i,
            "poolStart": r.lowerBound, "poolEnd": r.upperBound,
            "poolSize": Challenge.poolSize(wordCount: words.count, index: i),
            "new": Challenge.newWords(words, index: i).map(\\.id),
            "pool": Challenge.pool(words, index: i).map(\\.id),
            "forms": labels(Challenge.forms(index: i, of: steps.count)),
        ])
    }
    // supports(word, pair) for every word and every pair rung 3 can ask, as a bit string.
    let pairs = Challenge.forms(index: 3, of: steps.count)
    let supports = words.map { w in
        pairs.map { Challenge.supports(w, from: $0.from, to: $0.to) ? "1" : "0" }.joined()
    }
    lessons.append(["number": number, "wordCount": words.count, "steps": steps,
                    "count": Challenge.count(wordCount: words.count), "rungs": rungs,
                    "supportPairs": labels(pairs), "supports": supports])
}

// Lookalike scores over the first 14 words of lesson 1 (every ordered pair).
let first = (input[0]["words"] as! [[String: Any]]).prefix(14).map {
    Vocab(id: $0["id"] as! String, kana: $0["kana"] as! String, kanji: "", romaji: "",
          translation: "", audio: nil, displaysKanji: false)
}
var lookalikes: [[String: Any]] = []
for c in first { for a in first {
    lookalikes.append(["candidate": c.id, "answer": a.id, "score": ChallengeModel.lookalike(c, a)])
} }

let stars = (0...100).map { Challenge.stars(score: $0) }
var allowed: [[String: Any]] = []
for q in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20] { for m in [90, 80, 70] {
    allowed.append(["questions": q, "minScore": m, "allowed": ChallengeViewFx.allowedWrong(questions: q, minScore: m)])
} }

let out: [String: Any] = [
    "constants": ["questionsPerChallenge": Challenge.questionsPerChallenge, "passScore": Challenge.passScore,
                  "wordsPerStep": Challenge.wordsPerStep, "reviewWindow": Challenge.reviewWindow,
                  "minReviewSlots": Challenge.minReviewSlots],
    "stars": stars, "allowedWrong": allowed, "lessons": lessons, "lookalikes": lookalikes,
]
let data = try! JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
"""


def lessons_from_data():
    data = json.loads(DATA.read_text())
    out = []
    for lesson in data["lessons"]:
        words = []
        for e in lesson["entries"]:
            use_kana = bool(e.get("useKana", False))
            words.append({
                "id": f"{lesson['number']}/{e.get('key') or e['romaji']}",
                "kana": e["kana"],
                "kanji": e["kanji"],
                "displaysKanji": (not use_kana) and e["kanji"] != e["kana"],
                "hasAudio": e.get("audio") is not None,
            })
        out.append({"number": lesson["number"], "words": words})
    return out


def extract_allowed_wrong():
    src = CHALLENGE_VIEW.read_text()
    start = src.index("    static func allowedWrong")
    end = src.index("\n    }\n", start) + len("\n    }\n")
    return "enum ChallengeViewFx {\n" + src[start:end] + "}\n"


def extract_cheers():
    src = PRONOUNCER.read_text()
    pools = {}
    for name in ("passed", "perfect", "missed"):
        block = re.search(rf"static let {name} = \[(.*?)\n    \]", src, re.S).group(1)
        pools[name] = [
            {"text": t, "key": k, "meaning": m}
            for t, k, m in re.findall(r'Cheer\(text: "([^"]+)",\s*key: "([^"]+)",\s*meaning: "([^"]+)"\)', block)
        ]
    return pools


def extract_clean_word():
    src = VOCAB_STORE.read_text()
    start = src.index("func cleanWord(")
    end = src.index("\n}\n", start) + 3
    return src[start:end]


def main():
    challenge = CHALLENGE.read_text()
    challenge = challenge.replace("@Observable\n", "")
    challenge = challenge.replace("private static func lookalike", "static func lookalike")
    challenge = challenge.replace("private static func options", "static func options")
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        (tmp / "Stubs.swift").write_text(STUBS + extract_clean_word() + extract_allowed_wrong())
        (tmp / "Challenge.swift").write_text(challenge)
        (tmp / "main.swift").write_text(DRIVER)
        (tmp / "input.json").write_text(json.dumps(lessons_from_data(), ensure_ascii=False))
        binary = tmp / "dump"
        build = subprocess.run(
            ["swiftc", "-O", "-o", str(binary), str(tmp / "Stubs.swift"), str(tmp / "Challenge.swift"),
             str(tmp / "main.swift")], capture_output=True, text=True)
        if build.returncode != 0:
            sys.exit(build.stderr)
        run = subprocess.run([str(binary), str(tmp / "input.json")], capture_output=True, text=True)
        if run.returncode != 0:
            sys.exit(run.stderr)
    fixtures = json.loads(run.stdout)
    fixtures["cheers"] = extract_cheers()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(fixtures, ensure_ascii=False, separators=(",", ":"), sort_keys=True) + "\n")
    print(f"wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
