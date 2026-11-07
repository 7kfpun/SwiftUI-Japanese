#!/usr/bin/env python3
"""Generate the Android string resources from nihongo/UIStrings.json (stdlib only).

Writes, under android/app/src/main/res/:

  values/strings.xml, values-<qualifier>/strings.xml   one per UI language (19)
  xml/locales_config.xml                               the per-app language list

Usage:
  python3 scripts/build-android-strings.py            write the files
  python3 scripts/build-android-strings.py --check    write nothing; exit 1 if any file is
                                                      missing, stale or unexpected (CI)

The output is committed; never hand-edit it. See android/CLAUDE.md, "Strings".

Resource names (deterministic, derived from the English key `k`):
  1. lowercase `k`, `%@` -> " arg ", `%` -> " pct ";
  2. every run of characters outside [a-z0-9] -> "_", trimmed of "_";
  3. a name that is empty, starts with a digit or is a Java keyword ("interface") gets "s_";
  4. longer than 60 characters: cut at 52 and append "_" + 7 hex of sha1(k);
  5. names shared by two or more keys get "_" + 7 hex of sha1(k) on all of them.

Values (iOS format string -> Android):
  %@  -> %1$s, %2$s ... in order of appearance (always numbered);
  %%  -> kept as %% when the English value has a placeholder (the app formats it);
         a literal % with formatted="false" otherwise.
  Also escaped: backslash, apostrophe, double quote, & < >, newline, tab, a leading @ or ?,
  and leading/trailing spaces.
"""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "nihongo" / "UIStrings.json"
RES = ROOT / "android" / "app" / "src" / "main" / "res"

# Mirrors L.languageOrder in nihongo/Localization.swift. The first is the default (values/).
# code -> (values folder qualifier, BCP 47 tag for locales_config.xml and AppCompatDelegate).
# zh is Simplified (iOS `zh`) and zh-Hant Traditional; both use script subtags so a phone set
# to zh-CN, zh-SG, zh-TW or zh-HK resolves to the right one. Indonesian is `in` in resource
# qualifiers, the legacy code every Android version accepts.
LANGUAGES = {
    "en": ("", "en"),
    "zh": ("b+zh+Hans", "zh-Hans"),
    "zh-Hant": ("b+zh+Hant", "zh-Hant"),
    "id": ("in", "id"),
    "ko": ("ko", "ko"),
    "vi": ("vi", "vi"),
    "th": ("th", "th"),
    "fil": ("fil", "fil"),
    "my": ("my", "my"),
    "hi": ("hi", "hi"),
    "bn": ("bn", "bn"),
    "ta": ("ta", "ta"),
    "te": ("te", "te"),
    "ne": ("ne", "ne"),
    "es": ("es", "es"),
    "fr": ("fr", "fr"),
    "it": ("it", "it"),
    "de": ("de", "de"),
    "ru": ("ru", "ru"),
}

# Java keywords and literals: aapt2 rejects them as resource names.
JAVA_RESERVED = set(
    "abstract assert boolean break byte case catch char class const continue default do double else enum "
    "extends final finally float for goto if implements import instanceof int interface long native new "
    "package private protected public return short static strictfp super switch synchronized this throw "
    "throws transient try void volatile while true false null".split()
)

# Hand-written resource names generated names must not collide with.
RESERVED = {"app_name"}

PLACEHOLDER = re.compile(r"%@")
UNKNOWN_FORMAT = re.compile(r"%")  # what is left after %% and %@ are removed


def digest(key):
    return hashlib.sha1(key.encode("utf-8")).hexdigest()[:7]


def base_name(key):
    s = key.lower().replace("%@", " arg ").replace("%", " pct ")
    s = re.sub(r"[^a-z0-9]+", "_", s).strip("_")
    if not s or s[0].isdigit() or s in JAVA_RESERVED:
        s = "s_" + s if s else "s"
    if len(s) > 60:
        s = s[:52].rstrip("_") + "_" + digest(key)
    return s


def resource_names(keys):
    base = {k: base_name(k) for k in keys}
    counts = {}
    for n in base.values():
        counts[n] = counts.get(n, 0) + 1
    names = {}
    for k, n in base.items():
        names[k] = n if counts[n] == 1 and n not in RESERVED else n + "_" + digest(k)
    if len(set(names.values())) != len(names):
        raise SystemExit("resource name collision after hashing; widen digest()")
    return names


