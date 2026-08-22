#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build the Bonsai JLPT marketing site → web-jlpt/ (https://jlpt-jp.web.app/).

Completely separate from scripts/build-web.py, which builds the Japanese Daily
site into web/. The separation is deliberate and load-bearing: App Review
rejected the JLPT app under 4.3(a) as a duplicate of Japanese Daily, so the two
products — and their sites — must not look alike. This page is dark charcoal
with the app's amber→orange identity, structured around the N5→N1 level ladder;
the minna site is teal-on-light with a screenshot hero and a feature grid.
Nothing here may be copied from there.

Every number on the page (lesson counts, word counts, level ranges, language
counts) is read from Apps/jlpt/Resources/JLPTData.json and nihongo/UIStrings.json
at build time — never hardcoded, so the page cannot drift from the app.

Usage:  python3 scripts/build-web-jlpt.py          # builds everything (default)
        python3 scripts/build-web-jlpt.py --all    # same thing, for muscle memory

Outputs: web-jlpt/index.html (en) plus zh-Hans/, zh-Hant/, vi/ subfolders,
web-jlpt/sitemap.xml and web-jlpt/robots.txt. Never touches web-jlpt/privacy.html,
web-jlpt/terms.html or web-jlpt/img/ — those are hand-maintained.
"""

import html
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "web-jlpt"

BASE_URL = "https://jlpt-jp.web.app"
APP_STORE = "https://apps.apple.com/app/id6800220716"   # Course.jlpt.appStoreURL
STORE_LINK = APP_STORE + "?ct=web_jlpt"                 # campaign token for the site
SIBLING_URL = "https://japanesedaily.wahthefox.com/"    # our own beginner app

# ---------------------------------------------------------------------------
# Locales — the four the app's store listing carries (fastlane/jlpt/metadata/).
# `app_lang` is the key used inside JLPTData.json / UIStrings.json.
# ---------------------------------------------------------------------------

LOCALES = {
    "en":      dict(path="",         html_lang="en",      app_lang="en",
                    og="en_US", native="English"),
    "zh-Hans": dict(path="zh-Hans/", html_lang="zh-Hans", app_lang="zh",
                    og="zh_CN", native="简体中文"),
    "zh-Hant": dict(path="zh-Hant/", html_lang="zh-Hant", app_lang="zh-Hant",
                    og="zh_TW", native="繁體中文"),
    "vi":      dict(path="vi/",      html_lang="vi",      app_lang="vi",
                    og="vi_VN", native="Tiếng Việt"),
}

# Three real words per level, chosen for the difficulty arc they draw when read
# top to bottom (I/friend/school → exam/dream/future → … → concept/reason/measure).
# Looked up in the dataset at build time; a missing word fails the build loudly.
SAMPLES = {
    "N5": [(1, "watashi"), (7, "tomodachi"), (17, "gakkou")],
    "N4": [(21, "shiken"), (22, "yume"), (27, "shourai")],
    "N3": [(60, "mokuteki"), (69, "kaiketsu"), (57, "kankyou")],
    "N2": [(102, "kakuritsu"), (94, "shuyaku"), (100, "seisaku")],
    "N1": [(150, "gainen"), (177, "risei"), (170, "sochi")],
}


def esc(s):
    return html.escape(s, quote=True)


# ---------------------------------------------------------------------------
# Data — everything numeric comes from the app's own bundled files.
# ---------------------------------------------------------------------------

def load_course():
    data = json.load(open(ROOT / "Apps" / "jlpt" / "Resources" / "JLPTData.json",
                          encoding="utf-8"))
    assert data["languages"] == ["en", "zh", "zh-Hant", "vi"], data["languages"]

    lessons = {l["number"]: l for l in data["lessons"]}
    tr = data["translations"]

    levels = []
    total_words = 0
    prev_last = 0
    for lv in data["levels"]:
        assert lv["first"] == prev_last + 1, f"level gap before {lv['level']}"
        prev_last = lv["last"]
        words = sum(len(lessons[n]["entries"])
                    for n in range(lv["first"], lv["last"] + 1))
        total_words += words
        samples = []
        for lesson_no, romaji in SAMPLES[lv["level"]]:
            assert lv["first"] <= lesson_no <= lv["last"], (lv["level"], romaji)
            hits = [e for e in lessons[lesson_no]["entries"] if e["romaji"] == romaji]
            assert len(hits) == 1, f"{romaji} in lesson {lesson_no}: {len(hits)} hits"
            e = hits[0]
            meanings = {}
            for lang in data["languages"]:
                m = tr[lang][str(lesson_no)][e["key"]]
                meanings[lang] = m
            samples.append(dict(kanji=e["kanji"], kana=e["kana"],
                                romaji=romaji, meanings=meanings))
        levels.append(dict(level=lv["level"], first=lv["first"], last=lv["last"],
                           lessons=lv["last"] - lv["first"] + 1,
                           words=words, samples=samples))

    total_lessons = prev_last
    for lv in levels:
        lv["pct"] = round(lv["words"] * 100 / total_words)
    return levels, total_lessons, total_words


def count_ui_languages():
    ui = json.load(open(ROOT / "nihongo" / "UIStrings.json", encoding="utf-8"))
    return len(ui), ui


LEVELS, N_LESSONS, N_WORDS = load_course()
N_UI_LANGS, UI = count_ui_languages()

# The app's own labels for the five modes and a few shared strings, so the site
# and the app agree word for word in every language.
MODES = [
    ("Vocab List", "Browse & hear all words"),
    ("Flashcards", "Swipe right if you know it"),
    ("Train", "Swipe to the right answer"),
    ("Match", "Pair each word with its meaning"),
    ("Learn", "Rebuild the reading from tiles"),
]


def app_string(app_lang, key):
    return UI.get(app_lang, {}).get(key) or UI["en"][key]


def fmt(loc, n):
    """Locale-formatted integer: 7,972 (en/zh) — 7.972 (vi)."""
    s = f"{n:,}"
    return s.replace(",", ".") if loc == "vi" else s


def short_meaning(m):
    m = m.split(";")[0].strip()
    if len(m) > 30:
        m = m.split(",")[0].strip()
    return m


# ---------------------------------------------------------------------------
# Copy — one dict per locale, identical key sets (asserted below). Numbers are
# interpolated, never written into the strings.
# ---------------------------------------------------------------------------

S = {
    "en": dict(
        title="Bonsai JLPT — JLPT vocabulary from N5 to N1",
        meta_desc="All five JLPT levels in one app: {words} words across {lessons} "
                  "short lessons, N5 to N1. Five study modes, scored challenges, "
                  "every word spoken — offline, no account.",
        kicker="one word at a time, to the summit",
        h1_pre="The whole JLPT vocabulary, ",
        h1_grad="N5 to N1",
        lede="You’ve decided to sit the test. Bonsai lays out the vocabulary of all "
             "five levels in teaching order — so the distance to N1 is something you "
             "can see, and shrink a little every day.",
        nav_cta="Get the app",
        cta="Download on the App Store",
        cta_note="Free to start · iPhone & iPad · works offline",
        stat_lessons="short lessons",
        stat_words="words",
        stat_levels="levels, N5 → N1",
        stat_langs="interface languages",
        ladder_h2="One climb, five camps",
        ladder_sub="Pick your level and the lesson list follows it. Each level below "
                   "shows its true share of the climb — and a first taste of its words.",
        lesson_range="Lessons {a}–{b}",
        words_n="{n} words",
        pct_label="{pct}% of the climb",
        level_N5="Greetings, numbers, the words of daily life — where everyone starts.",
        level_N4="School, work, the neighbourhood — and the words that glue "
                 "sentences together.",
        level_N3="The long middle: the vocabulary that turns phrases into conversation.",
        level_N2="Newspapers, meetings, opinions — Japanese the way adults actually "
                 "use it.",
        level_N1="Government, law, nuance. The summit — {n1} words wide.",
        modes_h2="Five ways into every lesson",
        modes_sub="A word rarely sticks the first time. Every lesson can be worked "
                  "five ways, shallow to deep — and then the scoring starts.",
        challenge_h3="Then sit the test in miniature",
        challenge_body="Every lesson ends in a ladder of challenges: ten questions a "
                       "rung, 80% to pass, three stars for a perfect run. The rungs "
                       "harden as you climb — first you recognise the word, then you "
                       "recall it, and near the top you only hear it, spoken aloud "
                       "with nothing on screen. Pass a rung and the next one opens.",
        earn="Sweep the opening lessons — three stars on every challenge — and the "
             "whole of N5 unlocks for good, free.",
        facts_h2="The fine print, up front",
        fact1_t="Works offline",
        fact1_b="Every lesson, every word and every audio clip ships inside the app. "
                "Planes and subways welcome.",
        fact2_t="Every word, spoken",
        fact2_b="All {words} words — and every kana — carry their own audio clip in "
                "a clear synthesised voice.",
        fact3_t="No account",
        fact3_b="Nothing to sign up for and nothing to remember. Progress syncs "
                "privately between your devices through iCloud.",
        fact4_t="Kana included, free",
        fact4_b="A complete hiragana and katakana section with five drills of its "
                "own — free for everyone, no unlock needed.",
        fact5_t="Meanings in your language",
        fact5_b="Word meanings in English, Simplified Chinese, Traditional Chinese "
                "and Vietnamese; the interface speaks {langs} languages — and you "
                "choose the two separately.",
        fact6_t="Premium, sized to your test date",
        fact6_b="Start free and see how it fits. Premium opens all {lessons} lessons "
                "— subscribe for 1, 3 or 6 months, or pay once and it’s yours forever.",
        chapter_h2="The next chapter",
        chapter_body="Bonsai JLPT comes from the maker of Japanese Daily — the teal "
                     "app where many people meet their first Japanese words. That one "
                     "gets beginners started; this one is built for the long climb, "
                     "from your first N5 word to your last N1 lesson.",
        chapter_link="Meet Japanese Daily",
        get_h2="The test has a date. Start climbing today.",
        langs_label="Languages",
        disclaimer="Bonsai JLPT is an independent study app. The JLPT is administered "
                   "by the Japan Foundation and JEES; this app is not affiliated with "
                   "or endorsed by them. All audio is synthesised.",
        og_alt="The Bonsai JLPT app icon beside the words: JLPT vocabulary, N5 to N1 "
               "— {lessons} lessons, {words} words.",
    ),
    "zh-Hans": dict(
        title="Bonsai JLPT — JLPT 词汇，从 N5 到 N1",
        meta_desc="五个 JLPT 级别尽在一款应用：{lessons} 个短课程、{words} 个单词，"
                  "从 N5 到 N1。五种练习模式加计分挑战，每个单词都有发音——离线可用，"
                  "无需注册。",
        kicker="一词一词，直到顶峰",
        h1_pre="JLPT 词汇全收录，",
        h1_grad="从 N5 到 N1",
        lede="你已决定报考 JLPT。Bonsai 把五个级别的词汇按教学顺序铺开——到 N1 的距离"
             "一目了然，每天都能缩短一点。",
        nav_cta="获取应用",
        cta="在 App Store 下载",
        cta_note="免费开始 · iPhone 和 iPad · 离线可用",
        stat_lessons="个短课程",
        stat_words="个单词",
        stat_levels="个级别，N5 → N1",
        stat_langs="种界面语言",
        ladder_h2="一次攀登，五个营地",
        ladder_sub="选好级别，课程列表就跟着走。下面每一级都标出它在整段攀登中的真实"
                   "占比——再配几个单词先尝尝。",
        lesson_range="第 {a}–{b} 课",
        words_n="{n} 个单词",
        pct_label="占整段攀登的 {pct}%",
        level_N5="问候、数字、日常生活的词——每个人的起点。",
        level_N4="学校、工作、街坊——还有把句子粘起来的那些词。",
        level_N3="漫长的中段：让短语变成对话的词汇。",
        level_N2="报纸、会议、观点——成年人真正在用的日语。",
        level_N1="政府、法律、微妙的语感。顶峰——宽 {n1} 个单词。",
        modes_h2="进入每一课的五种方式",
        modes_sub="一个单词很少一次就记住。每一课都能由浅入深练上五遍——然后才开始计分。",
        challenge_h3="然后，把考试缩小来考",
        challenge_body="每一课的终点是一串挑战：每级十题，80% 及格，全对得三星。越往上"
                       "越难——先是认出单词，再是回想起它，接近顶端时只能靠听，屏幕上"
                       "什么都没有。过一级，开一级。",
        earn="把开头几课的所有挑战都拿满三星，整个 N5 级别就永久免费解锁。",
        facts_h2="细节，先说清楚",
        fact1_t="离线可用",
        fact1_b="每一课、每个单词、每段音频都内置在应用里。飞机上、地铁里照样学。",
        fact2_t="每个单词都有发音",
        fact2_b="全部 {words} 个单词和每个假名都配有清晰的合成语音。",
        fact3_t="无需账号",
        fact3_b="不用注册，也没有密码要记。学习进度通过 iCloud 在你的设备间私密同步。",
        fact4_t="假名完全免费",
        fact4_b="完整的平假名、片假名板块，自带五种练习——对所有人免费，无需解锁。",
        fact5_t="释义用你的语言",
        fact5_b="单词释义提供英语、简体中文、繁体中文和越南语；界面支持 {langs} 种语言"
                "——两者可分开选择。",
        fact6_t="Premium 按考期来订",
        fact6_b="先免费用起来。Premium 解锁全部 {lessons} 课——按 1、3 或 6 个月订阅，"
                "或一次买断，永久拥有。",
        chapter_h2="下一章",
        chapter_body="Bonsai JLPT 出自 Japanese Daily 的开发者之手——那款青色的应用，"
                     "许多人在那里认识了自己的第一个日语单词。那一款带你入门；这一款"
                     "为漫长的攀登而生——从第一个 N5 单词，到最后一课 N1。",
        chapter_link="认识 Japanese Daily",
        get_h2="考试已有日期。今天就开始攀登。",
        langs_label="语言",
        disclaimer="Bonsai JLPT 是独立开发的学习应用。JLPT 由日本国际交流基金会与日本"
                   "国际教育支援协会（JEES）主办，本应用与其无关，亦未获其认可。所有"
                   "音频均为合成语音。",
        og_alt="Bonsai JLPT 应用图标，旁边写着：JLPT 词汇，从 N5 到 N1——{lessons} 课、"
               "{words} 个单词。",
    ),
    "zh-Hant": dict(
        title="Bonsai JLPT — JLPT 單字，從 N5 到 N1",
        meta_desc="五個 JLPT 級別盡在一款應用程式：{lessons} 個短課程、{words} 個單字，"
                  "從 N5 到 N1。五種練習模式加計分挑戰，每個單字都有發音——離線可用，"
                  "無需註冊。",
        kicker="一字一字，直到頂峰",
        h1_pre="JLPT 單字全收錄，",
        h1_grad="從 N5 到 N1",
        lede="你已決定報考 JLPT。Bonsai 把五個級別的單字按教學順序鋪開——到 N1 的距離"
             "一目了然，每天都能縮短一點。",
        nav_cta="取得 App",
        cta="在 App Store 下載",
        cta_note="免費開始 · iPhone 與 iPad · 離線可用",
        stat_lessons="個短課程",
        stat_words="個單字",
        stat_levels="個級別，N5 → N1",
        stat_langs="種介面語言",
        ladder_h2="一次攀登，五個營地",
        ladder_sub="選好級別，課程列表就跟著走。下面每一級都標出它在整段攀登中的真實"
                   "占比——再配幾個單字先嚐嚐。",
        lesson_range="第 {a}–{b} 課",
        words_n="{n} 個單字",
        pct_label="佔整段攀登的 {pct}%",
        level_N5="問候、數字、日常生活的詞——每個人的起點。",
        level_N4="學校、工作、街坊——還有把句子黏起來的那些詞。",
        level_N3="漫長的中段：讓片語變成對話的詞彙。",
        level_N2="報紙、會議、觀點——成年人真正在用的日語。",
        level_N1="政府、法律、微妙的語感。頂峰——寬 {n1} 個單字。",
        modes_h2="進入每一課的五種方式",
        modes_sub="一個單字很少一次就記住。每一課都能由淺入深練上五遍——然後才開始計分。",
        challenge_h3="然後，把考試縮小來考",
        challenge_body="每一課的終點是一串挑戰：每級十題，80% 及格，全對得三星。越往上"
                       "越難——先是認出單字，再是回想起它，接近頂端時只能靠聽，螢幕上"
                       "什麼都沒有。過一級，開一級。",
        earn="把開頭幾課的所有挑戰都拿滿三星，整個 N5 級別就永久免費解鎖。",
        facts_h2="細節，先說清楚",
        fact1_t="離線可用",
        fact1_b="每一課、每個單字、每段音訊都內建在應用程式裡。飛機上、捷運裡照樣學。",
        fact2_t="每個單字都有發音",
        fact2_b="全部 {words} 個單字和每個假名都配有清晰的合成語音。",
        fact3_t="無需帳號",
        fact3_b="不用註冊，也沒有密碼要記。學習進度透過 iCloud 在你的裝置間私密同步。",
        fact4_t="假名完全免費",
        fact4_b="完整的平假名、片假名單元，內建五種練習——對所有人免費，無需解鎖。",
        fact5_t="釋義用你的語言",
        fact5_b="單字釋義提供英語、簡體中文、繁體中文和越南語；介面支援 {langs} 種語言"
                "——兩者可分開選擇。",
        fact6_t="Premium 按考期來訂",
        fact6_b="先免費用起來。Premium 解鎖全部 {lessons} 課——按 1、3 或 6 個月訂閱，"
                "或一次買斷，永久擁有。",
        chapter_h2="下一章",
        chapter_body="Bonsai JLPT 出自 Japanese Daily 的開發者之手——那款青色的應用"
                     "程式，許多人在那裡認識了自己的第一個日語單字。那一款帶你入門；"
                     "這一款為漫長的攀登而生——從第一個 N5 單字，到最後一課 N1。",
        chapter_link="認識 Japanese Daily",
        get_h2="考試已有日期。今天就開始攀登。",
        langs_label="語言",
        disclaimer="Bonsai JLPT 是獨立開發的學習應用程式。JLPT 由日本國際交流基金會與"
                   "日本國際教育支援協會（JEES）主辦，本應用程式與其無關，亦未獲其"
                   "認可。所有音訊均為合成語音。",
        og_alt="Bonsai JLPT 應用程式圖標，旁邊寫著：JLPT 單字，從 N5 到 N1——{lessons} "
               "課、{words} 個單字。",
    ),
    "vi": dict(
        title="Bonsai JLPT — Từ vựng JLPT từ N5 đến N1",
        meta_desc="Cả năm cấp độ JLPT trong một ứng dụng: {words} từ trong {lessons} "
                  "bài học ngắn, từ N5 đến N1. Năm chế độ luyện tập cùng thử thách "
                  "tính điểm, từ nào cũng được đọc — ngoại tuyến, không cần tài khoản.",
        kicker="từng từ một, lên tới đỉnh",
        h1_pre="Trọn bộ từ vựng JLPT, ",
        h1_grad="từ N5 đến N1",
        lede="Bạn đã quyết định thi JLPT. Bonsai trải toàn bộ từ vựng của năm cấp độ "
             "theo thứ tự giảng dạy — để quãng đường đến N1 là thứ bạn nhìn thấy "
             "được, và rút ngắn một chút mỗi ngày.",
        nav_cta="Tải ứng dụng",
        cta="Tải trên App Store",
        cta_note="Miễn phí để bắt đầu · iPhone & iPad · dùng ngoại tuyến",
        stat_lessons="bài học ngắn",
        stat_words="từ vựng",
        stat_levels="cấp độ, N5 → N1",
        stat_langs="ngôn ngữ giao diện",
        ladder_h2="Một cuộc leo, năm trạm dừng",
        ladder_sub="Chọn cấp độ, danh sách bài học sẽ theo đó. Mỗi cấp độ dưới đây "
                   "cho thấy phần thực của nó trên cả chặng leo — cùng vài từ nếm thử.",
        lesson_range="Bài {a}–{b}",
        words_n="{n} từ",
        pct_label="{pct}% chặng leo",
        level_N5="Chào hỏi, con số, từ ngữ của đời sống hằng ngày — nơi ai cũng "
                 "bắt đầu.",
        level_N4="Trường học, công việc, khu phố — và những từ kết dính câu chữ.",
        level_N3="Chặng giữa dài: vốn từ biến các cụm từ thành cuộc trò chuyện.",
        level_N2="Báo chí, cuộc họp, quan điểm — tiếng Nhật đúng như người lớn "
                 "đang dùng.",
        level_N1="Chính phủ, luật pháp, sắc thái. Đỉnh núi — rộng {n1} từ.",
        modes_h2="Năm lối vào mỗi bài học",
        modes_sub="Một từ hiếm khi nhớ ngay lần đầu. Mỗi bài học có thể luyện theo "
                  "năm cách, từ nông đến sâu — rồi mới bắt đầu tính điểm.",
        challenge_h3="Rồi làm bài thi thu nhỏ",
        challenge_body="Mỗi bài học kết thúc bằng một thang thử thách: mười câu mỗi "
                       "nấc, 80% để qua, ba sao cho lượt làm hoàn hảo. Càng leo càng "
                       "khó — đầu tiên bạn nhận ra từ, rồi phải tự nhớ ra nó, và gần "
                       "đỉnh bạn chỉ được nghe, màn hình không hiện gì. Qua một nấc, "
                       "nấc kế tiếp mở ra.",
        earn="Đạt ba sao ở mọi thử thách của những bài mở đầu — cả cấp độ N5 mở khóa "
             "vĩnh viễn, miễn phí.",
        facts_h2="Mọi thứ rõ ràng từ đầu",
        fact1_t="Dùng ngoại tuyến",
        fact1_b="Mọi bài học, mọi từ và mọi đoạn âm thanh đều nằm sẵn trong ứng dụng. "
                "Trên máy bay hay tàu điện đều học được.",
        fact2_t="Từ nào cũng được đọc",
        fact2_b="Cả {words} từ — và mọi kana — đều có đoạn âm thanh riêng bằng giọng "
                "tổng hợp rõ ràng.",
        fact3_t="Không cần tài khoản",
        fact3_b="Không phải đăng ký, không phải nhớ mật khẩu. Tiến độ đồng bộ riêng "
                "tư giữa các thiết bị của bạn qua iCloud.",
        fact4_t="Kana miễn phí trọn vẹn",
        fact4_b="Trọn bộ hiragana và katakana với năm bài luyện riêng — miễn phí cho "
                "mọi người, không cần mở khóa.",
        fact5_t="Nghĩa theo ngôn ngữ của bạn",
        fact5_b="Nghĩa của từ có tiếng Anh, tiếng Trung giản thể, tiếng Trung phồn "
                "thể và tiếng Việt; giao diện nói {langs} ngôn ngữ — và bạn chọn hai "
                "thứ này riêng.",
        fact6_t="Premium theo ngày thi của bạn",
        fact6_b="Bắt đầu miễn phí để xem có hợp không. Premium mở toàn bộ {lessons} "
                "bài — đăng ký 1, 3 hoặc 6 tháng, hoặc trả một lần và giữ mãi mãi.",
        chapter_h2="Chương tiếp theo",
        chapter_body="Bonsai JLPT đến từ tác giả của Japanese Daily — ứng dụng màu "
                     "xanh ngọc nơi nhiều người gặp những từ tiếng Nhật đầu tiên của "
                     "mình. Ứng dụng ấy giúp người mới bắt đầu; ứng dụng này sinh ra "
                     "cho cuộc leo dài — từ từ N5 đầu tiên đến bài N1 cuối cùng.",
        chapter_link="Làm quen Japanese Daily",
        get_h2="Kỳ thi đã có ngày. Bắt đầu leo từ hôm nay.",
        langs_label="Ngôn ngữ",
        disclaimer="Bonsai JLPT là ứng dụng học tập độc lập. Kỳ thi JLPT do Japan "
                   "Foundation và JEES tổ chức; ứng dụng này không liên kết hay được "
                   "họ bảo trợ. Toàn bộ âm thanh là giọng tổng hợp.",
        og_alt="Biểu tượng ứng dụng Bonsai JLPT bên dòng chữ: từ vựng JLPT, N5 đến "
               "N1 — {lessons} bài, {words} từ.",
    ),
}

# Every locale must carry exactly the same keys — a hole would render as a
# KeyError at build time, never as a silently-English page.
_keysets = {loc: set(t) for loc, t in S.items()}
assert all(k == _keysets["en"] for k in _keysets.values()), {
    loc: k ^ _keysets["en"] for loc, k in _keysets.items() if k != _keysets["en"]}


# ---------------------------------------------------------------------------
# The page. Dark charcoal, amber→orange, a level ladder for a spine.
# ---------------------------------------------------------------------------

CSS = """
:root {
  --bg: #15161A;
  --panel: #1D1F25;
  --ink: #F4F1EA;
  --muted: #A5A199;
  --line: rgba(255, 255, 255, 0.09);
  --amber: #FFC24D;
  --orange: #FFA500;
  --grad: linear-gradient(120deg, #FFC24D 0%, #FFA500 55%, #FF8A00 100%);
  --teal: #31C3CF;
}
* { margin: 0; padding: 0; box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  background: var(--bg);
  color: var(--ink);
  font-family: system-ui, -apple-system, "Avenir Next", "Segoe UI Variable",
               "Segoe UI", Roboto, sans-serif;
  font-size: 17px;
  line-height: 1.65;
  -webkit-font-smoothing: antialiased;
}
[lang="ja"] {
  font-family: "Hiragino Mincho ProN", "Yu Mincho", "Noto Serif JP",
               "Hiragino Sans", serif;
}
img { max-width: 100%; }
a { color: var(--amber); }

.wrap { max-width: 1000px; margin: 0 auto; padding: 0 24px; }

/* --- top bar ------------------------------------------------------------ */
.top {
  position: sticky; top: 0; z-index: 10;
  background: rgba(21, 22, 26, 0.82);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border-bottom: 1px solid var(--line);
}
.top .wrap {
  display: flex; align-items: center; gap: 12px;
  padding-top: 10px; padding-bottom: 10px;
}
.brand {
  display: flex; align-items: center; gap: 10px;
  color: var(--ink); text-decoration: none; font-weight: 700;
  letter-spacing: 0.01em;
}
.brand img { width: 28px; height: 28px; border-radius: 7px; display: block; }
.top-cta {
  margin-left: auto;
  color: #1E1503; background: var(--grad);
  text-decoration: none; font-weight: 700; font-size: 0.88em;
  padding: 7px 16px; border-radius: 999px; white-space: nowrap;
}

/* --- masthead ------------------------------------------------------------ */
.mast { padding: clamp(56px, 10vw, 120px) 0 clamp(40px, 6vw, 72px); }
.kicker {
  color: var(--muted); font-size: 0.95em; letter-spacing: 0.02em;
  margin-bottom: 20px;
}
.kicker [lang="ja"] { color: var(--amber); font-size: 1.15em; }
.kicker .sep { margin: 0 10px; opacity: 0.5; }
h1 {
  font-size: clamp(2.3rem, 6.5vw, 4.1rem);
  line-height: 1.08; font-weight: 800; letter-spacing: -0.02em;
  max-width: 18ch;
}
.grad {
  background: var(--grad);
  -webkit-background-clip: text; background-clip: text;
  -webkit-text-fill-color: transparent; color: var(--orange);
}
.lede {
  color: var(--muted); font-size: clamp(1.05rem, 2vw, 1.25rem);
  max-width: 56ch; margin-top: 24px;
}
.cta-row {
  display: flex; align-items: center; gap: 18px; flex-wrap: wrap;
  margin-top: 36px;
}
.cta {
  display: inline-block; text-decoration: none;
  color: #1E1503; background: var(--grad);
  font-weight: 800; font-size: 1.02em;
  padding: 15px 30px; border-radius: 999px;
  box-shadow: 0 10px 34px rgba(255, 165, 0, 0.28);
}
.cta-note { color: var(--muted); font-size: 0.9em; }
.stats {
  display: flex; flex-wrap: wrap; gap: 16px 48px;
  margin-top: clamp(40px, 6vw, 64px);
  padding-top: 28px; border-top: 1px solid var(--line);
}
.stat strong {
  display: block; font-size: clamp(1.9rem, 4vw, 2.6rem); font-weight: 800;
  letter-spacing: -0.02em; font-variant-numeric: tabular-nums;
  background: var(--grad);
  -webkit-background-clip: text; background-clip: text;
  -webkit-text-fill-color: transparent; color: var(--orange);
}
.stat span { color: var(--muted); font-size: 0.9em; }

/* --- sections ------------------------------------------------------------ */
section { padding: clamp(48px, 8vw, 88px) 0; border-top: 1px solid var(--line); }
h2 {
  font-size: clamp(1.6rem, 3.6vw, 2.3rem); font-weight: 800;
  letter-spacing: -0.015em; line-height: 1.15;
}
.section-sub { color: var(--muted); max-width: 60ch; margin-top: 12px; }

/* --- the ladder ----------------------------------------------------------- */
.rungs { list-style: none; margin-top: 24px; }
.rung {
  display: grid; grid-template-columns: minmax(110px, 190px) 1fr;
  gap: 8px 32px; padding: clamp(28px, 4vw, 44px) 0;
  border-top: 1px solid var(--line);
}
.rung:first-child { border-top: none; }
.lvl {
  font-size: clamp(3rem, 8vw, 5rem); font-weight: 900; line-height: 1;
  letter-spacing: -0.03em;
  background: var(--grad);
  -webkit-background-clip: text; background-clip: text;
  -webkit-text-fill-color: transparent; color: var(--orange);
  align-self: start;
}
.rung-meta {
  color: var(--muted); font-size: 0.9em; letter-spacing: 0.01em;
  font-variant-numeric: tabular-nums;
}
.bar {
  height: 6px; border-radius: 99px; background: var(--panel);
  margin: 12px 0 14px; overflow: hidden;
}
.bar i { display: block; height: 100%; border-radius: 99px;
         background: var(--grad); width: var(--w); }
.rung-line { max-width: 58ch; }
.words { list-style: none; display: flex; flex-wrap: wrap; gap: 10px; margin-top: 18px; }
.words li {
  display: grid; gap: 1px;
  background: var(--panel); border: 1px solid var(--line);
  border-radius: 14px; padding: 12px 16px; min-width: 132px;
}
.wj { font-size: 1.45rem; line-height: 1.3; }
.wk { color: var(--muted); font-size: 0.82em; }
.wr { color: var(--muted); font-size: 0.74em; letter-spacing: 0.06em;
      text-transform: uppercase; }
.wm { color: var(--amber); font-size: 0.88em; margin-top: 5px; }

/* --- modes + the challenge ladder ----------------------------------------- */
.mode-row {
  list-style: none; counter-reset: mode;
  display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 14px; margin-top: 28px;
}
.mode {
  counter-increment: mode;
  background: var(--panel); border: 1px solid var(--line);
  border-radius: 16px; padding: 18px 18px 16px;
}
.mode::before {
  content: counter(mode);
  display: inline-grid; place-items: center;
  width: 26px; height: 26px; border-radius: 999px;
  border: 1.5px solid var(--orange); color: var(--amber);
  font-size: 0.8em; font-weight: 700; margin-bottom: 12px;
}
.mode h3 { font-size: 1.02em; font-weight: 700; }
.mode p { color: var(--muted); font-size: 0.86em; margin-top: 4px; }
.challenge {
  margin-top: 26px; border-left: 3px solid var(--orange);
  background: var(--panel); border-radius: 0 16px 16px 0;
  padding: clamp(20px, 3vw, 30px) clamp(20px, 3.4vw, 34px);
}
.challenge h3 { font-size: 1.25em; font-weight: 800; letter-spacing: -0.01em; }
.challenge p { color: var(--muted); margin-top: 10px; max-width: 68ch; }
.challenge .earn { color: var(--amber); }

/* --- facts ----------------------------------------------------------------- */
.fact-list {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(270px, 1fr));
  gap: 26px 40px; margin-top: 30px;
}
.fact { border-top: 1px solid var(--line); padding-top: 14px; }
.fact dt { color: var(--amber); font-weight: 700; }
.fact dd { color: var(--muted); font-size: 0.94em; margin-top: 5px; }

