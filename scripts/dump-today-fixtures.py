#!/usr/bin/env python3
"""Dump the iOS Today hourly rotation (Shared/TodayShared.swift) as shared JSON fixtures.

The Android port (android/.../today/TodayShared.kt) is asserted against the file this writes,
android/app/src/test/resources/today/rotation-fixtures.json, so the app and the widget pick the same word of the
same deck at the same instant on both platforms.

How it runs the *real* Swift: it copies TodayShared.swift to a temp dir, replaces the two members that lean on
`Course` (`appGroup`, `sampleWords`) with stubs, and compiles it with `swiftc` next to a small driver. No Xcode
project, no simulator, no app build is involved.

Usage (macOS, Xcode command line tools):  python3 scripts/dump-today-fixtures.py
"""

import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Shared" / "TodayShared.swift"
OUT = ROOT / "android" / "app" / "src" / "test" / "resources" / "today" / "rotation-fixtures.json"

# Epoch seconds: a boundary, mid-hour, a day apart, a DST-ish spring date, the epoch itself, and a pre-epoch instant.
TIMES = [0.0, 1.0, 3599.0, 3600.0, 1_700_000_000.0, 1_700_001_234.5, 1_772_000_000.0, 1_798_761_599.0, -1.0, -3600.0]
COUNTS = [0, 1, 7, 20, 23]
CURSORS = [-20, -3, 0, 5, 1000]

DRIVER = """
import Foundation

let times: [Double] = %s
let counts: [Int] = %s
let cursors: [Int] = %s

var rows: [[String: Any]] = []
for t in times {
    let date = Date(timeIntervalSince1970: t)
    for count in counts {
        for cursor in cursors {
            rows.append([
                "t": t, "count": count, "cursor": cursor,
                "index": TodayShared.rotationIndex(count: count, cursor: cursor, at: date),
            ])
        }
    }
}
var slots: [[String: Any]] = []
for t in times {
    let date = Date(timeIntervalSince1970: t)
    slots.append(["t": t, "slot": TodayShared.hourSlot(date),
                  "nextHour": TodayShared.nextHour(after: date).timeIntervalSince1970])
}
let data = try! JSONSerialization.data(withJSONObject: ["rotation": rows, "slots": slots],
                                       options: [.sortedKeys])
print(String(data: data, encoding: .utf8)!)
"""


def main() -> int:
    text = SOURCE.read_text()
    text, n1 = re.subn(r"static var appGroup: String \{[^}]*\}", 'static var appGroup: String { "stub" }', text)
    text, n2 = re.subn(r"static var sampleWords: \[Word\] \{[^}]*\}", "static var sampleWords: [Word] { [] }", text)
    if n1 != 1 or n2 != 1:
        print("TodayShared.swift changed shape: update the stubs in this script", file=sys.stderr)
        return 1
    driver = DRIVER % (json.dumps(TIMES), json.dumps(COUNTS), json.dumps(CURSORS))
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        (tmp / "TodayShared.swift").write_text(text)
        (tmp / "main.swift").write_text(driver)
        exe = tmp / "dump"
        subprocess.run(["swiftc", "-O", "-o", str(exe), str(tmp / "TodayShared.swift"), str(tmp / "main.swift")],
                       check=True)
        out = subprocess.run([str(exe)], check=True, capture_output=True, text=True).stdout
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(json.loads(out), indent=1, sort_keys=True) + "\n")
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