def escape(value):
    """XML-escape for an Android string resource (no outer quotes)."""
    out = (
        value.replace("\\", "\\\\")
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("'", "\\'")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\t", "\\t")
    )
    if out[:1] in ("@", "?"):
        out = "\\" + out
    if out[:1] == " ":
        out = "\\u0020" + out[1:]
    if out[-1:] == " ":
        out = out[:-1] + "\\u0020"
    return out


def convert(value, formatted):
    """iOS format string -> escaped Android value. `formatted` decides what %% means."""
    if UNKNOWN_FORMAT.search(value.replace("%%", "").replace("%@", "")):
        raise SystemExit(f"unsupported format specifier in {value!r}")
    n = 0

    def number(_):
        nonlocal n
        n += 1
        return f"%{n}$s"

    # Hold %% aside so the escaping pass cannot touch it and %@ numbering cannot see it.
    parts = value.split("%%")
    text = "\x00".join(PLACEHOLDER.sub(number, p) for p in parts)
    text = escape(text)
    return text.replace("\x00", "%%" if formatted else "%")


def comment(text):
    return text.replace("--", "- -").replace("\n", " ")


def render_strings(code, table, names, english):
    lines = ['<?xml version="1.0" encoding="utf-8"?>']
    lines.append("<!-- Generated by scripts/build-android-strings.py from nihongo/UIStrings.json")
    lines.append(f"     ({code}). Do not edit; change the source and regenerate. -->")
    lines.append("<resources>")
    for key in english:
        en_value = english[key]
        formatted = bool(PLACEHOLDER.search(en_value))
        value = table[key]
        if bool(PLACEHOLDER.search(value)) != formatted:
            raise SystemExit(f"{code}: {key!r} has a different placeholder shape than en")
        attrs = ""
        if not formatted and "%" in value:
            attrs = ' formatted="false"'
        if code == "en":
            lines.append(f"    <!-- {comment(key)} -->")
        lines.append(f'    <string name="{names[key]}"{attrs}>{convert(value, formatted)}</string>')
    lines.append("</resources>")
    return "\n".join(lines) + "\n"


def render_locales_config():
    lines = ['<?xml version="1.0" encoding="utf-8"?>']
    lines.append("<!-- Generated by scripts/build-android-strings.py. The UI languages, offered in the")
    lines.append("     system's per-app language setting on Android 13+ and read by AppLanguage. -->")
    lines.append('<locale-config xmlns:android="http://schemas.android.com/apk/res/android">')
    for _, tag in LANGUAGES.values():
        lines.append(f'    <locale android:name="{tag}" />')
    lines.append("</locale-config>")
    return "\n".join(lines) + "\n"


def generate():
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    if set(data) != set(LANGUAGES):
        raise SystemExit(
            f"UIStrings.json languages differ from LANGUAGES: "
            f"+{sorted(set(data) - set(LANGUAGES))} -{sorted(set(LANGUAGES) - set(data))}"
        )
    english = data["en"]
    for code, table in data.items():
        if set(table) != set(english):
            raise SystemExit(f"{code}: keys differ from en: {sorted(set(table) ^ set(english))[:5]}")
    names = resource_names(list(english))
    files = {}
    for code, (qualifier, _) in LANGUAGES.items():
        folder = "values" + (f"-{qualifier}" if qualifier else "")
        files[RES / folder / "strings.xml"] = render_strings(code, data[code], names, english)
    files[RES / "xml" / "locales_config.xml"] = render_locales_config()
    return files


def main():
    check = "--check" in sys.argv[1:]
    files = generate()
    problems = []
    for path, text in files.items():
        if check:
            if not path.is_file():
                problems.append(f"missing: {path.relative_to(ROOT)}")
            elif path.read_text(encoding="utf-8") != text:
                problems.append(f"stale: {path.relative_to(ROOT)}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
    if check:
        for path in RES.glob("values*/strings.xml"):
            if path not in files:
                problems.append(f"unexpected: {path.relative_to(ROOT)}")
        if problems:
            print("\n".join(problems))
            print("Run: python3 scripts/build-android-strings.py")
            return 1
        print(f"android strings up to date ({len(files)} files)")
    else:
        print(f"wrote {len(files)} files under {RES.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