/* --- the sibling app, in its own colour ------------------------------------ */
.chapter-card {
  margin-top: 26px;
  background: rgba(49, 195, 207, 0.07);
  border: 1px solid rgba(49, 195, 207, 0.3);
  border-radius: 20px; padding: clamp(22px, 3.4vw, 34px);
}
.chapter-card p { color: var(--muted); max-width: 66ch; }
.chapter-card a {
  display: inline-block; margin-top: 16px;
  color: var(--teal); font-weight: 700; text-decoration: none;
  border-bottom: 1.5px solid rgba(49, 195, 207, 0.5);
}

/* --- closing CTA + footer --------------------------------------------------- */
.get { text-align: center; }
.get img {
  width: 84px; height: 84px; border-radius: 20px; margin-bottom: 26px;
  box-shadow: 0 14px 44px rgba(255, 165, 0, 0.22);
}
.get h2 { max-width: 22ch; margin: 0 auto; }
.get .cta { margin-top: 32px; }
.get .cta-note { display: block; margin-top: 18px; }

footer { border-top: 1px solid var(--line); padding: 40px 0 56px; }
footer nav { display: flex; flex-wrap: wrap; gap: 8px 22px; }
footer a { color: var(--muted); text-decoration: none; font-size: 0.9em; }
footer a:hover { color: var(--amber); }
footer a[aria-current="true"] { color: var(--amber); }
.legal { margin-top: 14px; }
.fine { color: var(--muted); font-size: 0.78em; margin-top: 22px; max-width: 72ch; }

