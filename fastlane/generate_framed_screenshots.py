#!/usr/bin/env python3
"""Composite the raw iOS Simulator screenshots — iPhone captures in
fastlane/screenshot_raw/iphone/*.png (1206x2622 on the "iPhone 17 Pro"
simulator), iPad captures in fastlane/screenshot_raw/ipad/*.png (2064x2752 on
the "iPad Pro 13-inch (M5)" simulator) — into framed, titled App Store marketing
screenshots: gradient background + bold rounded headline + official Apple device
frame, rendered at the exact pixel resolutions App Store Connect / fastlane
`deliver` require. Pure Pillow, no ImageMagick (frameit's own tool needs
ImageMagick's `convert`, which isn't installed on this machine and needs
sudo/brew doctor fixes to install — this script reimplements the same idea
directly with Pillow).

Two directories, one job each:

    fastlane/screenshot_raw/<device>/    hand-captured, the only real source
    fastlane/screenshots/<locale>/       generated, exactly what deliver uploads

There is deliberately no intermediate tree: this writes final upload filenames
straight into the locale folders. Note that `deliver` reads *every* subdirectory
of its screenshots_path as a locale (see Deliver::Loader::LanguageFolder), so
nothing but locale folders may live under fastlane/screenshots/ — which is why
the raw captures sit in their own top-level directory rather than beneath it.

Usage:
    arch -x86_64 python3 fastlane/generate_framed_screenshots.py [filter]
    arch -x86_64 python3 fastlane/generate_framed_screenshots.py --check [locale]

Run from the repo root. Pass an optional substring filter (e.g. "01-today")
to render just one screenshot while iterating on copy/layout.

`--check` renders nothing; it audits the copy in LOCALES against the fonts in
LOCALE_TYPOGRAPHY — every character must have a real glyph, and every wrapped
line must fit the canvas width on every device. Run it after any copy or font
edit; a missing glyph or an overflowing line is silent at render time and only
shows up as tofu boxes / clipped text in the uploaded screenshot.

LOCALES covers every App Store localization except `hi` — Devanagari and Tamil
cannot be rendered correctly without a text shaper, and this Pillow has none.
That call is argued out in full in the comment below LOCALES; don't add either
locale back without reading it.

NOTE on architecture: the Pillow wheel installed on this machine is x86_64
only; plain `python3` on Apple Silicon resolves to the arm64 slice and can't
load Pillow's compiled extension. Always run this via `arch -x86_64 python3`
(or reinstall an arm64-native Pillow with `pip install --force-reinstall
--no-binary :all: pillow` if you'd rather fix that properly).

Outputs are fastlane/screenshots/<locale>/<key>-<device>.png, where <device> is
one of 6.9 / 6.3 / ipad13 — matching the APP_IPHONE_67 "6.9-inch"
mandatory/largest bucket, the APP_IPHONE_61 "6.1-6.3-inch" bucket, and the
APP_IPAD_PRO_3GEN_129 "13-inch iPad" bucket. deliver resolves which bucket a
file belongs to from its pixel size alone; the `-<device>` suffix exists only to
keep names unique within a locale folder. Once this has run, upload with
`bundle exec fastlane screenshots` (the deliver lane in fastlane/Fastfile) —
no copying or staging step in between.

Apple/deliver caps each device-size screenshot set at 10 images per locale,
so with 14 source screenshots only the first 10 alphabetically (01-10) will
upload per device size — trim COPY below to <=10 entries, or rename/reorder,
if you want a different 10 featured.

Device frame assets (official, Facebook Design-redrawn Apple device frames,
used by fastlane's own `frameit` action) are vendored in
fastlane/screenshot_frames/. If missing, they're fetched from
https://fastlane.github.io/frameit-frames/latest/<filename> (the same public,
versioned CDN frameit itself downloads from — see
fastlane's frameit/lib/frameit/frame_downloader.rb for reference).
"""
import os
import shutil
import sys
import urllib.parse
import urllib.request

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Device frames are the one shared asset — the same phone, whichever app is inside it.
FRAMES_DIR = os.path.join(ROOT, "fastlane/screenshot_frames")

# Two apps ship from this repo, and each owns a folder. `--app jlpt` switches the
# captures read, the folder written, and the marketing copy — all three together,
# because rendering one app's copy over the other's captures produces files that
# look completely plausible and are wrong.
APP = "minna"


def app_paths(app):
    base = os.path.join(ROOT, "fastlane", app)
    return (os.path.join(base, "screenshot_raw/iphone"),
            os.path.join(base, "screenshot_raw/ipad"),
            os.path.join(base, "screenshots"))


RAW_DIR, IPAD_RAW_DIR, OUT_DIR = app_paths(APP)
FRAMES_CDN = "https://fastlane.github.io/frameit-frames/latest"

# Display faces, one per script. The house style is *rounded* — it matches the
# app's own visual identity (Theme.jp is a rounded face; see context/07-ux-ui.md)
# — so every entry below is the roundest face on macOS that actually has the
# script's glyphs. Which font each locale gets is LOCALE_TYPOGRAPHY, below.
FONT_ARIAL_ROUNDED = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
FONT_SF_ROUNDED = "/System/Library/Fonts/SFNSRounded.ttf"
FONT_HEITI = "/System/Library/Fonts/STHeiti Medium.ttc"
FONT_SUKHUMVIT = "/System/Library/Fonts/Supplemental/SukhumvitSet.ttc"
FONT_HIRA_MARU = "/System/Library/Fonts/ヒラギノ丸ゴ ProN W4.ttc"
FONT_APPLE_SD_GOTHIC = "/System/Library/Fonts/AppleSDGothicNeo.ttc"

