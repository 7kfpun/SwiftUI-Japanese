#!/usr/bin/env python3
"""Dump the iOS handwriting-scoring maths (nihongo/Kana/KanaSketch.swift) as shared JSON fixtures.

The Android port (android/.../kana/KanaSketch.kt) is asserted against the file this writes,
android/app/src/test/resources/kana/sketch-fixtures.json, so both platforms score a stroke the same way.

How it runs the *real* Swift: it copies KanaSketch.swift to a temp dir, drops the one UIKit-only
region (the on-screen template image, which scoring never touches) and the `import UIKit`, widens
`private static` to `static`, and compiles it with `swiftc` next to a small driver. CoreGraphics and
CoreText behave the same on macOS as on iOS for these calls. No Xcode project, no simulator, no app
build is involved. The bundled KanjiStrokeOrders font is registered from nihongo/Fonts.

The fixtures only use the KanjiStrokeOrders template. The other four template fonts are Apple system
fonts that Android does not have, so they are not part of the shared contract (see android/CLAUDE.md,
"Kana Write scoring").

Usage (macOS, Xcode command line tools):  python3 scripts/dump-kana-sketch-fixtures.py
"""

import json
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKETCH = ROOT / "nihongo" / "Kana" / "KanaSketch.swift"
FONT = ROOT / "nihongo" / "Fonts" / "KanjiStrokeOrders_v4.005.ttf"
OUT = ROOT / "android" / "app" / "src" / "test" / "resources" / "kana" / "sketch-fixtures.json"

# Glyphs whose KanjiStrokeOrders raster, digit-stripped grid and erased-digit count are dumped.
# The last two are combos, which render at the smaller size.
GLYPHS = ["一", "あ", "い", "ア", "に", "ロ", "し", "マ", "ぱ", "ちゅ", "びゃ"]


def wobble(points, amp, seed):
    """Deterministic hand-shake: a small sine offset per point, so the fixture needs no RNG."""
    out = []
    for i, (x, y) in enumerate(points):
        out.append((round(x + amp * math.sin(i * 1.7 + seed), 2), round(y + amp * math.cos(i * 2.3 + seed * 1.3), 2)))
    return out


def seg(a, b, step=6.0):
    n = max(2, int(math.dist(a, b) / step) + 1)
    return [(a[0] + (b[0] - a[0]) * i / (n - 1), a[1] + (b[1] - a[1]) * i / (n - 1)) for i in range(n)]


def poly(*pts, step=6.0):
    out = []
    for a, b in zip(pts, pts[1:]):
        s = seg(a, b, step)
        out.extend(s if not out else s[1:])
    return out


def arc(cx, cy, rx, ry, a0, a1, n=24):
    return [
        (cx + rx * math.cos(math.radians(a0 + (a1 - a0) * i / (n - 1))),
         cy + ry * math.sin(math.radians(a0 + (a1 - a0) * i / (n - 1))))
        for i in range(n)
    ]


# Stroke sets in screen space (y grows downward), arbitrary scale and offset, since the scoring
# normalises position and size away. The target says which glyph the learner meant to draw.
STROKE_SETS = [
    {  # ロ: a clean three-stroke box
        "id": "ro-clean",
        "target": "ロ",
        "expected": 3,
        "strokes": [
            poly((100, 100), (100, 220)),
            poly((100, 100), (220, 100), (220, 220)),
            poly((100, 220), (220, 220)),
        ],
    },
    {  # ロ drawn wobbly, off-centre and small
        "id": "ro-wobbly-small",
        "target": "ロ",
        "expected": 3,
        "strokes": [
            wobble(poly((40, 30), (42, 80), step=4), 1.2, 1),
            wobble(poly((40, 30), (88, 31), (86, 82), step=4), 1.2, 2),
            wobble(poly((41, 80), (86, 82), step=4), 1.2, 3),
        ],
    },
    {  # ロ drawn as one swipe: a scribble the stroke count must punish
        "id": "ro-one-stroke",
        "target": "ロ",
        "expected": 3,
        "strokes": [wobble(poly((100, 100), (100, 220), (220, 220), (220, 100), (100, 100)), 1.0, 4)],
    },
    {  # 一 stretched: per-axis normalisation makes it fill the grid
        "id": "bar",
        "target": "一",
        "expected": 1,
        "strokes": [poly((50, 150), (250, 152))],
    },
    {  # し: one curved stroke
        "id": "shi",
        "target": "し",
        "expected": 1,
        "strokes": [
            poly((130, 60), (130, 190), step=8) + arc(165, 190, 35, 40, 180, 20, 18)[1:],
        ],
    },
    {  # に: a vertical on the left and two bars plus a hook on the right, wobble on
        "id": "ni",
        "target": "に",
        "expected": 3,
        "strokes": [
            wobble(poly((80, 60), (82, 230), step=5), 1.5, 5),
            wobble(poly((140, 100), (240, 98), step=5), 1.5, 6),
            wobble(poly((140, 180), (170, 182), step=5) + arc(190, 195, 28, 30, 250, 20, 14), 1.5, 7),
        ],
    },
    {  # ア: a bar with a hook and a diagonal
        "id": "a-kata",
        "target": "ア",
        "expected": 2,
        "strokes": [
            poly((60, 80), (230, 80), (150, 150), step=7),
            poly((150, 110), (110, 230), step=7),
        ],
    },
    {  # ち hint: a lone dot (a stroke too short to matter)
        "id": "dot",
        "target": "い",
        "expected": 2,
        "strokes": [poly((100, 100), (108, 160)), poly((170, 100), (178, 130))],
    },
]