/* --- reveal (JS adds .js; without it everything is simply visible) --------- */
@media (prefers-reduced-motion: no-preference) {
  .js .rung, .js .mode, .js .fact, .js .chapter-card {
    opacity: 0; transform: translateY(14px);
    transition: opacity 0.55s ease, transform 0.55s ease;
  }
  .js .rung .bar i { width: 0; transition: width 0.9s ease 0.25s; }
  .js .seen { opacity: 1; transform: none; }
  .js .seen .bar i { width: var(--w); }
}

@media (max-width: 620px) {
  .rung { grid-template-columns: 1fr; }
  .lvl { font-size: clamp(2.6rem, 13vw, 3.4rem); }
  .top-cta { font-size: 0.8em; }
}
"""

JS = """
(function () {
  if (!("IntersectionObserver" in window)) { return; }
  document.documentElement.classList.add("js");
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) {
        entry.target.classList.add("seen");
        io.unobserve(entry.target);
      }
    });
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.1 });
  var targets = document.querySelectorAll(".rung, .mode, .fact, .chapter-card");
  targets.forEach(function (el) { io.observe(el); });
})();
"""


def t(loc, key, **kw):
    """A locale's string, with the shared numbers pre-filled."""
    base = dict(words=fmt(loc, N_WORDS), lessons=str(N_LESSONS),
                langs=str(N_UI_LANGS),
                n1=fmt(loc, next(l["words"] for l in LEVELS if l["level"] == "N1")))
    base.update(kw)
    return S[loc][key].format(**base)