# Brand gradient, per app — the two ends of the background every headline sits on.
#
# **Per app deliberately.** Both apps build from one codebase and shipped the same teal;
# App Review rejected the JLPT listing as too close to Minna. The screenshots are the
# first thing a reviewer and a browser see, so they carry the difference first.
#
# minna: BLUE sampled from nihongo/Assets.xcassets/AppIcon.appiconset/AppIcon.png, TEAL
# from its AccentColor.colorset (also --accent: #0FB0BF in scripts/build-web.py).
# jlpt: a deep amber into orange, matching the #FFA500 accent that app now ships. Not
# exactly #FFA500 at either end — a flat fill of the accent leaves white headline text
# barely legible, so the gradient runs darker at the top where the text sits.
GRADIENTS = {
    "minna": ((12, 83, 148), (15, 176, 191)),
    "jlpt":  ((150, 74, 0), (255, 165, 0)),
}
BLUE, TEAL = GRADIENTS["minna"]

# Device targets. `off` / `off_w` come from frameit-frames' offsets.json: where
# (in the frame PNG's own native pixel grid) the screenshot layer must be
# pasted, and how wide it must be resized to, before the frame art is
# layered on top.
DEVICES = {
    # Apple Watch Series 10, 416x496 — the size ASC wants, and the size the raw
    # capture already is. `raw_dir="watch"` because the shot lives beside the phone
    # and iPad captures rather than among them, and `frame=None` selects the
    # frameless path in `process`. Headline only: at 416px wide a subtitle under a
    # headline leaves the screen no room, so `COPY` gives this key an empty one.
    "watch": dict(canvas=(416, 496), frame=None, raw_dir="watch",
                  off=(0, 0), off_w=416),
    "6.9": dict(canvas=(1320, 2868), frame="Apple iPhone 17 Pro Max Silver.png",
                off=(75, 66), off_w=1320),
    "6.3": dict(canvas=(1206, 2622), frame="Apple iPhone 17 Pro Silver.png",
                off=(72, 69), off_w=1206),
    # 13-inch iPad (ASC's APP_IPAD_PRO_3GEN_129 bucket). Raw captures come from
    # the "iPad Pro 13-inch (M5)" simulator at its native 2064x2752 — the canvas
    # matches that 1:1. No frameit-frames asset exists yet for the M4/M5 13-inch
    # panel, so this reuses the 12.9-inch (4th gen) frame (2048x2732, near-identical
    # aspect) purely as decorative device art; it doesn't affect the required
    # output pixel size.
    "ipad13": dict(canvas=(2064, 2752), frame="Apple iPad Pro (12.9-inch) (4th generation) Silver.png",
                   # `ipad=True`, not `raw_dir=IPAD_RAW_DIR`. A path baked in here is
                   # captured at import time, so `--app` could not move it — and the
                   # iPad shots silently rendered one app's captures under the other
                   # app's copy, which looks entirely plausible and is wrong.
                   off=(96, 102), off_w=2048, ipad=True),
}