# Which glyphs each stroke set is scored against: its own target, plus two that are not.
DECOYS = ["ロ", "に", "し", "マ"]

DRIVER = r'''
import Foundation
import CoreGraphics
import CoreText

struct StrokeSet: Decodable { let id: String; let target: String; let expected: Int; let strokes: [[[Double]]] }
struct Input: Decodable { let glyphs: [String]; let sets: [StrokeSet]; let decoys: [String]; let font: String }

func bits(_ g: [Bool]) -> String { String(g.map { $0 ? "1" : "0" }) }
func jstr(_ s: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [s], options: [])
    var t = String(data: data, encoding: .utf8)!
    t.removeFirst(); t.removeLast()
    return t
}

let input = try! JSONDecoder().decode(Input.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
var err: Unmanaged<CFError>?
CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: input.font) as CFURL, .process, &err)

let name = "KanjiStrokeOrders"
var out = "{\n"

// Glyph rasters: raw (pre-strip), erased digit count, final 48x48 grid.
var glyphJSON: [String] = []
var grids: [String: [Bool]] = [:]
for g in input.glyphs {
    var raw = KanaSketch.rawGlyph(g, font: name)!
    let rawBits = bits(raw)
    let erased = KanaSketch.stripTinyComponents(&raw, size: KanaSketch.big)
    let grid = KanaSketch.glyphGrid(g, font: name)!
    grids[g] = grid
    glyphJSON.append("""
    {"glyph": \(jstr(g)), "raw": "\(rawBits)", "erased": \(erased), "grid": "\(bits(grid))"}
    """)
}
out += "\"glyphs\": [\n" + glyphJSON.joined(separator: ",\n") + "\n],\n"

// Stroke grids, distances and end-to-end scores (KanjiStrokeOrders template only).
var setJSON: [String] = []
for s in input.sets {
    let pts = s.strokes.map { $0.map { CGPoint(x: $0[0], y: $0[1]) } }
    let sg = KanaSketch.strokeGrid(pts)!
    var cmp: [String] = []
    for t in ([s.target] + input.decoys.filter { $0 != s.target }) {
        guard let tg = grids[t] ?? KanaSketch.glyphGrid(t, font: name) else { continue }
        grids[t] = tg
        let d = KanaSketch.distance(sg, tg)
        let zd = KanaSketch.zoneDiff(KanaSketch.zones(sg), KanaSketch.zones(tg))
        var score = 100 - d * 3.5
        score -= Double(abs(pts.count - s.expected)) * 10
        let final = max(0, min(100, Int(score.rounded())))
        let bare = max(0, min(100, Int((100 - d * 3.5).rounded())))
        cmp.append("""
        {"glyph": \(jstr(t)), "distance": \(d), "zoneDiff": \(zd), "score": \(final), "scoreNoPenalty": \(bare)}
        """)
    }
    let strokeJSON = s.strokes.map { "[" + $0.map { "[\($0[0]),\($0[1])]" }.joined(separator: ",") + "]" }
    setJSON.append("""
    {"id": \(jstr(s.id)), "target": \(jstr(s.target)), "expectedStrokes": \(s.expected),
     "strokes": [\(strokeJSON.joined(separator: ","))], "grid": "\(bits(sg))",
     "comparisons": [\(cmp.joined(separator: ","))]}
    """)
}
out += "\"sets\": [\n" + setJSON.joined(separator: ",\n") + "\n]\n}\n"
print(out)
'''


def main() -> int:
    src = SKETCH.read_text(encoding="utf-8")
    src = src.replace("import UIKit\n", "")
    start = src.index("// MARK: - on-screen trace template (Write mode)")
    end = src.index("// MARK: - chamfer matching")
    src = src[:start] + src[end:]
    src = re.sub(r"\bprivate static\b", "static", src)

    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        (tmp / "KanaSketch.swift").write_text(src, encoding="utf-8")
        (tmp / "main.swift").write_text(DRIVER, encoding="utf-8")
        sets = [
            {**s, "strokes": [[[round(x, 3), round(y, 3)] for x, y in st] for st in s["strokes"]]}
            for s in STROKE_SETS
        ]
        (tmp / "input.json").write_text(
            json.dumps({"glyphs": GLYPHS, "sets": sets, "decoys": DECOYS, "font": str(FONT)}), encoding="utf-8"
        )
        exe = tmp / "dump"
        subprocess.run(
            ["swiftc", "-O", str(tmp / "KanaSketch.swift"), str(tmp / "main.swift"), "-o", str(exe)],
            check=True,
        )
        result = subprocess.run([str(exe), str(tmp / "input.json")], check=True, capture_output=True, text=True)
    data = json.loads(result.stdout)
    data["meta"] = {
        "source": "nihongo/Kana/KanaSketch.swift via scripts/dump-kana-sketch-fixtures.py",
        "template": "KanjiStrokeOrders only",
        "grid": 48,
        "raw": 160,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"wrote {OUT.relative_to(ROOT)} ({OUT.stat().st_size // 1024} KB)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