def head_html(loc):
    meta = LOCALES[loc]
    url = BASE_URL + "/" + meta["path"]
    title = t(loc, "title")
    desc = t(loc, "meta_desc")
    og_alt = t(loc, "og_alt")

    alternates = "\n".join(
        f'<link rel="alternate" hreflang="{code}" href="{BASE_URL}/{m["path"]}">'
        for code, m in LOCALES.items())
    og_alternates = "\n".join(
        f'<meta property="og:locale:alternate" content="{m["og"]}">'
        for code, m in LOCALES.items() if code != loc)

    ld = json.dumps({
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "name": "Bonsai JLPT",
        "operatingSystem": "iOS",
        "applicationCategory": "EducationalApplication",
        "description": desc,
        "inLanguage": meta["html_lang"],
        "image": f"{BASE_URL}/img/og-card.png",
        "url": url,
        "installUrl": APP_STORE,
        "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
    }, ensure_ascii=False, indent=2)

    return f"""<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{esc(title)}</title>
<meta name="description" content="{esc(desc)}">
<meta name="color-scheme" content="dark">
<meta name="theme-color" content="#15161A">
<link rel="icon" href="/img/favicon-32.png" sizes="32x32" type="image/png">
<link rel="icon" href="/img/icon-512.png" sizes="512x512" type="image/png">
<link rel="apple-touch-icon" href="/img/apple-touch-icon.png">
<link rel="canonical" href="{url}">
{alternates}
<link rel="alternate" hreflang="x-default" href="{BASE_URL}/">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Bonsai JLPT">
<meta property="og:title" content="{esc(title)}">
<meta property="og:description" content="{esc(desc)}">
<meta property="og:url" content="{url}">
<meta property="og:locale" content="{meta["og"]}">
{og_alternates}
<meta property="og:image" content="{BASE_URL}/img/og-card.png">
<meta property="og:image:type" content="image/png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="{esc(og_alt)}">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{esc(title)}">
<meta name="twitter:description" content="{esc(desc)}">
<meta name="twitter:image" content="{BASE_URL}/img/og-card.png">
<script type="application/ld+json">
{ld}
</script>
<style>{CSS}</style>"""