# headline, subtitle for each raw screenshot (<raw dir>/<key>.png), per App
# Store Connect locale. The screenshots themselves are the same
# English-UI captures for every locale (re-capturing the app UI in each
# language is out of scope here — "just the frame") — only the marketing
# title/subtitle overlay is localized.
#
# Curated to exactly 10 — Apple/deliver caps each device-size screenshot set
# at 10 images per locale, so all 10 of these upload cleanly with nothing
# skipped. Dropped from the original 14 (still available as raw captures in
# fastlane/screenshot_sources/raw/iphone/*.png if you want to swap any back in):
#   05-kana-swipe        - redundant with quiz/flashcards, generic UX pattern
#   10-lesson-flashcards - redundant with kana flashcards + lesson-learn
#   13-settings          - settings screens don't sell an app
#   14-paywall           - best practice: never lead with your paywall
LOCALES = {
    "en-US": {
        "01-watch-today": ("On your wrist", ""),
        "01-today": ("Track your progress", "Every day, at a glance"),
        "02-kana-table": ("Hiragana & Katakana", "The complete kana charts"),
        "03-kana-flashcards": ("Kana flashcards", "Flip, listen, remember"),
        "04-kana-quiz-classic": ("Kana quizzes", "Test yourself, kana by kana"),
        # Not "native audio": the clips are synthesised (`say -v Kyoko`), and two
        # `~`-placeholder sentence templates have no clip at all. The whole store
        # listing and the in-app paywall now claim what the audio is *for* rather
        # than who recorded it, and the screenshots are the most-seen surface of
        # the three, so they must say the same thing.
        "06-kana-listening": ("Listening practice", "Every kana spoken, to help it stick"),
        "07-kana-write": ("Write practice", "Real stroke order, real memory"),
        "00-lessons": ("50 Minna no Nihongo lessons", "Every lesson, right on your phone"),
        "09-vocab-list": ("We speak your language", "Every word explained in 19 languages"),
        "11-lesson-learn": ("Learn mode", "Swipe through new words with audio"),
        "12-lesson-quiz": ("Lesson quizzes", "Check what you've really learned"),
    },
    "de-DE": {
        "01-watch-today": ("Am Handgelenk", ""),
        "01-today": ("Verfolge deinen Fortschritt", "Jeden Tag auf einen Blick"),
        "02-kana-table": ("Hiragana & Katakana", "Die kompletten Kana-Tabellen"),
        "03-kana-flashcards": ("Kana-Karteikarten", "Umdrehen, hören, merken"),
        "04-kana-quiz-classic": ("Kana-Quiz", "Teste dich, Kana für Kana"),
        "06-kana-listening": ("Hörverständnis", "Jedes Kana vorgelesen, damit es sitzt"),
        "07-kana-write": ("Schreibübung", "Echte Strichfolge, echtes Gedächtnis"),
        # Not "50 Minna-no-Nihongo-Lektionen": German compounding makes that one
        # unbreakable 26-character token, 140% of the text column, and word wrapping has
        # nowhere to break it — it shipped clipped at both edges. Keeping the title as a
        # separate phrase after a colon lets it wrap at real spaces.
        "00-lessons": ("Minna no Nihongo: 50 Lektionen", "Jede Lektion direkt auf deinem Handy"),
        "09-vocab-list": ("Wir sprechen deine Sprache", "Jedes Wort erklärt in 19 Sprachen"),
        "11-lesson-learn": ("Lernmodus", "Neue Wörter mit Audio durchblättern"),
        "12-lesson-quiz": ("Lektionsquiz", "Prüfe, was du wirklich gelernt hast"),
    },
    "zh-Hant": {
        "01-watch-today": ("戴在手腕上", ""),
        "01-today": ("追蹤你的學習進度", "每天一目了然"),
        "02-kana-table": ("五十音", "完整的平假名與片假名表"),
        "03-kana-flashcards": ("五十音字卡", "翻牌、聆聽、記住"),
        "04-kana-quiz-classic": ("五十音測驗", "一個一個考考自己"),
        "06-kana-listening": ("聽力練習", "每個假名都朗讀，聽了就記住"),
        "07-kana-write": ("書寫練習", "正確筆順，真正記住"),
        "00-lessons": ("50 課大家的日本語課程", "每一課都在你的手機裡"),
        "09-vocab-list": ("我們懂你的語言", "19 種語言，逐字講解"),
        "11-lesson-learn": ("學習模式", "滑動瀏覽新單字並聽發音"),
        "12-lesson-quiz": ("課程測驗", "檢查你真正學到了什麼"),
    },
    "ru": {
        "01-watch-today": ("На запястье", ""),
        "01-today": ("Следи за прогрессом", "Каждый день — как на ладони"),
        "02-kana-table": ("Хирагана и катакана", "Полные таблицы каны"),
        "03-kana-flashcards": ("Карточки каны", "Переверни, послушай, запомни"),
        "04-kana-quiz-classic": ("Тесты по кане", "Проверь себя знак за знаком"),
        "06-kana-listening": ("Тренировка слуха", "Каждый знак озвучен — и запомнится"),
        "07-kana-write": ("Учись писать", "Настоящий порядок черт"),
        "00-lessons": ("50 уроков Minna no Nihongo", "Каждый урок — в твоём телефоне"),
        "09-vocab-list": ("Говорим на твоём языке", "Каждое слово — на 19 языках"),
        "11-lesson-learn": ("Режим изучения", "Новые слова с озвучкой"),
        "12-lesson-quiz": ("Тесты по уроку", "Проверь, что ты правда выучил"),
    },
    # Vietnamese literals here must stay in NFC (precomposed ế ộ ữ ằ ọ, one
    # codepoint each). Pillow is built without libraqm on this machine, so it
    # does no complex-script shaping: NFD sequences (base + combining acute)
    # would be drawn as two separate advancing glyphs and come out mangled,
    # whereas the precomposed forms are single glyphs that need no shaping.
    "vi": {
        "01-watch-today": ("Ngay trên cổ tay", ""),
        "01-today": ("Theo dõi tiến độ", "Mỗi ngày, chỉ một cái nhìn"),
        "02-kana-table": ("Hiragana & Katakana", "Bảng chữ kana đầy đủ"),
        "03-kana-flashcards": ("Thẻ ghi nhớ kana", "Lật, nghe, ghi nhớ"),
        "04-kana-quiz-classic": ("Trắc nghiệm kana", "Tự kiểm tra từng chữ kana"),
        "06-kana-listening": ("Luyện nghe", "Kana nào cũng có âm thanh, nhớ lâu"),
        "07-kana-write": ("Luyện viết", "Thứ tự nét đúng, nhớ lâu hơn"),
        "00-lessons": ("50 bài Minna no Nihongo", "Trọn bộ bài học trong túi bạn"),
        "09-vocab-list": ("Nói đúng tiếng của bạn", "Mỗi từ giải nghĩa bằng 19 thứ tiếng"),
        "11-lesson-learn": ("Chế độ học", "Lướt qua từ mới kèm âm thanh"),
        "12-lesson-quiz": ("Trắc nghiệm bài học", "Kiểm tra bạn thật sự nhớ gì"),
    },
    # Thai is deliberately written short enough that every line below fits the
    # canvas on its own — see the wrap="word" note in LOCALE_TYPOGRAPHY for why
    # that matters, and run `--check` after editing any of it.
    "th": {
        "01-watch-today": ("บนข้อมือคุณ", ""),
        "01-today": ("ติดตามความก้าวหน้า", "เห็นทุกวันในหน้าเดียว"),
        "02-kana-table": ("ฮิรางานะ & คาตาคานะ", "ตารางคานะครบทุกตัว"),
        "03-kana-flashcards": ("บัตรคำคานะ", "พลิก ฟัง จำได้"),
        "04-kana-quiz-classic": ("แบบทดสอบคานะ", "ทดสอบตัวเองทีละตัว"),
        "06-kana-listening": ("ฝึกฟัง", "ทุกตัวคานะมีเสียงอ่าน จำได้แน่น"),
        "07-kana-write": ("ฝึกเขียน", "ลำดับเส้นถูกต้อง จำได้จริง"),
        "00-lessons": ("50 บทเรียน Minna no Nihongo", "ครบทุกบทอยู่ในมือคุณ"),
        "09-vocab-list": ("เราพูดภาษาของคุณ", "ทุกคำแปลครบ 19 ภาษา"),
        "11-lesson-learn": ("โหมดเรียนรู้", "ปัดดูคำใหม่พร้อมเสียงอ่าน"),
        "12-lesson-quiz": ("แบบทดสอบบทเรียน", "ตรวจว่าคุณจำได้จริงไหม"),
    },
    # The Latin-script locales below reuse the mode names the app's own UI shows
    # in that language (nihongo/UIStrings.json: Test/Tarjetas/Aprender,
    # Quiz/Cartes mémo/Apprendre, Pagsusulit/Matuto, Kuis/Kartu kilas/Belajar),
    # so a screenshot caption and the screen under it use the same word.
    "es-ES": {
        "01-watch-today": ("En tu muñeca", ""),
        "01-today": ("Sigue tu progreso", "Cada día, de un vistazo"),
        "02-kana-table": ("Hiragana y katakana", "Las tablas de kana completas"),
        "03-kana-flashcards": ("Tarjetas de kana", "Gira, escucha, recuerda"),
        "04-kana-quiz-classic": ("Test de kana", "Ponte a prueba kana a kana"),
        "06-kana-listening": ("Entrena el oído", "Cada kana con voz, para que se fije"),
        "07-kana-write": ("Escritura a mano", "Orden real de trazos, memoria real"),
        "00-lessons": ("Minna no Nihongo: 50 lecciones", "Cada lección en tu bolsillo"),
        "09-vocab-list": ("En tu idioma", "Cada palabra explicada en 19 idiomas"),
        "11-lesson-learn": ("Modo Aprender", "Desliza palabras nuevas con voz"),
        "12-lesson-quiz": ("Test de la lección", "Comprueba lo que sabes de verdad"),
    },
    # Straight ASCII apostrophes, as in en-US, not U+2019: Arial Rounded Bold does
    # carry the typographic apostrophe, but mixing the two across locales in one
    # file is how a stray one ends up somewhere that can't render it.
    "fr-FR": {
        "01-watch-today": ("À ton poignet", ""),
        "01-today": ("Suis ta progression", "Chaque jour, d'un seul regard"),
        "02-kana-table": ("Hiragana et katakana", "Les tableaux de kana complets"),
        "03-kana-flashcards": ("Cartes mémo de kana", "Retourne, écoute, retiens"),
        "04-kana-quiz-classic": ("Quiz de kana", "Teste-toi, kana par kana"),
        "06-kana-listening": ("Entraîne ton oreille", "Chaque kana prononcé, pour l'ancrer"),
        "07-kana-write": ("Écriture à la main", "Le vrai ordre des traits"),
        "00-lessons": ("Minna no Nihongo : 50 leçons", "Chaque leçon dans ta poche"),
        "09-vocab-list": ("On parle ta langue", "Chaque mot en 19 langues"),
        "11-lesson-learn": ("Mode Apprendre", "Fais défiler les mots, avec le son"),
        "12-lesson-quiz": ("Quiz de la leçon", "Vérifie ce que tu sais vraiment"),
    },
    "id": {
        "01-watch-today": ("Di pergelanganmu", ""),
        "01-today": ("Pantau kemajuan", "Setiap hari, sekali lihat"),
        "02-kana-table": ("Hiragana dan katakana", "Tabel kana yang lengkap"),
        "03-kana-flashcards": ("Kartu kilas kana", "Balik, dengar, ingat"),
        "04-kana-quiz-classic": ("Kuis kana", "Uji dirimu, satu per satu"),
        "06-kana-listening": ("Latihan menyimak", "Tiap kana ada suaranya"),
        "07-kana-write": ("Latihan menulis", "Urutan coretan yang sebenarnya"),
        "00-lessons": ("Minna no Nihongo: 50 pelajaran", "Tiap pelajaran di sakumu"),
        "09-vocab-list": ("Kami bicara bahasamu", "Tiap kata dalam 19 bahasa"),
        "11-lesson-learn": ("Mode Belajar", "Geser kata baru, ada suaranya"),
        "12-lesson-quiz": ("Kuis pelajaran", "Cek yang benar-benar kamu kuasai"),
    },
    # Japanese: the one locale whose store copy can use the textbook's real
    # Japanese title, みんなの日本語, rather than the romanisation. Titles are kept
    # to eight characters or fewer because wrap="char" would otherwise break a
    # headline mid-word to make it fit — see the ja entry in LOCALE_TYPOGRAPHY.
    "ja": {
        "01-watch-today": ("手首の上で", ""),
        "01-today": ("進捗はひと目で", "毎日の学習を記録"),
        "02-kana-table": ("ひらがな・カタカナ", "全チャートを収録"),
        "03-kana-flashcards": ("フラッシュカード", "めくって、聴いて、覚える"),
        "04-kana-quiz-classic": ("かなクイズ", "1文字ずつ力試し"),
        "06-kana-listening": ("リスニング練習", "すべてのかなに音声つき"),
        "07-kana-write": ("手書き練習", "本物の筆順で採点"),
        "00-lessons": ("みんなの日本語50課", "どの課もポケットの中に"),
        "09-vocab-list": ("あなたの言語で", "全単語を19言語で解説"),
        "11-lesson-learn": ("学習モード", "新しい単語を音声つきでめくる"),
        "12-lesson-quiz": ("レッスンのクイズ", "本当に覚えたかを確認"),
    },
    "it": {
        "01-watch-today": ("Al tuo polso", ""),
        "01-today": ("Segui i tuoi progressi", "Ogni giorno, a colpo d'occhio"),
        "02-kana-table": ("Hiragana e Katakana", "Le tabelle kana complete"),
        "03-kana-flashcards": ("Flashcard dei kana", "Gira, ascolta, memorizza"),
        "04-kana-quiz-classic": ("Quiz sui kana", "Mettiti alla prova, kana per kana"),
        "06-kana-listening": ("Esercizi di ascolto", "Ogni kana pronunciato, per ricordarlo"),
        "07-kana-write": ("Esercizi di scrittura", "Ordine dei tratti autentico"),
        # No textbook name, unlike the older locales above — see the note on Guideline
        # 5.2 in CLAUDE.md. A screenshot headline is a user-visible store field.
        "00-lessons": ("50 lezioni di giapponese", "Ogni lezione, sul tuo telefono"),
        "09-vocab-list": ("Parliamo la tua lingua", "Ogni parola spiegata in 19 lingue"),
        "11-lesson-learn": ("Modalità Learn", "Scorri tra le parole nuove con l'audio"),
        "12-lesson-quiz": ("Quiz delle lezioni", "Verifica ciò che hai imparato"),
    },
    "ko": {
        "01-watch-today": ("손목 위에서", ""),
        "01-today": ("진도를 한눈에", "매일의 학습을 기록"),
        "02-kana-table": ("히라가나·가타카나", "가나 표 전체 수록"),
        "03-kana-flashcards": ("가나 플래시카드", "넘기고, 듣고, 기억하기"),
        "04-kana-quiz-classic": ("가나 퀴즈", "한 글자씩 확인하기"),
        "06-kana-listening": ("듣기 연습", "모든 가나에 음성 제공"),
        "07-kana-write": ("손글씨 연습", "실제 획순으로 채점"),
        "00-lessons": ("Minna no Nihongo 50과", "모든 레슨이 주머니 속에"),
        "09-vocab-list": ("당신의 언어로", "모든 단어를 17개 언어로"),
        "11-lesson-learn": ("학습 모드", "새 단어를 음성과 함께 넘기기"),
        "12-lesson-quiz": ("레슨 퀴즈", "정말 익혔는지 확인"),
    },
}

# Store locales deliberately left without screenshots: `hi` (Devanagari) and `ta`
# (Tamil). Both are conjunct-forming scripts, and this Pillow has no libraqm, so
# there is no shaping at all — the same limitation that ruled out Thonburi for
# Thai, only worse, because for these two it is the *text* that comes out wrong
# rather than one mark. Measured, not assumed, against every Devanagari and Tamil
# face on macOS (Kohinoor, Devanagari Sangam MN, ITF Devanagari, Devanagari MT,
# .SF Devanagari; Tamil Sangam MN, Tamil MN, InaiMathi, .SF Tamil):
#
#   Devanagari - the virama never triggers the conjunct substitution, so स्ट्रोक,
#   प्र and र् render as base + visible halant + base instead of the stacked and
#   subjoined forms. Hindi cannot be written around this: हिरागाना (hiragana),
#   लिखावट (handwriting), अभ्यास (practice) and क्विज़ (quiz) all need conjuncts
#   or a pre-base i-matra, so there is no wording that dodges it.
#
#   Tamil - the pre-base vowel signs ெ ே ை render to the *right* of their
#   consonant (கே comes out as க+ே), the two-part signs ொ ோ ௌ render as a
#   dotted-circle placeholder, and the pulli ் is zero-advance but unpositioned,
#   so it lands between two letters instead of above one.
#
# A legacy "visual order" workaround (storing the matra codepoints pre-reordered)
# was tried and rejected: it cannot form Devanagari conjuncts at all, it leaves
# Tamil's pulli misplaced, and it would put text into this file that is not valid
# Hindi or Tamil — which `--check` cannot audit, since every codepoint still has
# a glyph. Shipping mangled Devanagari is worse than shipping no hi screenshots,
# so these two locales fall back to en-US's set on the store. To add them
# properly, this script needs a shaping engine: a Pillow built with libraqm, or
# pre-rendering the headline through CoreText.