def rung_html(loc, lv):
    app_lang = LOCALES[loc]["app_lang"]
    meta_bits = " · ".join([
        t(loc, "lesson_range", a=lv["first"], b=lv["last"]),
        t(loc, "words_n", n=fmt(loc, lv["words"])),
        t(loc, "pct_label", pct=lv["pct"]),
    ])
    chips = "\n".join(
        f"""<li>
<span class="wj" lang="ja">{esc(w["kanji"])}</span>
<span class="wk" lang="ja">{esc(w["kana"])}</span>
<span class="wr">{esc(w["romaji"])}</span>
<span class="wm">{esc(short_meaning(w["meanings"][app_lang]))}</span>
</li>"""
        for w in lv["samples"])
    return f"""<li class="rung" style="--w:{lv["pct"]}%">
<div class="lvl" aria-hidden="true">{lv["level"]}</div>
<div class="rung-body">
<p class="rung-meta"><strong>{lv["level"]}</strong> · {esc(meta_bits)}</p>
<div class="bar" role="presentation"><i></i></div>
<p class="rung-line">{esc(t(loc, "level_" + lv["level"]))}</p>
<ul class="words">
{chips}
</ul>
</div>
</li>"""


def page_html(loc):
    meta = LOCALES[loc]
    app_lang = meta["app_lang"]
    root = "/" + meta["path"]

    stats = "\n".join(
        f'<div class="stat"><strong>{esc(v)}</strong><span>{esc(t(loc, k))}</span></div>'
        for v, k in [
            (str(N_LESSONS), "stat_lessons"),
            (fmt(loc, N_WORDS), "stat_words"),
            (str(len(LEVELS)), "stat_levels"),
            (str(N_UI_LANGS), "stat_langs"),
        ])

    rungs = "\n".join(rung_html(loc, lv) for lv in LEVELS)

    modes = "\n".join(
        f"""<li class="mode">
<h3>{esc(app_string(app_lang, name))}</h3>
<p>{esc(app_string(app_lang, sub))}</p>
</li>"""
        for name, sub in MODES)

    facts = "\n".join(
        f"""<div class="fact">
<dt>{esc(t(loc, f"fact{i}_t"))}</dt>
<dd>{esc(t(loc, f"fact{i}_b"))}</dd>
</div>"""
        for i in range(1, 7))

    lang_links = "\n".join(
        f'<a href="/{m["path"]}" hreflang="{code}" lang="{m["html_lang"]}"'
        f'{" aria-current=" + chr(34) + "true" + chr(34) if code == loc else ""}>'
        f'{esc(m["native"])}</a>'
        for code, m in LOCALES.items())

    privacy = app_string(app_lang, "Privacy Policy")
    terms = app_string(app_lang, "Terms of Use")

    return f"""<!DOCTYPE html>
<html lang="{meta["html_lang"]}">
<head>
{head_html(loc)}
</head>
<body>

<nav class="top" aria-label="Bonsai JLPT">
<div class="wrap">
<a class="brand" href="{root}"><img src="/img/icon-192.png" width="28" height="28" alt="">Bonsai JLPT</a>
<a class="top-cta" href="{STORE_LINK}">{esc(t(loc, "nav_cta"))}</a>
</div>
</nav>

<header class="mast">
<div class="wrap">
<p class="kicker"><span lang="ja">一語ずつ、頂上へ</span><span class="sep">—</span>{esc(t(loc, "kicker"))}</p>
<h1>{esc(t(loc, "h1_pre"))}<span class="grad">{esc(t(loc, "h1_grad"))}</span></h1>
<p class="lede">{esc(t(loc, "lede"))}</p>
<div class="cta-row">
<a class="cta" href="{STORE_LINK}">{esc(t(loc, "cta"))}</a>
<span class="cta-note">{esc(t(loc, "cta_note"))}</span>
</div>
<dl class="stats">
{stats}
</dl>
</div>
</header>

<main>
<section class="climb" id="climb" aria-label="{esc(t(loc, "ladder_h2"))}">
<div class="wrap">
<h2>{esc(t(loc, "ladder_h2"))}</h2>
<p class="section-sub">{esc(t(loc, "ladder_sub"))}</p>
<ol class="rungs">
{rungs}
</ol>
</div>
</section>

<section class="modes" id="modes" aria-label="{esc(t(loc, "modes_h2"))}">
<div class="wrap">
<h2>{esc(t(loc, "modes_h2"))}</h2>
<p class="section-sub">{esc(t(loc, "modes_sub"))}</p>
<ol class="mode-row">
{modes}
</ol>
<div class="challenge">
<h3>{esc(t(loc, "challenge_h3"))}</h3>
<p>{esc(t(loc, "challenge_body"))}</p>
<p class="earn">{esc(t(loc, "earn"))}</p>
</div>
</div>
</section>

<section class="facts" id="facts" aria-label="{esc(t(loc, "facts_h2"))}">
<div class="wrap">
<h2>{esc(t(loc, "facts_h2"))}</h2>
<dl class="fact-list">
{facts}
</dl>
</div>
</section>

<section class="chapter" id="chapter" aria-label="{esc(t(loc, "chapter_h2"))}">
<div class="wrap">
<h2>{esc(t(loc, "chapter_h2"))}</h2>
<div class="chapter-card">
<p>{esc(t(loc, "chapter_body"))}</p>
<a href="{SIBLING_URL}">{esc(t(loc, "chapter_link"))} →</a>
</div>
</div>
</section>

<section class="get" id="get" aria-label="{esc(t(loc, "cta"))}">
<div class="wrap">
<img src="/img/icon-192.png" width="84" height="84" alt="">
<h2>{esc(t(loc, "get_h2"))}</h2>
<a class="cta" href="{STORE_LINK}">{esc(t(loc, "cta"))}</a>
<span class="cta-note">{esc(t(loc, "cta_note"))}</span>
</div>
</section>
</main>

<footer>
<div class="wrap">
<nav aria-label="{esc(t(loc, "langs_label"))}">
{lang_links}
</nav>
<nav class="legal" aria-label="Legal">
<a href="/privacy.html">{esc(privacy)}</a>
<a href="/terms.html">{esc(terms)}</a>
</nav>
<p class="fine">{esc(t(loc, "disclaimer"))}</p>
<p class="fine">© 2026 Bonsai JLPT · jlpt-jp.web.app</p>
</div>
</footer>

<script>{JS}</script>
</body>
</html>
"""