# Locales that ship another locale's rendered images verbatim. Simplified Chinese
# readers get the Traditional copy rather than an empty screenshot set; swap this
# for a real "zh-Hans" block in LOCALES above once the copy is translated.

# The JLPT app's copy. Only the locales its listing actually carries — en-US and
# zh-Hant, with zh-Hans aliased onto the latter by LOCALE_ALIASES below.
#
# Two lines deliberately differ from minna's beyond the numbers. `08-lessons` names
# no textbook (Guideline 5.2), and `09-vocab-list` does not say "17 languages": this
# app's *interface* is 17, but its meanings are English and Traditional Chinese, and
# the screenshot is the most-seen surface of the three that could get that wrong.
JLPT_LOCALES = {
    "en-US": {
        "01-today": ("Track your progress", "Every day, at a glance"),
        "05-progress": ("Make it a habit", "Streak, stats and bookmarks in one place"),
        "02-kana-table": ("Hiragana & Katakana", "The complete kana charts"),
        "03-kana-flashcards": ("Kana flashcards", "Flip, listen, remember"),
        "04-kana-quiz-classic": ("Kana quizzes", "Test yourself, kana by kana"),
        "06-kana-listening": ("Listening practice", "Every kana spoken, to help it stick"),
        "07-kana-write": ("Write practice", "Real stroke order, real memory"),
        "00-lessons": ("201 lessons, N5 to N1", "7,972 words in teaching order"),
        "09-vocab-list": ("Hear every word", "All 7,972, spoken and explained"),
        "11-lesson-learn": ("Learn mode", "Swipe through new words with audio"),
        "12-lesson-quiz": ("Lesson quizzes", "Check what you've really learned"),
    },
    "zh-Hant": {
        "01-today": ("追蹤你的學習進度", "每天一目了然"),
        "05-progress": ("養成每日習慣", "連續天數、統計與書籤，一目了然"),
        "02-kana-table": ("五十音", "完整的平假名與片假名表"),
        "03-kana-flashcards": ("五十音字卡", "翻牌、聆聽、記住"),
        "04-kana-quiz-classic": ("五十音測驗", "一個一個考考自己"),
        "06-kana-listening": ("聽力練習", "每個假名都朗讀，聽了就記住"),
        "07-kana-write": ("書寫練習", "正確筆順，真正記住"),
        "00-lessons": ("201 課，N5 到 N1", "7,972 個單字，依教學順序"),
        "09-vocab-list": ("每個單字都能聽", "全部 7,972 個，有發音也有解釋"),
        "11-lesson-learn": ("學習模式", "滑動瀏覽新單字並聽發音"),
        "12-lesson-quiz": ("課程測驗", "檢查你真正學到了什麼"),
    },
}

APP_LOCALES = {"minna": LOCALES, "jlpt": JLPT_LOCALES}

LOCALE_ALIASES = {"zh-Hans": "zh-Hant"}

# Per-locale typography. This used to be a single boolean — "CJK or not" — which
# picked one of two fonts and one of two wrap modes; that can't express six
# scripts, so it's a mapping now, with DEFAULT_TYPOGRAPHY for anything unlisted.
# Unlisted means Arial Rounded Bold + word wrapping, which is right for every
# plain-Latin locale (en-US, de-DE, es-ES, fr-FR, id).
# Keys:
#   font    path to a .ttf/.ttc
#   index   face index inside a .ttc collection (ignored for a plain .ttf)
#   weight  named instance of a *variable* font, or None. SF NS Rounded ships
#           every weight in one file and defaults to Regular, which looks
#           anaemic beside the other locales' bold titles — so it must be
#           pinned to "Bold" explicitly.
#   wrap    "word" breaks only at spaces; "char" breaks between any two
#           characters (see draw_centered_text).
#
# Font choices are driven by glyph coverage first, roundness second. Arial
# Rounded MT Bold — the default, and the right face for the app's rounded
# identity — carries only 241 glyphs: Latin-1 and nothing more. It has *no*
# Cyrillic whatsoever, no Latin Extended Additional (so none of Vietnamese's
# stacked-diacritic vowels ế ộ ữ ằ ọ), no Thai, no CJK. Verified, not assumed:
# `--check` asserts every character of every string has a real glyph.
DEFAULT_TYPOGRAPHY = dict(font=FONT_ARIAL_ROUNDED, index=0, weight=None, wrap="word")
LOCALE_TYPOGRAPHY = {
    # Chinese: "Heiti TC" (face 0 of STHeiti Medium.ttc, a stable base macOS
    # system font) covers Traditional and Simplified cleanly at a reasonably
    # bold weight. No rounded CJK face ships with macOS. Chinese puts no spaces
    # between words, so word-wrapping would leave one unbreakable overflowing
    # line — hence wrap="char", which is safe here because every Han character
    # is an independent cluster.
    "zh-Hant": dict(font=FONT_HEITI, wrap="char"),
    "zh-Hans": dict(font=FONT_HEITI, wrap="char"),
    # Russian and Vietnamese: SF NS Rounded (the system rounded face, hidden
    # behind a dot-prefixed family name but loadable by path) is the only
    # rounded font on this machine covering both Cyrillic and the precomposed
    # Vietnamese vowels, so it keeps these two locales visually on-brand
    # instead of dropping them onto a plain grotesque.
    "ru": dict(font=FONT_SF_ROUNDED, weight="Bold"),
    "vi": dict(font=FONT_SF_ROUNDED, weight="Bold"),
    # Thai: Sukhumvit Set Bold (face 5), soft and geometric enough to sit next
    # to the rounded faces. Chosen over Thonburi — the older macOS Thai system
    # face — for a mechanical reason, not a stylistic one: Thonburi's combining
    # vowels and tone marks each carry a *non-zero* advance width (1300/2560 em)
    # and their outlines include the dotted-circle placeholder, because Thonburi
    # expects Apple's AAT shaper to substitute a zero-width variant. Pillow here
    # is built without libraqm, so it does no shaping at all and renders Thonburi
    # Thai as a row of dotted circles. Sukhumvit Set's marks are genuinely
    # zero-advance and sit at their final height with no shaping, so unshaped
    # Pillow output is correct.
    "th": dict(font=FONT_SUKHUMVIT, index=5),
    # Japanese: Hiragino Maru Gothic ProN W4 (face 1 — face 0 is the older
    # non-ProN variant with a smaller kanji set). The *only* rounded Japanese
    # face on macOS.
    #
    # This is a marketing headline, and it deliberately no longer matches the
    # app: Theme.jp moved to Hiragino Mincho ProN (the design's face), while a
    # store headline at 116px wants weight the mincho's thin horizontals don't
    # give. Maru Gothic ships in W4 only, with no bold, and at this size its
    # strokes read as heavy as Heiti Medium does for Chinese. Revisit together
    # with a screenshot re-render, never on its own — screenshots/ is generated.
    # No shaping needed: kana and kanji are all independent single-glyph
    # clusters, so unshaped Pillow output is correct. wrap="char" for the same
    # reason as Chinese — Japanese has no word spaces.
    "ja": dict(font=FONT_HIRA_MARU, index=1, wrap="char"),
    # Korean: Apple SD Gothic Neo Bold (face 6 — the odd indices are the hidden
    # ".Apple SD Gothic NeoI" interface variants, not what we want). No rounded
    # Korean face ships with macOS, so this is the same compromise Chinese makes
    # with Heiti. Korean needs no shaping either: modern Hangul is written in
    # precomposed syllable blocks (U+AC00..U+D7A3), one codepoint and one glyph
    # per syllable, so no jamo composition happens at render time. wrap="word"
    # because Korean *does* put spaces between words, unlike Chinese/Japanese.
    "ko": dict(font=FONT_APPLE_SD_GOTHIC, index=6),
}


def typography(locale):
    return {**DEFAULT_TYPOGRAPHY, **LOCALE_TYPOGRAPHY.get(locale, {})}


def load_font(typo, size):
    font = ImageFont.truetype(typo["font"], size, index=typo["index"])
    if typo["weight"]:
        # Variable font: select a named instance from its fvar table.
        font.set_variation_by_name(typo["weight"])
    return font


def ensure_frame(filename: str) -> str:
    path = os.path.join(FRAMES_DIR, filename)
    if os.path.exists(path):
        return path
    os.makedirs(FRAMES_DIR, exist_ok=True)
    url = f"{FRAMES_CDN}/{urllib.parse.quote(filename)}"
    print(f"downloading missing frame asset from {url}")
    urllib.request.urlretrieve(url, path)
    return path