def write_sitemap_and_robots():
    entries = []
    alternates = "\n".join(
        f'    <xhtml:link rel="alternate" hreflang="{code}" '
        f'href="{BASE_URL}/{m["path"]}"/>'
        for code, m in LOCALES.items())
    alternates += (f'\n    <xhtml:link rel="alternate" hreflang="x-default" '
                   f'href="{BASE_URL}/"/>')
    for code, m in LOCALES.items():
        entries.append(f"""  <url>
    <loc>{BASE_URL}/{m["path"]}</loc>
{alternates}
  </url>""")
    sitemap = ('<?xml version="1.0" encoding="UTF-8"?>\n'
               '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"\n'
               '        xmlns:xhtml="http://www.w3.org/1999/xhtml">\n'
               + "\n".join(entries) + "\n</urlset>\n")
    (OUT / "sitemap.xml").write_text(sitemap, encoding="utf-8")

    robots = f"User-agent: *\nAllow: /\n\nSitemap: {BASE_URL}/sitemap.xml\n"
    (OUT / "robots.txt").write_text(robots, encoding="utf-8")
    print(f"  sitemap.xml + robots.txt")


def build():
    OUT.mkdir(exist_ok=True)
    print(f"Bonsai JLPT site → {OUT.relative_to(ROOT)}/ "
          f"({N_LESSONS} lessons, {N_WORDS:,} words, {N_UI_LANGS} UI languages)")
    for loc, meta in LOCALES.items():
        folder = OUT / meta["path"] if meta["path"] else OUT
        folder.mkdir(exist_ok=True)
        path = folder / "index.html"
        html_text = page_html(loc)
        path.write_text(html_text, encoding="utf-8")
        print(f"  {path.relative_to(ROOT)}  ({len(html_text.encode('utf-8')):,} bytes)")
    write_sitemap_and_robots()


if __name__ == "__main__":
    # Builds everything by default; --all is accepted for muscle-memory parity
    # with build-web.py but changes nothing.
    args = [a for a in sys.argv[1:] if a != "--all"]
    if args:
        sys.exit(f"unknown arguments: {args} (this script always builds all locales)")
    build()