def make_gradient(w, h, top, bottom):
    top_a = Image.new("RGB", (w, h), top)
    bot_a = Image.new("RGB", (w, h), bottom)
    mask = Image.new("L", (1, h))
    for y in range(h):
        mask.putpixel((0, y), int(255 * (y / (h - 1)) ** 0.85))
    mask = mask.resize((w, h))
    return Image.composite(bot_a, top_a, mask)


def wrap_lines(draw, text, font, max_width, wrap="word"):
    """Greedy wrap of `text` to `max_width`, breaking at spaces or characters.

    wrap="char" breaks between any two characters. That's correct for Chinese
    (no spaces between words, every Han character its own cluster) and *wrong*
    for Thai, which also has no word spaces but does have multi-codepoint
    clusters: splitting a consonant from its combining vowel or tone mark leaves
    a visibly broken glyph and a stray floating mark. So Thai uses wrap="word",
    which breaks only at the spaces Thai puts between phrases, never mid-cluster
    — and the Thai copy in LOCALES is written short enough that it almost never
    needs to wrap at all. `--check` is what makes that claim safe: it measures
    every wrapped line of every locale against max_width on every device, so a
    Thai line that no longer fits fails the check instead of silently running
    off the canvas.
    """
    units = list(text) if wrap == "char" else text.split(" ")
    sep = "" if wrap == "char" else " "
    lines, cur = [], ""
    for u in units:
        trial = (cur + sep + u).strip() if sep else (cur + u)
        if draw.textlength(trial, font=font) <= max_width or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = u
    if cur:
        lines.append(cur)
    return lines


def draw_centered_text(draw, cx, top_y, text, font, fill, max_width, line_gap=1.08, wrap="word"):
    lines = wrap_lines(draw, text, font, max_width, wrap)

    ascent, descent = font.getmetrics()
    line_h = int((ascent + descent) * line_gap)
    y = top_y
    for ln in lines:
        w = draw.textlength(ln, font=font)
        draw.text((cx - w / 2, y), ln, font=font, fill=fill)
        y += line_h
    return y  # bottom y after last line


def compose_device(raw_shot: Image.Image, frame_path: str, off_x, off_y, off_w) -> Image.Image:
    frame = Image.open(frame_path).convert("RGBA")
    scale = off_w / raw_shot.width
    shot_w = off_w
    shot_h = round(raw_shot.height * scale)
    shot_resized = raw_shot.convert("RGBA").resize((shot_w, shot_h), Image.LANCZOS)

    # Round the screenshot's corners so its square corners don't peek out past
    # the frame's rounded screen cutout (plain screenshots are rectangles;
    # the physical display has rounded corners).
    radius = round(shot_w * 0.10)
    mask = Image.new("L", (shot_w, shot_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot_w - 1, shot_h - 1], radius=radius, fill=255)
    shot_resized.putalpha(mask)

    canvas = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    canvas.paste(shot_resized, (off_x, off_y), shot_resized)
    canvas.alpha_composite(frame)
    return canvas


def process(locale, key, dev_key, dev):
    # Resolved per call, so `--app` reaches it — see the note in DEVICES.
    if dev.get("raw_dir"):
        base = os.path.join(os.path.dirname(RAW_DIR), dev["raw_dir"])
    else:
        base = IPAD_RAW_DIR if dev.get("ipad") else RAW_DIR
    raw_path = os.path.join(base, f"{key}.png")
    if not os.path.exists(raw_path):
        return None
    raw = Image.open(raw_path)

    W, H = dev["canvas"]
    if dev.get("frame"):
        device_img = compose_device(raw, ensure_frame(dev["frame"]),
                                    *dev["off"], dev["off_w"])
    else:
        # Frameless: no frameit asset exists for the watch, and a bezel drawn at this
        # size would swallow the screen. Just round the corners, as the physical
        # display does, and let the gradient behind it read as the device edge.
        shot = raw.convert("RGBA")
        radius = round(shot.width * 0.22)      # the watch is far rounder than a phone
        mask = Image.new("L", shot.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, shot.width - 1, shot.height - 1],
                                               radius=radius, fill=255)
        shot.putalpha(mask)
        device_img = shot

    bg = make_gradient(W, H, *GRADIENTS[APP]).convert("RGBA")
    draw = ImageDraw.Draw(bg)

    title, subtitle = LOCALES[LOCALE_ALIASES.get(locale, locale)][key]
    typo = typography(locale)
    title_font = load_font(typo, round(W * 0.088))
    sub_font = load_font(typo, round(W * 0.045))

    wrap_mode = typo["wrap"]
    top_y = round(H * 0.065)
    max_text_w = W * 0.88
    bottom_of_title = draw_centered_text(draw, W / 2, top_y, title, title_font,
                                          (255, 255, 255, 255), max_text_w, line_gap=1.05, wrap=wrap_mode)
    sub_top = bottom_of_title + round(H * 0.012)
    bottom_of_sub = draw_centered_text(draw, W / 2, sub_top, subtitle, sub_font,
                                        (255, 255, 255, 220), max_text_w, line_gap=1.1, wrap=wrap_mode)

    # Scale the composed device to fill most of the canvas width; let it
    # bleed off the bottom edge (matches the reference marketing-screenshot
    # style rather than shrinking to show the whole device).
    frame_target_w = round(W * 0.94)
    scale2 = frame_target_w / device_img.width
    frame_target_h = round(device_img.height * scale2)
    device_scaled = device_img.resize((frame_target_w, frame_target_h), Image.LANCZOS)

    device_top_y = bottom_of_sub + round(H * 0.035)
    device_left_x = round((W - frame_target_w) / 2)
    bg.alpha_composite(device_scaled, (device_left_x, device_top_y))

    # Written straight to its final upload name. deliver picks the device bucket
    # from each PNG's pixel size, not its filename, but names must be unique
    # within a locale — hence the `-<dev_key>` suffix.
    out_dir = os.path.join(OUT_DIR, locale)
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"{key}-{dev_key}.png")
    bg.convert("RGB").save(out_path, "PNG")
    return out_path


def missing_glyphs(font, text):
    """The characters of `text` the font has no glyph for.

    A codepoint the font doesn't cover is not an error in Pillow — it silently
    renders the font's .notdef glyph, which is a tofu box (□) in some faces and
    blank in others. A whole App Store screenshot set of tofu is exactly the
    failure this guards against, so coverage gets asserted rather than eyeballed.

    Pillow exposes no cmap API, so this rasterises each character onto its own
    scratch canvas and compares the pixels against U+FFFF rendered the same way.
    U+FFFF is a permanently unassigned noncharacter, so it *always* resolves to
    .notdef; a pixel-identical match means the character resolved to .notdef too,
    i.e. the font lacks it. Cross-checked against the real `cmap` tables with
    fontTools while picking the fonts above — identical answers — and this way
    the script keeps Pillow as its only dependency. Whitespace is skipped: a
    space is legitimately blank and would otherwise match a blank .notdef.
    """
    box = round(font.size * 3)

    def bitmap(ch):
        img = Image.new("L", (box, box), 0)
        ImageDraw.Draw(img).text((font.size, font.size), ch, font=font, fill=255)
        return img.tobytes()

    notdef = bitmap("￿")
    return [ch for ch in dict.fromkeys(text)
            if not ch.isspace() and bitmap(ch) == notdef]


def check(locale_filter=None):
    """Audit LOCALES against LOCALE_TYPOGRAPHY. Returns True if everything passes.

    Two failure modes, both invisible at render time:
      1. a character with no glyph in the locale's font -> tofu/blank
      2. a wrapped line wider than the text column -> text runs off the canvas
    Both are checked at the real font sizes for every device, since the font size
    is a fraction of canvas width and each device rounds it differently.
    """
    probe = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    locales = {**LOCALES, **{a: LOCALES[s] for a, s in LOCALE_ALIASES.items()}}
    ok = True
    for locale, copy in sorted(locales.items()):
        if locale_filter and locale != locale_filter:
            continue
        typo = typography(locale)
        face = os.path.basename(typo["font"])
        print(f"\n{locale}: {face} index={typo['index']} "
              f"weight={typo['weight'] or 'static'} wrap={typo['wrap']}")
        for dev_key, dev in DEVICES.items():
            W = dev["canvas"][0]
            max_text_w = W * 0.88
            fonts = dict(title=load_font(typo, round(W * 0.088)),
                         sub=load_font(typo, round(W * 0.045)))
            worst, dev_ok, lines_total = 0.0, True, 0
            for key, (title, subtitle) in copy.items():
                for role, text in (("title", title), ("sub", subtitle)):
                    font = fonts[role]
                    gaps = missing_glyphs(font, text)
                    if gaps:
                        ok = dev_ok = False
                        print(f"  FAIL {dev_key} {key} {role}: no glyph for "
                              f"{' '.join(f'{c!r} U+{ord(c):04X}' for c in gaps)}")
                    for line in wrap_lines(probe, text, font, max_text_w, typo["wrap"]):
                        lines_total += 1
                        w = probe.textlength(line, font=font)
                        worst = max(worst, w / max_text_w)
                        if w > max_text_w:
                            ok = dev_ok = False
                            print(f"  FAIL {dev_key} {key} {role}: line {w:.0f}px "
                                  f"> {max_text_w:.0f}px column: {line!r}")
            verdict = "ok" if dev_ok else "PROBLEMS ABOVE"
            print(f"  {dev_key}: {W}px canvas, 20 strings / {lines_total} rendered lines, "
                  f"widest {worst:.0%} of the {max_text_w:.0f}px text column - {verdict}")
    print("\ncheck: PASS" if ok else "\ncheck: FAIL")
    return ok


if __name__ == "__main__":
    # Usage: generate_framed_screenshots.py [locale-or-key-substring-filter]
    # e.g. "de-DE" renders only German, "01-today" renders that screenshot
    # for every locale, "de-DE:01-today" combines both filters.
    # `--check [locale]` audits fonts/copy and renders nothing.
    argv = sys.argv[1:]
    # `--app <name>` selects which app is being framed. Consumed before anything
    # else so the filter argument keeps its existing meaning.
    if "--app" in argv:
        i = argv.index("--app")
        APP = argv[i + 1]
        if APP not in APP_LOCALES:
            sys.exit(f"unknown app {APP!r} — expected one of: {', '.join(APP_LOCALES)}")
        del argv[i:i + 2]
        RAW_DIR, IPAD_RAW_DIR, OUT_DIR = app_paths(APP)
        LOCALES = APP_LOCALES[APP]

    if "--check" in argv:
        rest = [a for a in argv if a != "--check"]
        sys.exit(0 if check(rest[0] if rest else None) else 1)

    arg = argv[0] if argv else None
    locale_filter, key_filter = (None, None)
    if arg:
        if ":" in arg:
            locale_filter, key_filter = arg.split(":", 1)
        elif arg in LOCALES or arg in LOCALE_ALIASES:
            locale_filter = arg
        else:
            key_filter = arg

    # Aliased locales render the same copy as the locale they point at.
    targets = {**LOCALES, **{alias: LOCALES[src] for alias, src in LOCALE_ALIASES.items()}}

    for locale, copy in targets.items():
        if locale_filter and locale != locale_filter:
            continue


        for key in copy:
            if key_filter and key_filter not in key:
                continue
            for dev_key, dev in DEVICES.items():
                out = process(locale, key, dev_key, dev)
                # None = no raw capture for this key on this device (e.g. only a
                # couple of screens were ever captured on the iPad simulator).
                print("wrote", out) if out else print(f"skip  {locale}/{dev_key}/{key} (no raw capture)")
