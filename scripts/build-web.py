#!/usr/bin/env python3
"""Generate the promotional website for Japanese Daily 每日日本語.

One HTML template + a translations dict -> 17 static pages:
  web/index.html            (English, x-default)
  web/<lang>/index.html     (16 localized copies)

Usage:  python3 scripts/build-web.py
Never edit web/index.html or web/<lang>/index.html by hand — edit this
script and re-run it.  web/privacy.html and web/terms.html are NOT touched.
"""
import pathlib
from string import Template

ROOT = pathlib.Path(__file__).resolve().parent.parent
WEB = ROOT / "web"
BASE_URL = "https://kf-nihongo.web.app"
APP_STORE = "https://apps.apple.com/app/id1447639161"

# (lang dir, html lang attr, hreflang, og:locale)
LANG_META = [
    ("en",      "en",      "en",      "en_US"),
    ("zh",      "zh-Hans", "zh-Hans", "zh_CN"),
    ("zh-Hant", "zh-Hant", "zh-Hant", "zh_TW"),
    ("vi",      "vi",      "vi",      "vi_VN"),
    ("de",      "de",      "de",      "de_DE"),
    ("th",      "th",      "th",      "th_TH"),
    ("my",      "my",      "my",      "my_MM"),
    ("es",      "es",      "es",      "es_ES"),
    ("fr",      "fr",      "fr",      "fr_FR"),
    ("ru",      "ru",      "ru",      "ru_RU"),
    ("bn",      "bn",      "bn",      "bn_BD"),
    ("hi",      "hi",      "hi",      "hi_IN"),
    ("ta",      "ta",      "ta",      "ta_IN"),
    ("te",      "te",      "te",      "te_IN"),
    ("fil",     "fil",     "fil",     "fil_PH"),
    ("id",      "id",      "id",      "id_ID"),
    ("ko",      "ko",      "ko",      "ko_KR"),
]

TEMPLATE = Template(r"""<!DOCTYPE html>
<html lang="$html_lang">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<meta name="description" content="$desc">
<link rel="canonical" href="$canonical">
$hreflangs
<meta property="og:type" content="website">
<meta property="og:site_name" content="Japanese Daily 每日日本語">
<meta property="og:title" content="$title">
<meta property="og:description" content="$desc">
<meta property="og:url" content="$canonical">
<meta property="og:locale" content="$og_locale">
<meta name="twitter:card" content="summary">
<meta name="twitter:title" content="$title">
<meta name="twitter:description" content="$desc">
<script type="application/ld+json">
{
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  "name": "Japanese Daily 每日日本語",
  "operatingSystem": "iOS",
  "applicationCategory": "EducationalApplication",
  "description": "$desc",
  "inLanguage": "$hreflang",
  "url": "$canonical",
  "installUrl": "$app_store",
  "offers": { "@type": "Offer", "price": "0", "priceCurrency": "USD" }
}
</script>
<script type="application/ld+json">
$faq_jsonld
</script>
<style>
  :root {
    --accent: #0FB0BF;
    --accent-soft: rgba(15, 176, 191, 0.12);
    --green: #2ECC40;
    --red: #FF4136;
    --bg: #fafafa;
    --bg-card: #ffffff;
    --fg: #1a1a1a;
    --fg-muted: #6b6b6b;
    --line: rgba(0, 0, 0, 0.08);
    --badge-bg: #000;
    --badge-fg: #fff;
    --shadow: 0 8px 30px rgba(0, 0, 0, 0.06);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #101214;
      --bg-card: #181b1e;
      --fg: #f0f0f0;
      --fg-muted: #9a9a9a;
      --line: rgba(255, 255, 255, 0.1);
      --badge-bg: #fff;
      --badge-fg: #000;
      --shadow: 0 8px 30px rgba(0, 0, 0, 0.4);
    }
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html { scroll-behavior: smooth; }
  body {
    background: var(--bg);
    color: var(--fg);
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", "Segoe UI", Arial, sans-serif;
    -webkit-font-smoothing: antialiased;
    line-height: 1.6;
    overflow-x: hidden;
  }
  .jp {
    font-family: "Hiragino Sans", "Hiragino Kaku Gothic ProN", "Yu Gothic", "YuGothic",
                 "Noto Sans CJK JP", "Meiryo", sans-serif;
  }

  /* ---------- Hero ---------- */
  .hero {
    position: relative;
    min-height: 92vh;
    display: flex;
    align-items: center;
    justify-content: center;
    text-align: center;
    padding: 4rem 1.5rem;
    overflow: hidden;
  }
  #kana-bg { position: absolute; inset: 0; z-index: 0; pointer-events: none; }
  #kana-bg canvas { display: block; width: 100%; height: 100%; }
  .hero::after {
    content: "";
    position: absolute;
    inset: 0;
    z-index: 1;
    pointer-events: none;
    background: radial-gradient(ellipse at center,
      color-mix(in srgb, var(--bg) 55%, transparent) 0%,
      transparent 70%);
  }
  .hero-inner {
    position: relative;
    z-index: 2;
    max-width: 68rem;
    width: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2.6rem;
  }
  .hero-copy { max-width: 36rem; width: 100%; }
  .hero-kicker {
    display: inline-block;
    font-size: 0.85rem;
    font-weight: 600;
    letter-spacing: 0.05em;
    color: var(--accent);
    background: var(--accent-soft);
    border: 1px solid color-mix(in srgb, var(--accent) 30%, transparent);
    border-radius: 999px;
    padding: 0.35rem 1rem;
    margin-bottom: 1.4rem;
  }
  .hero h1 {
    font-size: clamp(2.4rem, 7vw, 4.2rem);
    font-weight: 800;
    letter-spacing: -0.02em;
    line-height: 1.1;
  }
  .hero h1 .jp-name {
    display: block;
    font-size: clamp(1.4rem, 4vw, 2.2rem);
    font-weight: 600;
    color: var(--accent);
    margin-top: 0.4rem;
  }
  .hero p.tagline {
    margin: 1.4rem auto 0;
    max-width: 34rem;
    font-size: clamp(1.05rem, 2.4vw, 1.3rem);
    color: var(--fg-muted);
  }
  .hero-shots {
    display: flex;
    align-items: center;
    justify-content: center;
  }
  .hero-shot {
    width: clamp(110px, 30vw, 170px);
    height: auto;
    border-radius: 20px;
    box-shadow: var(--shadow);
    border: 1px solid var(--line);
    display: block;
  }
  .hero-shot.shot-today {
    width: clamp(130px, 34vw, 200px);
    z-index: 3;
    position: relative;
  }
  .hero-shot.shot-kana { transform: rotate(-9deg); margin-right: -1.5rem; z-index: 1; opacity: 0.94; }
  .hero-shot.shot-cards { transform: rotate(9deg); margin-left: -1.5rem; z-index: 1; opacity: 0.94; }
  .hero .cta { margin-top: 2.2rem; display: flex; flex-direction: column; align-items: center; gap: 0.9rem; }
  .free-note { font-size: 0.85rem; color: var(--fg-muted); }
  .free-note .dot-green { color: var(--green); }

  .appstore-badge {
    display: inline-flex;
    align-items: center;
    gap: 0.7rem;
    background: var(--badge-bg);
    color: var(--badge-fg);
    text-decoration: none;
    border-radius: 14px;
    padding: 0.7rem 1.4rem 0.7rem 1.1rem;
    transition: transform 0.15s ease, box-shadow 0.15s ease;
    box-shadow: var(--shadow);
  }
  .appstore-badge:hover { transform: translateY(-2px) scale(1.02); }
  .appstore-badge:active { transform: translateY(0) scale(0.99); }
  .appstore-badge svg { width: 28px; height: 34px; flex: none; }
  .appstore-badge .badge-text { text-align: left; line-height: 1.2; }
  .appstore-badge .badge-text small { display: block; font-size: 0.68rem; font-weight: 400; opacity: 0.85; }
  .appstore-badge .badge-text strong { display: block; font-size: 1.25rem; font-weight: 600; letter-spacing: -0.01em; }

  .scroll-hint {
    position: absolute;
    bottom: 1.4rem;
    left: 50%;
    transform: translateX(-50%);
    z-index: 2;
    color: var(--fg-muted);
    font-size: 1.4rem;
    text-decoration: none;
    animation: bob 2.2s ease-in-out infinite;
  }
  @keyframes bob {
    0%, 100% { transform: translate(-50%, 0); }
    50% { transform: translate(-50%, 8px); }
  }

  @media (min-width: 900px) {
    .hero-inner {
      flex-direction: row;
      justify-content: space-between;
      text-align: left;
      max-width: 72rem;
      gap: 3.5rem;
    }
    .hero-copy { text-align: left; width: auto; flex: 1 1 auto; min-width: 0; }
    .hero .hero-copy .tagline { margin-left: 0; margin-right: 0; }
    .hero .hero-copy .cta { align-items: flex-start; }
    .hero-shots { flex: none; }
    .hero-shot { width: clamp(130px, 15vw, 190px); }
    .hero-shot.shot-today { width: clamp(155px, 18vw, 230px); }
  }

  /* ---------- Features (alternating showcase rows) ---------- */
  .features { max-width: 66rem; margin: 0 auto; padding: 4.5rem 1.5rem 1.5rem; }
  .features h2 {
    text-align: center;
    font-size: clamp(1.6rem, 4vw, 2.2rem);
    font-weight: 800;
    letter-spacing: -0.02em;
  }
  .features h2 .jp { color: var(--accent); font-weight: 600; }
  .features > p.sub {
    text-align: center;
    color: var(--fg-muted);
    max-width: 36rem;
    margin: 0.8rem auto 1.5rem;
  }
  .frow {
    position: relative;
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: clamp(1.5rem, 5vw, 4rem);
    align-items: center;
    padding: 3.4rem 0;
  }
  .frow + .frow { border-top: 1px dashed var(--line); }
  .frow:nth-of-type(even) .fcopy { order: 2; }
  .frow:nth-of-type(even) .fviz { order: 1; }
  .fcopy { position: relative; z-index: 1; }
  .fcopy .fnum {
    font-size: 0.8rem;
    font-weight: 700;
    letter-spacing: 0.18em;
    color: var(--accent);
    font-variant-numeric: tabular-nums;
  }
  .fcopy h3 {
    font-size: clamp(1.3rem, 3vw, 1.7rem);
    font-weight: 800;
    letter-spacing: -0.02em;
    margin: 0.3rem 0 0.6rem;
    line-height: 1.25;
  }
  .fcopy p { color: var(--fg-muted); max-width: 26rem; }
  .fglyph {
    position: absolute;
    top: 50%;
    transform: translateY(-50%);
    font-size: clamp(7rem, 16vw, 11rem);
    font-weight: 700;
    line-height: 1;
    color: var(--fg);
    opacity: 0.045;
    pointer-events: none;
    user-select: none;
    z-index: 0;
  }
  .frow:nth-of-type(odd) .fglyph { right: -0.5rem; }
  .frow:nth-of-type(even) .fglyph { left: -0.5rem; }
  .fviz { display: flex; justify-content: center; position: relative; z-index: 1; }

  /* vignette: lesson chips */
  .v-lessons { width: min(100%, 22rem); }
  .lesson-chip {
    display: flex; align-items: center; gap: 0.8rem;
    background: var(--bg-card);
    border: 1px solid var(--line);
    border-radius: 14px;
    box-shadow: var(--shadow);
    padding: 0.7rem 1rem;
    margin-bottom: 0.7rem;
    font-weight: 600;
  }
  .lesson-chip:nth-child(2) { transform: translateX(1.2rem); }
  .lesson-chip:nth-child(3) { transform: translateX(0.4rem); opacity: 0.85; }
  .lesson-chip .ln {
    flex: none;
    width: 2.1rem; height: 2.1rem;
    display: grid; place-items: center;
    border-radius: 10px;
    background: var(--accent-soft);
    color: var(--accent);
    font-size: 0.85rem; font-weight: 800;
  }
  .lesson-chip .bar {
    margin-left: auto; flex: none;
    width: 4.2rem; height: 0.4rem;
    border-radius: 99px;
    background: var(--line);
    overflow: hidden;
  }
  .lesson-chip .bar i { display: block; height: 100%; background: var(--accent); border-radius: 99px; }
  .lesson-chip small { color: var(--fg-muted); font-weight: 400; }

  /* vignette: language chips */
  .v-langs { width: min(100%, 22rem); text-align: center; }
  .v-langs .center-word {
    display: inline-block;
    font-size: 2rem; font-weight: 700;
    color: var(--accent);
    background: var(--accent-soft);
    border: 1px solid color-mix(in srgb, var(--accent) 30%, transparent);
    border-radius: 16px;
    padding: 0.4rem 1.4rem;
    margin-bottom: 1rem;
  }
  .v-langs .cloud { display: flex; flex-wrap: wrap; justify-content: center; gap: 0.45rem; }
  .v-langs .cloud span {
    background: var(--bg-card);
    border: 1px solid var(--line);
    border-radius: 999px;
    padding: 0.25rem 0.8rem;
    font-size: 0.85rem;
    color: var(--fg-muted);
    box-shadow: var(--shadow);
  }
  .v-langs .cloud span.hot { color: var(--accent); border-color: color-mix(in srgb, var(--accent) 40%, transparent); }

  /* vignette: kana tiles + audio */
  .v-kana { display: grid; grid-template-columns: repeat(5, 3.4rem); gap: 0.55rem; }
  .v-kana .tile {
    height: 3.4rem;
    display: grid; place-items: center;
    background: var(--bg-card);
    border: 1px solid var(--line);
    border-radius: 12px;
    box-shadow: var(--shadow);
    font-size: 1.3rem; font-weight: 600;
  }
  .v-kana .tile.on {
    background: var(--accent);
    border-color: var(--accent);
    color: #fff;
    position: relative;
  }
  .v-kana .tile.done { border-bottom: 3px solid var(--green); }
  .v-kana .tile.miss { border-bottom: 3px solid var(--red); }
  .v-kana .speaker {
    grid-column: 1 / -1;
    display: flex; align-items: center; justify-content: center; gap: 0.5rem;
    margin-top: 0.4rem;
    color: var(--accent);
    font-weight: 700; font-size: 0.9rem;
  }
  .eq { display: inline-flex; align-items: flex-end; gap: 2px; height: 14px; }
  .eq i { width: 3px; background: var(--accent); border-radius: 2px; animation: eq 1s ease-in-out infinite; }
  .eq i:nth-child(1) { height: 6px; animation-delay: 0s; }
  .eq i:nth-child(2) { height: 12px; animation-delay: 0.15s; }
  .eq i:nth-child(3) { height: 8px; animation-delay: 0.3s; }
  .eq i:nth-child(4) { height: 11px; animation-delay: 0.45s; }
  @keyframes eq { 0%, 100% { transform: scaleY(0.5); } 50% { transform: scaleY(1); } }

  /* vignette: quiz card */
  .v-quiz {
    width: min(100%, 20rem);
    background: var(--bg-card);
    border: 1px solid var(--line);
    border-radius: 18px;
    box-shadow: var(--shadow);
    padding: 1.3rem 1.3rem 1.1rem;
  }
  .v-quiz .qprompt {
    display: flex; align-items: center; justify-content: center; gap: 0.6rem;
    color: var(--accent); font-weight: 700;
    margin-bottom: 1rem;
  }
  .v-quiz .opt {
    display: flex; align-items: center; justify-content: space-between;
    border: 1px solid var(--line);
    border-radius: 12px;
    padding: 0.55rem 0.9rem;
    margin-bottom: 0.55rem;
    font-weight: 600; font-size: 1.05rem;
  }
  .v-quiz .opt.ok { border-color: var(--green); background: color-mix(in srgb, var(--green) 8%, transparent); }
  .v-quiz .opt.ok b { color: var(--green); }
  .v-quiz .opt.ng { border-color: color-mix(in srgb, var(--red) 50%, transparent); opacity: 0.75; }
  .v-quiz .opt.ng b { color: var(--red); }
  .v-quiz .opt b { font-size: 0.95rem; }

  /* vignette: flashcard stack */
  .v-cards { position: relative; width: min(100%, 15rem); height: 13.5rem; }
  .v-cards .fcard {
    position: absolute; inset: 0;
    background: var(--bg-card);
    border: 1px solid var(--line);
    border-radius: 20px;
    box-shadow: var(--shadow);
    display: grid; place-items: center;
  }
  .v-cards .fcard.b2 { transform: rotate(-6deg) translateY(8px); opacity: 0.5; }
  .v-cards .fcard.b1 { transform: rotate(3.5deg) translateY(4px); opacity: 0.75; }
  .v-cards .fcard.top { transform: rotate(-1.5deg); }
  .v-cards .fcard .word { font-size: 2.1rem; font-weight: 700; }
  .v-cards .fcard .reading { color: var(--fg-muted); font-size: 0.95rem; margin-top: 0.2rem; text-align: center; }
  .v-cards .tag {
    position: absolute; top: 0.8rem;
    font-size: 0.72rem; font-weight: 800; letter-spacing: 0.08em;
    border-radius: 8px; padding: 0.15rem 0.5rem;
    border: 2px solid;
  }
  .v-cards .tag.know { right: 0.9rem; color: var(--green); border-color: var(--green); transform: rotate(8deg); }
  .v-cards .tag.again { left: 0.9rem; color: var(--red); border-color: var(--red); transform: rotate(-8deg); }
  .v-cards .swipe-arrows {
    position: absolute; bottom: -1.9rem; left: 0; right: 0;
    text-align: center; color: var(--fg-muted); font-size: 0.85rem;
  }
  .v-cards .swipe-arrows .r { color: var(--green); }
  .v-cards .swipe-arrows .l { color: var(--red); }

  /* vignette: write / stroke order */
  .v-write {
    width: min(100%, 15rem);
    background: var(--bg-card);
    border: 1px solid var(--line);
    border-radius: 20px;
    box-shadow: var(--shadow);
    padding: 1rem;
  }
  .v-write svg { display: block; width: 100%; height: auto; }
  .v-write .guide { stroke: var(--fg-muted); opacity: 0.35; }
  .v-write .trace {
    stroke: var(--accent);
    stroke-dasharray: 320;
    stroke-dashoffset: 320;
    animation: draw 2.6s ease-in-out infinite;
  }
  @keyframes draw {
    0% { stroke-dashoffset: 320; }
    55%, 80% { stroke-dashoffset: 0; }
    100% { stroke-dashoffset: 0; opacity: 0; }
  }
  .v-write .snum { fill: var(--accent); font-size: 13px; font-weight: 700; font-family: inherit; }
  .v-write .grid-line { stroke: var(--line); stroke-dasharray: 4 5; }

  /* vignette: widget */
  .v-widget {
    width: min(100%, 15.5rem);
    background: linear-gradient(160deg,
      color-mix(in srgb, var(--accent) 14%, var(--bg-card)),
      var(--bg-card) 55%);
    border: 1px solid var(--line);
    border-radius: 26px;
    box-shadow: var(--shadow);
    padding: 1.2rem 1.2rem 1.4rem;
    text-align: center;
  }
  .v-widget .clock { font-size: 2.4rem; font-weight: 300; letter-spacing: 0.02em; }
  .v-widget .date { color: var(--fg-muted); font-size: 0.8rem; margin-bottom: 0.9rem; }
  .v-widget .wcard {
    background: var(--bg-card);
    border: 1px solid var(--line);
    border-radius: 16px;
    padding: 0.8rem 1rem;
    text-align: left;
    box-shadow: var(--shadow);
  }
  .v-widget .wlabel {
    font-size: 0.65rem; font-weight: 800; letter-spacing: 0.14em;
    color: var(--accent);
    margin-bottom: 0.2rem;
  }
  .v-widget .wword { font-size: 1.35rem; font-weight: 700; }
  .v-widget .wread { color: var(--fg-muted); font-size: 0.85rem; }

  /* ---------- How it works ---------- */
  .how { max-width: 62rem; margin: 0 auto; padding: 4.5rem 1.5rem 1rem; text-align: center; }
  .how .fnum { font-size: 0.8rem; font-weight: 700; letter-spacing: 0.18em; color: var(--accent); text-transform: uppercase; }
  .how h2 { font-size: clamp(1.6rem, 4vw, 2.2rem); font-weight: 800; letter-spacing: -0.02em; margin: 0.3rem 0 0.6rem; }
  .how > p.sub { color: var(--fg-muted); max-width: 34rem; margin: 0 auto 2.2rem; }
  .how-steps { display: grid; grid-template-columns: repeat(3, 1fr); gap: 1.5rem; text-align: left; }
  .how-step {
    background: var(--bg-card);
    border: 1px solid var(--line);
    border-radius: 18px;
    box-shadow: var(--shadow);
    padding: 1.6rem 1.4rem;
  }
  .how-step .how-n {
    display: inline-grid;
    place-items: center;
    width: 2.2rem; height: 2.2rem;
    border-radius: 999px;
    background: var(--accent-soft);
    color: var(--accent);
    font-weight: 800;
    margin-bottom: 0.9rem;
  }
  .how-step h3 { font-size: 1.05rem; font-weight: 700; margin-bottom: 0.4rem; }
  .how-step p { color: var(--fg-muted); font-size: 0.92rem; }
  @media (max-width: 760px) {
    .how-steps { grid-template-columns: 1fr; }
  }

  /* ---------- FAQ ---------- */
  .faq { max-width: 42rem; margin: 0 auto; padding: 4rem 1.5rem 1rem; text-align: center; }
  .faq .fnum { font-size: 0.8rem; font-weight: 700; letter-spacing: 0.18em; color: var(--accent); text-transform: uppercase; }
  .faq h2 { font-size: clamp(1.6rem, 4vw, 2.2rem); font-weight: 800; letter-spacing: -0.02em; margin: 0.3rem 0 0.6rem; }
  .faq > p.sub { color: var(--fg-muted); margin-bottom: 2rem; }
  .faq-list { text-align: left; display: flex; flex-direction: column; gap: 0.8rem; }
  .faq-item {
    background: var(--bg-card);
    border: 1px solid var(--line);
    border-radius: 14px;
    box-shadow: var(--shadow);
    padding: 1rem 1.2rem;
  }
  .faq-item summary {
    font-weight: 700;
    cursor: pointer;
    list-style: none;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 1rem;
  }
  .faq-item summary::-webkit-details-marker { display: none; }
  .faq-item summary::after {
    content: "+";
    color: var(--accent);
    font-weight: 800;
    font-size: 1.2rem;
    flex: none;
    transition: transform 0.15s ease;
  }
  .faq-item[open] summary::after { transform: rotate(45deg); }
  .faq-item p { color: var(--fg-muted); margin-top: 0.7rem; }

  /* ---------- Try-it quiz ---------- */
  .try-quiz {
    max-width: 36rem; margin: 0 auto; padding: 4rem 1.5rem 2rem; text-align: center;
  }
  .try-quiz .quiz-badge {
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    font-size: 0.9rem;
    font-weight: 800;
    letter-spacing: 0.02em;
    color: #fff;
    background: var(--accent);
    border-radius: 999px;
    padding: 0.5rem 1.3rem;
    margin-bottom: 1.1rem;
    box-shadow: 0 4px 16px color-mix(in srgb, var(--accent) 45%, transparent);
    animation: badge-pop 1.6s ease-in-out 2;
  }
  .try-quiz .quiz-badge::before { content: "▶"; font-size: 0.7em; }
  @keyframes badge-pop {
    0%, 100% { transform: scale(1); }
    50% { transform: scale(1.06); }
  }
  .try-quiz .fnum { font-size: 0.8rem; font-weight: 700; letter-spacing: 0.18em; color: var(--accent); }
  .try-quiz h2 { font-size: clamp(1.6rem, 4vw, 2.2rem); font-weight: 800; letter-spacing: -0.02em; margin: 0.3rem 0 0.6rem; }
  .try-quiz > p.sub { color: var(--fg-muted); margin-bottom: 1.8rem; }
  .quiz-box {
    background: var(--bg-card);
    border: 1px solid var(--line);
    border-radius: 22px;
    box-shadow: var(--shadow);
    padding: 1.8rem 1.4rem 1.6rem;
    text-align: center;
    animation: quiz-invite 1.8s ease-in-out 2;
  }
  /* A couple of gentle pulses on the box's ring to draw the eye down the page —
     stops on its own so it doesn't nag; off entirely for reduced motion. */
  @keyframes quiz-invite {
    0%, 100% { box-shadow: var(--shadow); }
    50% { box-shadow: var(--shadow), 0 0 0 4px color-mix(in srgb, var(--accent) 25%, transparent); }
  }
  .quiz-box .qword { font-size: clamp(2.2rem, 7vw, 3rem); font-weight: 700; line-height: 1.2; }
  .quiz-box .qkana { color: var(--fg-muted); margin-bottom: 1.4rem; }
  .quiz-box .qopts { display: grid; gap: 0.6rem; }
  .quiz-box .qopt {
    appearance: none;
    font: inherit;
    font-weight: 600;
    color: var(--fg);
    background: transparent;
    border: 1px solid var(--line);
    border-radius: 14px;
    padding: 0.7rem 1rem;
    cursor: pointer;
    transition: border-color 0.12s ease, background 0.12s ease, transform 0.12s ease;
  }
  .quiz-box .qopt:hover:not(:disabled) { border-color: var(--accent); transform: translateY(-1px); }
  .quiz-box .qopt:disabled { cursor: default; }
  .quiz-box .qopt.right { border-color: var(--green); background: color-mix(in srgb, var(--green) 10%, transparent); }
  .quiz-box .qopt.wrong { border-color: var(--red); background: color-mix(in srgb, var(--red) 8%, transparent); }
  .quiz-box .qfeedback { min-height: 1.6rem; margin-top: 0.9rem; font-weight: 700; }
  .quiz-box .qfeedback.good { color: var(--green); }
  .quiz-box .qfeedback.bad { color: var(--red); }
  .quiz-box .qdots { display: flex; justify-content: center; gap: 0.4rem; margin-top: 0.9rem; }
  .quiz-box .qdots i {
    width: 0.5rem; height: 0.5rem; border-radius: 99px;
    background: var(--line);
  }
  .quiz-box .qdots i.hit { background: var(--green); }
  .quiz-box .qdots i.miss { background: var(--red); }
  .quiz-box .qdots i.now { background: var(--accent); }
  .quiz-box .qnext, .quiz-box .qrestart {
    appearance: none;
    font: inherit; font-weight: 700;
    color: #fff;
    background: var(--accent);
    border: 0;
    border-radius: 999px;
    padding: 0.55rem 1.6rem;
    margin-top: 1rem;
    cursor: pointer;
    transition: transform 0.12s ease, filter 0.12s ease;
  }
  .quiz-box .qnext:hover, .quiz-box .qrestart:hover { transform: translateY(-1px); filter: brightness(1.05); }
  .quiz-box .qnext[hidden] { display: none; }
  .quiz-box .qscore { font-size: 1.5rem; font-weight: 800; margin-bottom: 0.5rem; }
  .quiz-box .qpitch { color: var(--fg-muted); max-width: 26rem; margin: 0 auto 1.2rem; }
  .quiz-box .qend .appstore-badge { margin-bottom: 0.4rem; }
  .quiz-box .qrestart { display: block; margin: 0.8rem auto 0; background: transparent; color: var(--accent); border: 1px solid var(--accent); }
  .noscript-note { color: var(--fg-muted); font-size: 0.9rem; }

  /* ---------- Bottom CTA ---------- */
  .bottom-cta { text-align: center; padding: 4rem 1.5rem 5rem; }
  .bottom-cta .big-kana {
    font-size: clamp(2rem, 6vw, 3rem);
    color: var(--accent);
    font-weight: 600;
    margin-bottom: 0.6rem;
  }
  .bottom-cta p { color: var(--fg-muted); margin-bottom: 1.8rem; }

  /* ---------- Footer ---------- */
  footer {
    border-top: 1px solid var(--line);
    padding: 2.2rem 1.5rem 2.6rem;
    text-align: center;
    font-size: 0.88rem;
    color: var(--fg-muted);
  }
  footer nav.legal { margin-bottom: 1.1rem; display: flex; justify-content: center; gap: 1.6rem; flex-wrap: wrap; }
  footer a { color: var(--accent); text-decoration: none; }
  footer a:hover { text-decoration: underline; }
  .lang-switch { margin-bottom: 1.1rem; }
  .lang-switch .lang-label {
    display: block;
    font-size: 0.72rem; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase;
    margin-bottom: 0.5rem;
  }
  .lang-switch nav { display: flex; flex-wrap: wrap; justify-content: center; gap: 0.3rem 0.9rem; max-width: 44rem; margin: 0 auto; }
  .lang-switch a { color: var(--fg-muted); font-size: 0.82rem; }
  .lang-switch a:hover { color: var(--accent); }
  .lang-switch a[aria-current="true"] { color: var(--accent); font-weight: 700; }

  @media (max-width: 760px) {
    .frow { grid-template-columns: 1fr; gap: 1.8rem; padding: 2.6rem 0; }
    .frow:nth-of-type(even) .fcopy { order: 1; }
    .frow:nth-of-type(even) .fviz { order: 2; }
    .fglyph { display: none; }
    .v-kana { grid-template-columns: repeat(5, 3rem); }
    .v-kana .tile { height: 3rem; font-size: 1.15rem; }
  }
  @media (prefers-reduced-motion: reduce) {
    html { scroll-behavior: auto; }
    .scroll-hint, .eq i, .v-write .trace, .quiz-box, .quiz-badge { animation: none; }
    .v-write .trace { stroke-dashoffset: 0; }
  }

  /* ---------- Floating "try it" button — visible from anywhere on the page ---------- */
  .quiz-fab {
    position: fixed;
    bottom: 1.3rem;
    right: 1.3rem;
    z-index: 50;
    display: inline-flex;
    align-items: center;
    gap: 0.4rem;
    font-size: 0.85rem;
    font-weight: 800;
    color: #fff;
    background: var(--accent);
    border-radius: 999px;
    padding: 0.7rem 1.15rem;
    box-shadow: 0 6px 20px color-mix(in srgb, var(--accent) 45%, transparent);
    text-decoration: none;
    transition: transform 0.15s ease;
  }
  .quiz-fab::before { content: "▶"; font-size: 0.7em; }
  .quiz-fab:hover { transform: translateY(-2px); }
  @media (max-width: 480px) {
    .quiz-fab { bottom: 1rem; right: 1rem; padding: 0.6rem 0.95rem; font-size: 0.78rem; }
  }
  @media (prefers-reduced-motion: reduce) {
    .quiz-fab { transition: none; }
  }
</style>
</head>
<body>

<a class="quiz-fab" href="#try">$quiz_badge</a>

<header class="hero">
  <div id="kana-bg" aria-hidden="true"></div>
  <div class="hero-inner">
    <div class="hero-copy">
      <span class="hero-kicker"><span class="jp">毎日、少しずつ</span> — $kicker</span>
      <h1>Japanese Daily
        <span class="jp-name jp">每日日本語</span>
      </h1>
      <p class="tagline">$tagline</p>
      <div class="cta">
        <a class="appstore-badge" href="$app_store" rel="noopener" aria-label="Download Japanese Daily on the App Store">
          <svg viewBox="0 0 24 29" fill="currentColor" aria-hidden="true">
            <path d="M19.7 15.3c0-3.1 2.5-4.6 2.6-4.7-1.4-2.1-3.7-2.4-4.5-2.4-1.9-.2-3.7 1.1-4.6 1.1-1 0-2.4-1.1-4-1.1-2 0-3.9 1.2-5 3-2.1 3.7-.5 9.2 1.5 12.2 1 1.5 2.2 3.1 3.8 3.1 1.5-.1 2.1-1 3.9-1s2.4 1 4 1c1.7 0 2.7-1.5 3.7-3 1.2-1.7 1.6-3.4 1.7-3.5-.1-.1-3.1-1.2-3.1-4.7zM16.6 6.2c.8-1 1.4-2.4 1.2-3.8-1.2 0-2.7.8-3.5 1.8-.8.9-1.5 2.3-1.3 3.7 1.3.1 2.7-.7 3.6-1.7z"/>
          </svg>
          <span class="badge-text">
            <small>Download on the</small>
            <strong>App Store</strong>
          </span>
        </a>
        <span class="free-note"><span class="dot-green" aria-hidden="true">●</span> $free_note</span>
      </div>
    </div>
    <div class="hero-shots">
      <img class="hero-shot shot-kana" src="/img/screenshot-kana.png" width="400" height="869" loading="eager" decoding="async" alt="$hero_alt2">
      <img class="hero-shot shot-today" src="/img/screenshot-today.png" width="400" height="869" loading="eager" decoding="async" alt="$hero_alt">
      <img class="hero-shot shot-cards" src="/img/screenshot-cards.png" width="400" height="869" loading="eager" decoding="async" alt="$hero_alt3">
    </div>
  </div>
  <a class="scroll-hint" href="#features" aria-label="Scroll down to features">↓</a>
</header>

<main>
  <section class="features" id="features" aria-label="Features">
    <h2>$feat_h2</h2>
    <p class="sub">$feat_sub</p>

    <article class="frow">
      <div class="fcopy">
        <span class="fnum">01</span>
        <h3>$f1t</h3>
        <p>$f1d</p>
      </div>
      <div class="fviz">
        <div class="v-lessons" aria-hidden="true">
          <div class="lesson-chip"><span class="ln">1</span><span class="jp">だい1か</span><span class="bar"><i style="width:100%"></i></span></div>
          <div class="lesson-chip"><span class="ln">2</span><span class="jp">だい2か</span><span class="bar"><i style="width:65%"></i></span></div>
          <div class="lesson-chip"><span class="ln">3</span><span class="jp">だい3か</span><span class="bar"><i style="width:20%"></i></span></div>
          <div class="lesson-chip"><span class="ln">50</span><span class="jp">だい50か</span><small>…</small></div>
        </div>
      </div>
      <span class="fglyph jp" aria-hidden="true">本</span>
    </article>

    <article class="frow">
      <div class="fcopy">
        <span class="fnum">02</span>
        <h3>$f2t</h3>
        <p>$f2d</p>
      </div>
      <div class="fviz">
        <div class="v-langs" aria-hidden="true">
          <span class="center-word jp">わたし</span>
          <div class="cloud">
            <span class="hot">I</span><span>我</span><span>tôi</span><span>ich</span><span>ฉัน</span>
            <span class="hot">yo</span><span>je</span><span>я</span><span>আমি</span><span>मैं</span>
            <span>நான்</span><span class="hot">నేను</span><span>ako</span><span>saya</span><span>나</span>
          </div>
        </div>
      </div>
      <span class="fglyph jp" aria-hidden="true">語</span>
    </article>

    <article class="frow">
      <div class="fcopy">
        <span class="fnum">03</span>
        <h3>$f3t</h3>
        <p>$f3d</p>
      </div>
      <div class="fviz">
        <div class="v-kana jp" aria-hidden="true">
          <span class="tile done">あ</span><span class="tile">い</span><span class="tile on">う</span><span class="tile done">え</span><span class="tile">お</span>
          <span class="tile">ア</span><span class="tile miss">イ</span><span class="tile">ウ</span><span class="tile">エ</span><span class="tile done">オ</span>
          <span class="speaker">
            <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3a4.5 4.5 0 0 0-2.5-4v8a4.5 4.5 0 0 0 2.5-4z"/></svg>
            u
            <span class="eq"><i></i><i></i><i></i><i></i></span>
          </span>
        </div>
      </div>
      <span class="fglyph jp" aria-hidden="true">あ</span>
    </article>

    <article class="frow">
      <div class="fcopy">
        <span class="fnum">04</span>
        <h3>$f4t</h3>
        <p>$f4d</p>
      </div>
      <div class="fviz">
        <div class="v-quiz" aria-hidden="true">
          <div class="qprompt">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3a4.5 4.5 0 0 0-2.5-4v8a4.5 4.5 0 0 0 2.5-4zM14 3.2v2.1a7 7 0 0 1 0 13.4v2.1a9 9 0 0 0 0-17.6z"/></svg>
            <span class="eq"><i></i><i></i><i></i><i></i></span>
          </div>
          <div class="opt ok"><span class="jp">みず・水</span><b>&#10003;</b></div>
          <div class="opt"><span class="jp">ほん・本</span></div>
          <div class="opt ng"><span class="jp">き・木</span><b>&#10007;</b></div>
        </div>
      </div>
      <span class="fglyph jp" aria-hidden="true">聞</span>
    </article>

    <article class="frow">
      <div class="fcopy">
        <span class="fnum">05</span>
        <h3>$f5t</h3>
        <p>$f5d</p>
      </div>
      <div class="fviz">
        <div class="v-cards" aria-hidden="true">
          <div class="fcard b2"></div>
          <div class="fcard b1"></div>
          <div class="fcard top">
            <div>
              <div class="word jp">せんせい</div>
              <div class="reading">先生 · sensei</div>
            </div>
            <span class="tag know">&#10003;</span>
            <span class="tag again">&#10007;</span>
          </div>
          <div class="swipe-arrows"><span class="l">&#8592;</span> &nbsp;·&nbsp; <span class="r">&#8594;</span></div>
        </div>
      </div>
      <span class="fglyph jp" aria-hidden="true">先</span>
    </article>

    <article class="frow">
      <div class="fcopy">
        <span class="fnum">06</span>
        <h3>$f6t</h3>
        <p>$f6d</p>
      </div>
      <div class="fviz">
        <div class="v-write" aria-hidden="true">
          <svg viewBox="0 0 160 160" fill="none" stroke-linecap="round">
            <line class="grid-line" x1="80" y1="8" x2="80" y2="152" stroke-width="1"/>
            <line class="grid-line" x1="8" y1="80" x2="152" y2="80" stroke-width="1"/>
            <path class="guide" d="M45.52,48.44c1.29,1.29,4.04,2.67,7.71,2.57c12.65,-0.37,29.36,-3.11,43.30,-6.24c2.22,-0.50,6.78,-1.29,9.72,-0.73" stroke-width="9"/>
            <path class="guide" d="M73.04,25.86c1.29,1.47,2.67,4.79,2.03,7.71c-5.50,24.59,-9.17,55.97,-7.53,78.72c0.60,8.37,2.76,15.97,4.96,19.99" stroke-width="9"/>
            <path class="guide" d="M96.34,64.76c1.10,1.64,1.70,6.44,0.73,8.98c-6.78,18.00,-16.50,34.88,-37.24,52.49c-10.07,8.56,-23.31,5.50,-23.85,-12.30c-0.50,-15.96,19.64,-33.94,47.53,-39.25c18.23,-3.48,39.63,2.03,44.77,18.72c5.94,19.35,-5.52,38.71,-30.65,44.76" stroke-width="9"/>
            <path class="trace" d="M96.34,64.76c1.10,1.64,1.70,6.44,0.73,8.98c-6.78,18.00,-16.50,34.88,-37.24,52.49c-10.07,8.56,-23.31,5.50,-23.85,-12.30c-0.50,-15.96,19.64,-33.94,47.53,-39.25c18.23,-3.48,39.63,2.03,44.77,18.72c5.94,19.35,-5.52,38.71,-30.65,44.76" stroke-width="9"/>
            <text class="snum" x="33.05" y="51.38">1</text>
            <text class="snum" x="60.94" y="27.89">2</text>
            <text class="snum" x="84.40" y="61.65">3</text>
          </svg>
        </div>
      </div>
      <span class="fglyph jp" aria-hidden="true">書</span>
    </article>

    <article class="frow">
      <div class="fcopy">
        <span class="fnum">07</span>
        <h3>$f7t</h3>
        <p>$f7d</p>
      </div>
      <div class="fviz">
        <div class="v-widget" aria-hidden="true">
          <div class="clock">9:41</div>
          <div class="date jp">8月7日 金曜日</div>
          <div class="wcard">
            <div class="wlabel jp">きょうのことば</div>
            <div class="wword jp">日本語</div>
            <div class="wread jp">にほんご · nihongo</div>
          </div>
        </div>
      </div>
      <span class="fglyph jp" aria-hidden="true">今</span>
    </article>
  </section>

  <section class="how" id="how" aria-label="$how_title">
    <span class="fnum">$how_kicker</span>
    <h2>$how_title</h2>
    <p class="sub">$how_sub</p>
    <div class="how-steps">
      <div class="how-step">
        <span class="how-n">1</span>
        <h3>$how1t</h3>
        <p>$how1d</p>
      </div>
      <div class="how-step">
        <span class="how-n">2</span>
        <h3>$how2t</h3>
        <p>$how2d</p>
      </div>
      <div class="how-step">
        <span class="how-n">3</span>
        <h3>$how3t</h3>
        <p>$how3d</p>
      </div>
    </div>
  </section>

  <section class="try-quiz" id="try" aria-label="$quiz_title">
    <span class="quiz-badge">$quiz_badge</span>
    <span class="fnum jp">だい1か</span>
    <h2>$quiz_title</h2>
    <p class="sub">$quiz_sub</p>
    <div class="quiz-box" id="quiz-box">
      <noscript><p class="noscript-note">$quiz_sub</p></noscript>
    </div>
  </section>

  <section class="faq" id="faq" aria-label="$faq_title">
    <span class="fnum">$faq_kicker</span>
    <h2>$faq_title</h2>
    <p class="sub">$faq_sub</p>
    <div class="faq-list">
      <details class="faq-item">
        <summary>$faq1q</summary>
        <p>$faq1a</p>
      </details>
      <details class="faq-item">
        <summary>$faq2q</summary>
        <p>$faq2a</p>
      </details>
      <details class="faq-item">
        <summary>$faq3q</summary>
        <p>$faq3a</p>
      </details>
      <details class="faq-item">
        <summary>$faq4q</summary>
        <p>$faq4a</p>
      </details>
    </div>
  </section>

  <section class="bottom-cta" aria-label="Download">
    <p class="big-kana jp">はじめましょう</p>
    <p>$cta_sub</p>
    <a class="appstore-badge" href="$app_store" rel="noopener" aria-label="Download Japanese Daily on the App Store">
      <svg viewBox="0 0 24 29" fill="currentColor" aria-hidden="true">
        <path d="M19.7 15.3c0-3.1 2.5-4.6 2.6-4.7-1.4-2.1-3.7-2.4-4.5-2.4-1.9-.2-3.7 1.1-4.6 1.1-1 0-2.4-1.1-4-1.1-2 0-3.9 1.2-5 3-2.1 3.7-.5 9.2 1.5 12.2 1 1.5 2.2 3.1 3.8 3.1 1.5-.1 2.1-1 3.9-1s2.4 1 4 1c1.7 0 2.7-1.5 3.7-3 1.2-1.7 1.6-3.4 1.7-3.5-.1-.1-3.1-1.2-3.1-4.7zM16.6 6.2c.8-1 1.4-2.4 1.2-3.8-1.2 0-2.7.8-3.5 1.8-.8.9-1.5 2.3-1.3 3.7 1.3.1 2.7-.7 3.6-1.7z"/>
      </svg>
      <span class="badge-text">
        <small>Download on the</small>
        <strong>App Store</strong>
      </span>
    </a>
  </section>
</main>

<footer>
$switcher_block
  <nav class="legal" aria-label="Legal">
    <a href="/privacy.html">$privacy</a>
    <a href="/terms.html">$terms</a>
    <a href="$app_store" rel="noopener">App Store</a>
  </nav>
  <p>&copy; 2026 Japanese Daily 每日日本語. $rights</p>
</footer>

<script>
(function () {
  "use strict";
  // Lesson 1 mini quiz — real Minna no Nihongo vocabulary + translations
  var DATA = $quiz_data;
  var I18N = $quiz_i18n;
  var ROUNDS = 6;

  var box = document.getElementById("quiz-box");
  if (!box) return;

  function shuffle(a) {
    for (var i = a.length - 1; i > 0; i--) {
      var j = Math.floor(Math.random() * (i + 1));
      var t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a;
  }

  var order, idx, score, results;

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text) e.textContent = text;
    return e;
  }

  function badge() {
    var a = document.createElement("a");
    a.className = "appstore-badge";
    a.href = "$app_store";
    a.rel = "noopener";
    a.innerHTML = document.querySelector(".bottom-cta .appstore-badge").innerHTML;
    return a;
  }

  function start() {
    order = shuffle(DATA.slice()).slice(0, ROUNDS);
    idx = 0; score = 0; results = [];
    question();
  }

  function dots() {
    var wrap = el("div", "qdots");
    for (var i = 0; i < ROUNDS; i++) {
      var d = el("i");
      if (i < results.length) d.className = results[i] ? "hit" : "miss";
      else if (i === idx) d.className = "now";
      wrap.appendChild(d);
    }
    return wrap;
  }

  function question() {
    var item = order[idx];
    box.textContent = "";
    box.appendChild(el("p", "qkana", I18N.prompt));
    var w = el("div", "qword jp", item.w);
    box.appendChild(w);
    box.appendChild(el("div", "qkana jp", item.k + " · " + item.r));

    var opts = el("div", "qopts");
    var wrongPool = shuffle(DATA.filter(function (d) { return d.m !== item.m; })).slice(0, 3);
    var choices = shuffle(wrongPool.concat([item]));
    var feedback = el("div", "qfeedback");
    var next = el("button", "qnext", I18N.next);
    next.hidden = true;

    choices.forEach(function (c) {
      var b = el("button", "qopt", c.m);
      b.type = "button";
      b.addEventListener("click", function () {
        var good = c.m === item.m;
        if (good) { score++; b.classList.add("right"); }
        else { b.classList.add("wrong"); }
        results.push(good);
        feedback.textContent = good ? I18N.correct : I18N.wrong;
        feedback.className = "qfeedback " + (good ? "good" : "bad");
        Array.prototype.forEach.call(opts.children, function (o) {
          o.disabled = true;
          if (o.textContent === item.m) o.classList.add("right");
        });
        next.hidden = false;
        next.focus();
      });
      opts.appendChild(b);
    });
    box.appendChild(opts);
    box.appendChild(feedback);
    next.addEventListener("click", function () {
      idx++;
      if (idx < ROUNDS) question(); else end();
    });
    box.appendChild(next);
    box.appendChild(dots());
  }

  function end() {
    box.textContent = "";
    var wrap = el("div", "qend");
    wrap.appendChild(el("div", "qscore",
      I18N.score.replace("{x}", String(score)).replace("{y}", String(ROUNDS))));
    wrap.appendChild(el("p", "qpitch", I18N.pitch));
    wrap.appendChild(badge());
    var r = el("button", "qrestart", I18N.restart);
    r.type = "button";
    r.addEventListener("click", start);
    wrap.appendChild(r);
    box.appendChild(wrap);
  }

  start();
})();
</script>
<script src="https://unpkg.com/three@0.160.0/build/three.min.js"></script>
<script>
(function () {
  "use strict";
  if (typeof THREE === "undefined") return;
  var container = document.getElementById("kana-bg");
  if (!container) return;

  function webglAvailable() {
    try {
      var c = document.createElement("canvas");
      return !!(window.WebGLRenderingContext &&
        (c.getContext("webgl") || c.getContext("experimental-webgl")));
    } catch (e) { return false; }
  }
  if (!webglAvailable()) return;

  var reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  var HIRAGANA = "あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん".split("");
  var KATAKANA = "アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン".split("");
  // Lesson 1 vocabulary (Minna no Nihongo) — ties the floating background
  // words to the real vocabulary used in the try-it quiz below.
  var WORDS = ["わたし", "あなた", "先生", "学生", "会社員",
               "医者", "大学", "病院", "だれ", "はい"];

  var ACCENT = "#0FB0BF";
  var isDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  var GRAYS = isDark
    ? ["#8f9499", "#6d7378", "#a7acb1"]
    : ["#9aa0a5", "#b8bdc2", "#7d838a"];

  var JP_FONT = '"Hiragino Sans", "Hiragino Kaku Gothic ProN", "Yu Gothic", "Noto Sans CJK JP", "Meiryo", sans-serif';

  function makeTextTexture(text, color, isWord) {
    var canvas = document.createElement("canvas");
    var size = 256;
    canvas.width = isWord ? size * Math.max(2, text.length * 0.6) : size;
    canvas.height = size;
    var ctx = canvas.getContext("2d");
    ctx.fillStyle = color;
    ctx.font = "600 " + Math.floor(size * 0.62) + "px " + JP_FONT;
    ctx.textAlign = "center";
    ctx.textBaseline = "middle";
    ctx.fillText(text, canvas.width / 2, canvas.height / 2 + size * 0.03);
    var tex = new THREE.CanvasTexture(canvas);
    tex.anisotropy = 2;
    return { texture: tex, aspect: canvas.width / canvas.height };
  }

  var scene = new THREE.Scene();
  var camera = new THREE.PerspectiveCamera(55, 1, 0.1, 100);
  camera.position.z = 14;

  var renderer;
  try {
    renderer = new THREE.WebGLRenderer({ alpha: true, antialias: true });
  } catch (e) { return; }
  renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
  container.appendChild(renderer.domElement);

  var sprites = [];
  function rand(min, max) { return min + Math.random() * (max - min); }
  function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }

  function addSprite(text, isWord) {
    var useAccent = isWord ? Math.random() < 0.7 : Math.random() < 0.2;
    var color = useAccent ? ACCENT : pick(GRAYS);
    var t = makeTextTexture(text, color, isWord);
    var material = new THREE.SpriteMaterial({
      map: t.texture,
      transparent: true,
      opacity: isWord ? rand(0.5, 0.8) : rand(0.25, 0.6),
      depthWrite: false
    });
    var sprite = new THREE.Sprite(material);
    var scale = isWord ? rand(1.6, 2.4) : rand(0.7, 1.5);
    sprite.scale.set(scale * t.aspect, scale, 1);
    sprite.position.set(rand(-13, 13), rand(-8, 8), rand(-8, 6));
    sprite.userData = {
      vx: rand(-0.05, 0.05),
      vy: rand(0.02, 0.09) * (Math.random() < 0.5 ? 1 : -1),
      spin: rand(-0.15, 0.15),
      wobblePhase: rand(0, Math.PI * 2),
      wobbleSpeed: rand(0.2, 0.6)
    };
    scene.add(sprite);
    sprites.push(sprite);
  }

  var kanaPool = HIRAGANA.concat(KATAKANA);
  var isSmall = window.innerWidth < 640;
  var kanaCount = isSmall ? 34 : 60;
  for (var i = 0; i < kanaCount; i++) addSprite(pick(kanaPool), false);
  WORDS.forEach(function (w) { addSprite(w, true); });

  function resize() {
    var w = container.clientWidth || 1;
    var h = container.clientHeight || 1;
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    renderer.setSize(w, h);
  }
  resize();
  window.addEventListener("resize", function () {
    resize();
    if (reducedMotion) renderer.render(scene, camera);
  });

  var targetX = 0, targetY = 0;
  if (!reducedMotion) {
    window.addEventListener("mousemove", function (e) {
      targetX = (e.clientX / window.innerWidth - 0.5) * 2;
      targetY = (e.clientY / window.innerHeight - 0.5) * 2;
    }, { passive: true });
  }

  if (reducedMotion) {
    renderer.render(scene, camera);
    return;
  }

  var clock = new THREE.Clock();
  var BOUND_X = 14, BOUND_Y = 9;

  function animate() {
    requestAnimationFrame(animate);
    var dt = Math.min(clock.getDelta(), 0.05);
    var t = clock.elapsedTime;

    for (var i = 0; i < sprites.length; i++) {
      var s = sprites[i];
      var u = s.userData;
      s.position.x += u.vx * dt * 3;
      s.position.y += u.vy * dt * 3;
      s.position.x += Math.sin(t * u.wobbleSpeed + u.wobblePhase) * 0.002;
      s.material.rotation += u.spin * dt;

      if (s.position.y > BOUND_Y) s.position.y = -BOUND_Y;
      if (s.position.y < -BOUND_Y) s.position.y = BOUND_Y;
      if (s.position.x > BOUND_X) s.position.x = -BOUND_X;
      if (s.position.x < -BOUND_X) s.position.x = BOUND_X;
    }

    camera.position.x += (targetX * 1.2 - camera.position.x) * 0.04;
    camera.position.y += (-targetY * 0.8 - camera.position.y) * 0.04;
    camera.lookAt(0, 0, 0);

    renderer.render(scene, camera);
  }
  animate();
})();
</script>
</body>
</html>
""")

# Feature H2 uses {z} for the styled ぜんぶ span.
# Borrowed at build time from UIStrings.json: privacy, terms, next, restart, correct, wrong.
T = {
"en": dict(
    autonym="English",
    title="Japanese Daily 每日日本語 — Learn Japanese, a little every day",
    desc="Learn Japanese daily: all 50 Minna no Nihongo lessons, Hiragana & Katakana with native audio, quizzes and flashcards in 17 languages — free on iPhone & iPad.",
    kicker="a little every day",
    tagline="Complete vocabulary, Hiragana & Katakana tables, quizzes, listening practice and flashcards — all in one beautiful iOS app.",
    hero_alt="Screenshot of the Japanese Daily app showing Minna no Nihongo vocabulary and Hiragana practice",
    free_note="Free on iPhone & iPad",
    feat_h2="Everything you need, {z} in one app",
    feat_sub="From your very first あ to full Minna no Nihongo mastery — a focused daily companion.",
    f1t="50 Minna no Nihongo lessons",
    f1d="The complete vocabulary of all 50 lessons from the classic textbook — organised exactly the way you study.",
    f2t="Vocabulary in 17 languages",
    f2d="Learn in the language you think in — from English and 中文 to Tiếng Việt, Español and हिन्दी.",
    f3t="Kana tables with native audio",
    f3d="Every Hiragana and Katakana character voiced by native speakers. Tap, listen, repeat.",
    f4t="Quizzes & listening mode",
    f4d="Read and choose, or listen first and pick what you heard — two ways to make it stick.",
    f5t="Tinder-style flashcards",
    f5d="Swipe right if you know it, left if you don't. Reviewing has never felt this quick.",
    f6t="Write practice",
    f6d="Trace every kana with the correct stroke order until your hand remembers it too.",
    f7t="Today widget",
    f7d="A fresh word of the day on your Home Screen and Lock Screen — learn before you even unlock.",
    quiz_title="Try it: a Lesson 1 quiz",
    quiz_badge="Interactive — no download needed",
    quiz_sub="Real vocabulary from Minna no Nihongo Lesson 1 — right here in your browser.",
    q_prompt="What does this word mean?",
    q_score="You got {x} out of {y}!",
    q_pitch="Fun, right? Now put it in your pocket — all 50 lessons with audio, flashcards and listening quizzes. Learn Japanese anytime, anywhere.",
    cta_sub="Start your Japanese habit today. One word at a time.",
    lang_label="Language",
    rights="All rights reserved.",
    hero_alt2="Screenshot of the Japanese Daily app showing the interactive Hiragana and Katakana table",
    hero_alt3="Screenshot of the Japanese Daily app showing Tinder-style vocabulary flashcards",
    how_kicker="how it works",
    how_title="Three steps to your first real Japanese words",
    how_sub="No account, no setup — just open the app and start with today's kana or vocabulary.",
    how1t="1. Warm up with Kana",
    how1d="Learn Hiragana and Katakana with native audio, one character at a time, at your own pace.",
    how2t="2. Work through Minna no Nihongo",
    how2d="Pick a lesson and study its vocabulary with flashcards, quizzes and listening practice.",
    how3t="3. Build a daily habit",
    how3d="Check the Today widget each morning for a new word, and watch your progress bar fill up lesson by lesson.",
    faq_kicker="faq",
    faq_title="Frequently asked questions",
    faq_sub="Everything you might want to know before you start.",
    faq1q="Is Japanese Daily free?",
    faq1a="Yes. Hiragana and Katakana practice is free, and so are the first 5 Minna no Nihongo lessons. A one-time purchase or subscription unlocks all 50 lessons and removes ads.",
    faq2q="Do I need an internet connection?",
    faq2a="No. All vocabulary, kana tables and native audio are bundled with the app, so you can study offline on a plane, a train, or anywhere else.",
    faq3q="What languages are supported?",
    faq3a="Vocabulary and the app's own interface are both available in 17 languages, from English and Spanish to Vietnamese, Hindi and Korean — pick whichever you think in.",
    faq4q="Is this based on a real textbook?",
    faq4a="Yes. Japanese Daily follows Minna no Nihongo, one of the most widely used Japanese textbooks in classrooms worldwide, with all 50 lessons' vocabulary organised exactly as you'd study them in the book — a solid foundation before tackling JLPT-level study.",
),
"zh": dict(
    autonym="简体中文",
    title="Japanese Daily 每日日本語 — 每天学一点日语",
    desc="每天学日语：《大家的日本语》全50课词汇、17种语言释义、平假名片假名原声发音、测验、听力、闪卡与笔顺书写练习 —— iPhone 和 iPad 免费下载。",
    kicker="每天进步一点点",
    tagline="完整词汇、五十音图、测验、听力练习和闪卡 —— 尽在一款精美的 iOS 应用。",
    hero_alt="Japanese Daily 每日日本語应用截图，展示《大家的日本语》词汇学习画面",
    free_note="iPhone 和 iPad 免费下载",
    feat_h2="所需的一切，{z}都在一个应用里",
    feat_sub="从第一个「あ」到掌握《大家的日本语》全部词汇，每天陪你学习。",
    f1t="《大家的日本语》全50课",
    f1d="经典教材全部50课的完整词汇，编排与你的学习进度完全一致。",
    f2t="17种语言的词汇释义",
    f2d="用你最熟悉的语言学习 —— 中文、英语、越南语、西班牙语、印地语等。",
    f3t="五十音图与原声发音",
    f3d="每个平假名和片假名都由母语者朗读。点一下，听一听，跟着读。",
    f4t="测验与听力模式",
    f4d="看词选义，或先听音再选词 —— 两种方式加深记忆。",
    f5t="Tinder 式闪卡",
    f5d="认识就向右滑，不认识就向左滑。复习从未如此轻松。",
    f6t="书写练习",
    f6d="按正确笔顺描写每个假名，直到手也记住它。",
    f7t="今日小组件",
    f7d="主屏幕和锁屏上每天一个新单词 —— 解锁之前就能学习。",
    quiz_title="试一试：第1课小测验",
    quiz_badge="互动体验 — 无需下载",
    quiz_sub="《大家的日本语》第1课的真实词汇，就在浏览器里。",
    q_prompt="这个词是什么意思？",
    q_score="答对 {x} / {y} 题！",
    q_pitch="好玩吧？把它装进口袋 —— 全50课、原声发音、闪卡和听力测验，随时随地学日语。",
    cta_sub="今天就开始你的日语习惯，每天一个单词。",
    lang_label="语言",
    rights="保留所有权利。",
    hero_alt2="Japanese Daily 每日日本语应用截图，展示互动式五十音图表",
    hero_alt3="Japanese Daily 每日日本语应用截图，展示 Tinder 式词汇闪卡",
    how_kicker="使用方法",
    how_title="三步开启你的日语学习",
    how_sub="无需注册，无需设置——打开应用，从今天的假名或词汇开始。",
    how1t="1. 先热身：五十音图",
    how1d="跟着母语发音，一个一个学习平假名和片假名，按自己的节奏来。",
    how2t="2. 学习《大家的日本语》",
    how2d="选择一课，用闪卡、测验和听力练习巩固词汇。",
    how3t="3. 养成每天学习的习惯",
    how3d="每天早上看看今日小组件学一个新单词，看着进度条一课一课涨起来。",
    faq_kicker="常见问题",
    faq_title="常见问题解答",
    faq_sub="开始之前，你可能想知道的一切。",
    faq1q="Japanese Daily 免费吗？",
    faq1a="免费。五十音图练习完全免费，《大家的日本语》前5课也免费。一次性购买或订阅可解锁全部50课并去除广告。",
    faq2q="需要联网吗？",
    faq2a="不需要。所有词汇、假名表和原声发音都随应用内置，飞机上、地铁里、任何地方都能离线学习。",
    faq3q="支持哪些语言？",
    faq3a="词汇释义和应用界面均支持17种语言，从英语、西班牙语到越南语、印地语、韩语——选你最习惯的语言即可。",
    faq4q="这是基于真实教材的吗？",
    faq4a="是的。Japanese Daily 遵循《大家的日本语》——全球课堂上最广泛使用的日语教材之一，全50课词汇按书中顺序编排，为之后挑战JLPT打下坚实基础。",
),
"zh-Hant": dict(
    autonym="繁體中文",
    title="Japanese Daily 每日日本語 — 每天學一點日語",
    desc="每天學日語：《大家的日本語》全50課單字、17種語言釋義、平假名片假名原聲發音、測驗、聽力、單字卡與筆順書寫練習 —— iPhone 與 iPad 免費下載。",
    kicker="每天進步一點點",
    tagline="完整單字、五十音、測驗、聽力練習與單字卡 —— 全都在一款精美的 iOS App。",
    hero_alt="Japanese Daily 每日日本語 App 截圖，展示《大家的日本語》單字學習畫面",
    free_note="iPhone 與 iPad 免費下載",
    feat_h2="所需的一切，{z}都在一個 App",
    feat_sub="從第一個「あ」到掌握《大家的日本語》全部單字，每天陪你學習。",
    f1t="《大家的日本語》全50課",
    f1d="經典教材全部50課的完整單字，編排與你的學習進度完全一致。",
    f2t="17種語言的單字釋義",
    f2d="用你最熟悉的語言學習 —— 中文、英文、越南文、西班牙文、印地文等。",
    f3t="五十音與原聲發音",
    f3d="每個平假名與片假名都由母語者朗讀。點一下，聽一聽，跟著唸。",
    f4t="測驗與聽力模式",
    f4d="看字選義，或先聽音再選字 —— 兩種方式加深記憶。",
    f5t="Tinder 式單字卡",
    f5d="認識就向右滑，不認識就向左滑。複習從未如此輕鬆。",
    f6t="書寫練習",
    f6d="按正確筆順描寫每個假名，直到手也記住它。",
    f7t="今日小工具",
    f7d="主畫面與鎖定畫面每天一個新單字 —— 解鎖前就能學習。",
    quiz_title="試試看：第1課小測驗",
    quiz_badge="互動體驗 — 無需下載",
    quiz_sub="《大家的日本語》第1課的真實單字，就在瀏覽器裡。",
    q_prompt="這個字是什麼意思？",
    q_score="答對 {x} / {y} 題！",
    q_pitch="好玩吧？把它裝進口袋 —— 全50課、原聲發音、單字卡與聽力測驗，隨時隨地學日語。",
    cta_sub="今天就開始你的日語習慣，每天一個單字。",
    lang_label="語言",
    rights="版權所有。",
    hero_alt2="Japanese Daily 每日日本語 App 截圖，展示互動式五十音表",
    hero_alt3="Japanese Daily 每日日本語 App 截圖，展示 Tinder 式單字卡",
    how_kicker="使用方法",
    how_title="三步開始你的日語學習",
    how_sub="不用註冊、不用設定——打開 App，從今天的假名或單字開始。",
    how1t="1. 先熱身：五十音",
    how1d="跟著母語發音，一個一個學習平假名和片假名，按自己的節奏來。",
    how2t="2. 學習《大家的日本語》",
    how2d="選一課，用單字卡、測驗和聽力練習來鞏固單字。",
    how3t="3. 養成每天學習的習慣",
    how3d="每天早上看看今日小工具學一個新單字，看著進度條一課一課往上漲。",
    faq_kicker="常見問題",
    faq_title="常見問題解答",
    faq_sub="開始之前，你可能想知道的一切。",
    faq1q="Japanese Daily 免費嗎？",
    faq1a="免費。五十音練習完全免費，《大家的日本語》前5課也免費。一次性購買或訂閱可解鎖全部50課並移除廣告。",
    faq2q="需要網路連線嗎？",
    faq2a="不需要。所有單字、假名表和原聲發音都內建在 App 裡，飛機上、捷運上、任何地方都能離線學習。",
    faq3q="支援哪些語言？",
    faq3a="單字釋義和 App 介面都支援17種語言，從英文、西班牙文到越南文、印地文、韓文——選你最習慣的語言就好。",
    faq4q="這是根據真實教材做的嗎？",
    faq4a="是的。Japanese Daily 依循《大家的日本語》——全球課堂上最廣泛使用的日語教材之一，全50課單字按書中順序編排，為之後挑戰JLPT打好基礎。",
),
"vi": dict(
    autonym="Tiếng Việt",
    title="Japanese Daily 每日日本語 — Học tiếng Nhật mỗi ngày một chút",
    desc="Học tiếng Nhật mỗi ngày: 50 bài Minna no Nihongo, Hiragana & Katakana với giọng bản xứ, kiểm tra và thẻ ghi nhớ trong 17 ngôn ngữ — miễn phí trên iPhone & iPad.",
    kicker="mỗi ngày một chút",
    tagline="Từ vựng đầy đủ, bảng Kana, kiểm tra, luyện nghe và thẻ ghi nhớ — tất cả trong một ứng dụng iOS tuyệt đẹp.",
    hero_alt="Ảnh chụp màn hình ứng dụng Japanese Daily hiển thị từ vựng Minna no Nihongo",
    free_note="Miễn phí trên iPhone & iPad",
    feat_h2="Mọi thứ bạn cần, {z} trong một ứng dụng",
    feat_sub="Từ chữ あ đầu tiên đến khi thành thạo toàn bộ Minna no Nihongo — người bạn đồng hành mỗi ngày.",
    f1t="Trọn bộ 50 bài Minna no Nihongo",
    f1d="Toàn bộ từ vựng của 50 bài trong giáo trình kinh điển, sắp xếp đúng theo cách bạn học.",
    f2t="Từ vựng trong 17 ngôn ngữ",
    f2d="Học bằng ngôn ngữ bạn quen thuộc nhất — tiếng Việt, tiếng Anh, tiếng Trung, tiếng Tây Ban Nha và nhiều hơn nữa.",
    f3t="Bảng Kana với giọng bản xứ",
    f3d="Mỗi chữ Hiragana và Katakana đều do người bản xứ đọc. Chạm, nghe, lặp lại.",
    f4t="Kiểm tra & chế độ luyện nghe",
    f4d="Đọc rồi chọn, hoặc nghe trước rồi chọn từ bạn nghe được — hai cách để nhớ lâu.",
    f5t="Thẻ ghi nhớ kiểu Tinder",
    f5d="Vuốt phải nếu bạn biết, vuốt trái nếu chưa. Ôn tập chưa bao giờ nhanh đến thế.",
    f6t="Luyện viết",
    f6d="Tô từng chữ kana theo đúng thứ tự nét cho đến khi tay bạn cũng nhớ.",
    f7t="Tiện ích Hôm nay",
    f7d="Mỗi ngày một từ mới ngay trên Màn hình chính và Màn hình khóa — học trước cả khi mở khóa.",
    quiz_title="Thử ngay: bài kiểm tra Bài 1",
    quiz_badge="Tương tác — không cần tải app",
    quiz_sub="Từ vựng thật của Bài 1 Minna no Nihongo — ngay trong trình duyệt.",
    q_prompt="Từ này nghĩa là gì?",
    q_score="Bạn đúng {x}/{y} câu!",
    q_pitch="Vui chứ? Hãy bỏ nó vào túi — đủ 50 bài với âm thanh, thẻ ghi nhớ và luyện nghe. Học tiếng Nhật mọi lúc, mọi nơi.",
    cta_sub="Bắt đầu thói quen tiếng Nhật ngay hôm nay. Mỗi ngày một từ.",
    lang_label="Ngôn ngữ",
    rights="Bảo lưu mọi quyền.",
    hero_alt2="Ảnh chụp màn hình ứng dụng Japanese Daily hiển thị bảng Hiragana và Katakana tương tác",
    hero_alt3="Ảnh chụp màn hình ứng dụng Japanese Daily hiển thị thẻ ghi nhớ từ vựng kiểu Tinder",
    how_kicker="cách hoạt động",
    how_title="Ba bước để có những từ tiếng Nhật thật đầu tiên",
    how_sub="Không cần đăng ký, không cần cài đặt — chỉ cần mở ứng dụng và bắt đầu với kana hoặc từ vựng hôm nay.",
    how1t="1. Khởi động với Kana",
    how1d="Học Hiragana và Katakana với giọng bản xứ, từng chữ một, theo nhịp độ của riêng bạn.",
    how2t="2. Học theo Minna no Nihongo",
    how2d="Chọn một bài học và ôn từ vựng bằng thẻ ghi nhớ, kiểm tra và luyện nghe.",
    how3t="3. Xây dựng thói quen mỗi ngày",
    how3d="Mỗi sáng xem tiện ích Hôm nay để học một từ mới, và nhìn thanh tiến độ đầy lên theo từng bài.",
    faq_kicker="hỏi đáp",
    faq_title="Câu hỏi thường gặp",
    faq_sub="Mọi điều bạn cần biết trước khi bắt đầu.",
    faq1q="Japanese Daily có miễn phí không?",
    faq1a="Có. Luyện Hiragana và Katakana hoàn toàn miễn phí, cùng với 5 bài học đầu của Minna no Nihongo. Mua một lần hoặc đăng ký để mở khóa toàn bộ 50 bài và loại bỏ quảng cáo.",
    faq2q="Tôi có cần kết nối internet không?",
    faq2a="Không. Toàn bộ từ vựng, bảng kana và âm thanh bản xứ đều có sẵn trong ứng dụng, nên bạn có thể học offline trên máy bay, tàu điện, hay bất cứ đâu.",
    faq3q="Ứng dụng hỗ trợ ngôn ngữ nào?",
    faq3a="Cả từ vựng và giao diện ứng dụng đều có sẵn trong 17 ngôn ngữ, từ tiếng Anh, tiếng Tây Ban Nha đến tiếng Việt, tiếng Hindi và tiếng Hàn — chọn ngôn ngữ bạn quen thuộc nhất.",
    faq4q="Ứng dụng có dựa trên giáo trình thật không?",
    faq4a="Có. Japanese Daily theo sát Minna no Nihongo, một trong những giáo trình tiếng Nhật được dùng rộng rãi nhất trên thế giới, với từ vựng cả 50 bài được sắp xếp đúng như trong sách — nền tảng vững chắc trước khi luyện thi JLPT.",
),
"de": dict(
    autonym="Deutsch",
    title="Japanese Daily 每日日本語 — Jeden Tag ein bisschen Japanisch",
    desc="Jeden Tag Japanisch lernen: 50 Lektionen Minna no Nihongo, Hiragana & Katakana mit Audio, Quiz und Karteikarten in 17 Sprachen — kostenlos für iPhone & iPad.",
    kicker="jeden Tag ein bisschen",
    tagline="Vollständiger Wortschatz, Kana-Tabellen, Quiz, Hörübungen und Karteikarten — alles in einer schönen iOS-App.",
    hero_alt="Screenshot der Japanese-Daily-App mit Minna-no-Nihongo-Vokabeln",
    free_note="Kostenlos für iPhone & iPad",
    feat_h2="Alles, was du brauchst — {z} in einer App",
    feat_sub="Vom allerersten あ bis zur kompletten Minna-no-Nihongo-Meisterschaft — dein täglicher Begleiter.",
    f1t="50 Lektionen Minna no Nihongo",
    f1d="Der komplette Wortschatz aller 50 Lektionen des Klassikers — genau so gegliedert, wie du lernst.",
    f2t="Vokabeln in 17 Sprachen",
    f2d="Lerne in der Sprache, in der du denkst — von Deutsch und Englisch bis 中文 und हिन्दी.",
    f3t="Kana-Tabellen mit nativem Audio",
    f3d="Jedes Hiragana und Katakana von Muttersprachlern gesprochen. Tippen, hören, nachsprechen.",
    f4t="Quiz & Hörmodus",
    f4d="Lesen und auswählen — oder erst hören und dann das richtige Wort wählen. Zwei Wege, damit es sitzt.",
    f5t="Karteikarten im Tinder-Stil",
    f5d="Nach rechts wischen, wenn du es kannst, nach links, wenn nicht. Wiederholen war nie so schnell.",
    f6t="Schreibübungen",
    f6d="Zeichne jedes Kana in der richtigen Strichfolge nach, bis auch deine Hand es sich merkt.",
    f7t="Heute-Widget",
    f7d="Jeden Tag ein neues Wort auf Home- und Sperrbildschirm — lernen, noch bevor du entsperrst.",
    quiz_title="Probier's aus: Quiz zu Lektion 1",
    quiz_badge="Interaktiv — keine Installation nötig",
    quiz_sub="Echte Vokabeln aus Lektion 1 von Minna no Nihongo — direkt im Browser.",
    q_prompt="Was bedeutet dieses Wort?",
    q_score="{x} von {y} richtig!",
    q_pitch="Macht Spaß, oder? Steck es in deine Tasche — alle 50 Lektionen mit Audio, Karteikarten und Hörquiz. Japanisch lernen, jederzeit und überall.",
    cta_sub="Starte heute deine Japanisch-Gewohnheit. Ein Wort nach dem anderen.",
    lang_label="Sprache",
    rights="Alle Rechte vorbehalten.",
    hero_alt2="Screenshot der Japanese-Daily-App mit der interaktiven Hiragana- und Katakana-Tabelle",
    hero_alt3="Screenshot der Japanese-Daily-App mit Vokabel-Karteikarten im Tinder-Stil",
    how_kicker="so funktioniert's",
    how_title="Drei Schritte zu deinen ersten echten japanischen Wörtern",
    how_sub="Kein Konto, keine Einrichtung — einfach die App öffnen und mit der Kana- oder Vokabel-Übung von heute starten.",
    how1t="1. Aufwärmen mit Kana",
    how1d="Lerne Hiragana und Katakana mit muttersprachlichem Audio, Zeichen für Zeichen, in deinem eigenen Tempo.",
    how2t="2. Minna no Nihongo durcharbeiten",
    how2d="Wähle eine Lektion und übe ihren Wortschatz mit Karteikarten, Quiz und Hörübungen.",
    how3t="3. Eine tägliche Gewohnheit aufbauen",
    how3d="Schau jeden Morgen im Heute-Widget nach einem neuen Wort und sieh, wie sich dein Fortschrittsbalken Lektion für Lektion füllt.",
    faq_kicker="häufige fragen",
    faq_title="Häufig gestellte Fragen",
    faq_sub="Alles, was du vor dem Start wissen möchtest.",
    faq1q="Ist Japanese Daily kostenlos?",
    faq1a="Ja. Hiragana- und Katakana-Übungen sind kostenlos, genauso wie die ersten 5 Lektionen von Minna no Nihongo. Ein einmaliger Kauf oder ein Abo schaltet alle 50 Lektionen frei und entfernt Werbung.",
    faq2q="Brauche ich eine Internetverbindung?",
    faq2a="Nein. Alle Vokabeln, Kana-Tabellen und das muttersprachliche Audio sind in der App enthalten — du kannst also offline lernen, im Flugzeug, im Zug oder überall sonst.",
    faq3q="Welche Sprachen werden unterstützt?",
    faq3a="Sowohl der Wortschatz als auch die App-Oberfläche selbst sind in 17 Sprachen verfügbar, von Englisch und Spanisch bis Vietnamesisch, Hindi und Koreanisch — wähle einfach die Sprache, in der du denkst.",
    faq4q="Basiert das auf einem echten Lehrbuch?",
    faq4a="Ja. Japanese Daily folgt Minna no Nihongo, einem der weltweit meistgenutzten Lehrbücher für Japanisch, mit dem Wortschatz aller 50 Lektionen genau so geordnet wie im Buch — eine solide Grundlage, bevor es an JLPT-Niveau geht.",
),
"th": dict(
    autonym="ไทย",
    title="Japanese Daily 每日日本語 — เรียนภาษาญี่ปุ่นวันละนิด",
    desc="เรียนภาษาญี่ปุ่นทุกวัน: 50 บท Minna no Nihongo ฮิรางานะ-คาตาคานะพร้อมเสียงเจ้าของภาษา แบบทดสอบและบัตรคำใน 17 ภาษา — ฟรีบน iPhone และ iPad",
    kicker="วันละนิดทุกวัน",
    tagline="คำศัพท์ครบชุด ตารางคานะ แบบทดสอบ ฝึกฟัง และบัตรคำ — ครบในแอป iOS ที่สวยงามแอปเดียว",
    hero_alt="ภาพหน้าจอแอป Japanese Daily แสดงคำศัพท์ Minna no Nihongo",
    free_note="ฟรีบน iPhone และ iPad",
    feat_h2="ทุกอย่างที่ต้องใช้ {z} ในแอปเดียว",
    feat_sub="จาก あ ตัวแรกจนเชี่ยวชาญ Minna no Nihongo ทั้งเล่ม — เพื่อนคู่ใจที่อยู่กับคุณทุกวัน",
    f1t="Minna no Nihongo ครบ 50 บท",
    f1d="คำศัพท์ครบถ้วนทั้ง 50 บทจากตำราคลาสสิก จัดเรียงตรงตามที่คุณเรียน",
    f2t="คำศัพท์ใน 17 ภาษา",
    f2d="เรียนด้วยภาษาที่คุณคิด — ไทย อังกฤษ จีน สเปน และอีกมากมาย",
    f3t="ตารางคานะพร้อมเสียงเจ้าของภาษา",
    f3d="ฮิรางานะและคาตาคานะทุกตัวออกเสียงโดยเจ้าของภาษา แตะ ฟัง แล้วพูดตาม",
    f4t="แบบทดสอบและโหมดการฟัง",
    f4d="อ่านแล้วเลือก หรือฟังก่อนแล้วเลือกคำที่ได้ยิน — สองวิธีให้จำได้แม่น",
    f5t="บัตรคำสไตล์ Tinder",
    f5d="รู้ก็ปัดขวา ไม่รู้ก็ปัดซ้าย ทบทวนได้เร็วอย่างที่ไม่เคยเป็นมาก่อน",
    f6t="ฝึกเขียน",
    f6d="เขียนคานะทุกตัวตามลำดับขีดที่ถูกต้อง จนมือของคุณก็จำได้",
    f7t="วิดเจ็ต Today",
    f7d="คำใหม่ทุกวันบนหน้าจอโฮมและหน้าจอล็อก — เรียนได้ก่อนปลดล็อกเสียอีก",
    quiz_title="ลองเลย: แบบทดสอบบทที่ 1",
    quiz_badge="โต้ตอบได้ — ไม่ต้องติดตั้งแอป",
    quiz_sub="คำศัพท์จริงจากบทที่ 1 ของ Minna no Nihongo — ทดลองได้ในเบราว์เซอร์",
    q_prompt="คำนี้แปลว่าอะไร",
    q_score="ตอบถูก {x} จาก {y} ข้อ!",
    q_pitch="สนุกใช่ไหม พกไว้ในกระเป๋าเลย — ครบ 50 บทพร้อมเสียง บัตรคำ และแบบทดสอบการฟัง เรียนภาษาญี่ปุ่นได้ทุกที่ทุกเวลา",
    cta_sub="เริ่มนิสัยเรียนภาษาญี่ปุ่นวันนี้ วันละหนึ่งคำ",
    lang_label="ภาษา",
    rights="สงวนลิขสิทธิ์",
    hero_alt2="ภาพหน้าจอแอป Japanese Daily แสดงตารางฮิรางานะและคาตาคานะแบบอินเทอร์แอกทีฟ",
    hero_alt3="ภาพหน้าจอแอป Japanese Daily แสดงบัตรคำศัพท์สไตล์ Tinder",
    how_kicker="วิธีใช้งาน",
    how_title="สามขั้นตอนสู่คำศัพท์ญี่ปุ่นแรกของคุณ",
    how_sub="ไม่ต้องสมัครสมาชิก ไม่ต้องตั้งค่า — เปิดแอปแล้วเริ่มจากคานะหรือคำศัพท์ของวันนี้ได้เลย",
    how1t="1. วอร์มอัพด้วยคานะ",
    how1d="เรียนฮิรางานะและคาตาคานะพร้อมเสียงเจ้าของภาษา ทีละตัวตามจังหวะของคุณเอง",
    how2t="2. เรียน Minna no Nihongo ทีละบท",
    how2d="เลือกบทเรียนแล้วฝึกคำศัพท์ด้วยบัตรคำ แบบทดสอบ และการฝึกฟัง",
    how3t="3. สร้างนิสัยเรียนทุกวัน",
    how3d="เช็กวิดเจ็ต Today ทุกเช้าเพื่อเรียนคำใหม่ และดูแถบความคืบหน้าเติมขึ้นทีละบท",
    faq_kicker="คำถามที่พบบ่อย",
    faq_title="คำถามที่พบบ่อย",
    faq_sub="ทุกอย่างที่คุณอาจอยากรู้ก่อนเริ่มใช้งาน",
    faq1q="Japanese Daily ฟรีไหม",
    faq1a="ฟรี ฝึกฮิรางานะและคาตาคานะได้โดยไม่มีค่าใช้จ่าย และ Minna no Nihongo 5 บทแรกก็ฟรีเช่นกัน ซื้อครั้งเดียวหรือสมัครสมาชิกเพื่อปลดล็อกครบ 50 บทและไม่มีโฆษณา",
    faq2q="ต้องต่ออินเทอร์เน็ตไหม",
    faq2a="ไม่ต้อง คำศัพท์ ตารางคานะ และเสียงเจ้าของภาษาทั้งหมดอยู่ในแอปแล้ว จึงเรียนแบบออฟไลน์ได้ทั้งบนเครื่องบิน รถไฟ หรือที่ไหนก็ได้",
    faq3q="รองรับภาษาอะไรบ้าง",
    faq3a="ทั้งคำศัพท์และหน้าตาแอปรองรับ 17 ภาษา ตั้งแต่อังกฤษ สเปน ไปจนถึงเวียดนาม ฮินดี และเกาหลี — เลือกภาษาที่คุณคิดได้เลย",
    faq4q="แอปนี้อ้างอิงจากตำราจริงหรือไม่",
    faq4a="ใช่ Japanese Daily อ้างอิงจาก Minna no Nihongo ตำราภาษาญี่ปุ่นที่ใช้กันแพร่หลายที่สุดในห้องเรียนทั่วโลก โดยจัดคำศัพท์ครบ 50 บทตามลำดับในหนังสือ — พื้นฐานที่มั่นคงก่อนไปลุยระดับ JLPT",
),
"my": dict(
    autonym="မြန်မာ",
    title="Japanese Daily 每日日本語 — နေ့စဉ် ဂျပန်စာ နည်းနည်းစီ",
    desc="နေ့တိုင်း ဂျပန်စာလေ့လာပါ — Minna no Nihongo သင်ခန်းစာ ၅၀၊ မူရင်းအသံပါ ဟီရာဂနာ/ခတခနာ၊ ဘာသာစကား ၁၇ မျိုးဖြင့် ဉာဏ်စမ်းနှင့်ကတ်ပြားများ — iPhone/iPad တွင် အခမဲ့။",
    kicker="နေ့တိုင်း နည်းနည်းစီ",
    tagline="ဝေါဟာရအပြည့်အစုံ၊ ကာနာဇယား၊ ဉာဏ်စမ်း၊ နားထောင်လေ့ကျင့်ခန်းနှင့် ကတ်ပြားများ — လှပသော iOS အက်ပ်တစ်ခုတည်းတွင်။",
    hero_alt="Japanese Daily အက်ပ်၏ Minna no Nihongo ဝေါဟာရသင်ကြားမှု မျက်နှာပြင်ဓာတ်ပုံ",
    free_note="iPhone နှင့် iPad တွင် အခမဲ့",
    feat_h2="လိုအပ်သမျှ {z} အက်ပ်တစ်ခုတည်းမှာ",
    feat_sub="ပထမဆုံး あ မှစ၍ Minna no Nihongo တစ်အုပ်လုံး ကျွမ်းကျင်သည်အထိ — နေ့စဉ် အဖော်မွန်။",
    f1t="Minna no Nihongo သင်ခန်းစာ ၅၀",
    f1d="ဂန္ထဝင်ကျမ်း၏ သင်ခန်းစာ ၅၀ လုံး၏ ဝေါဟာရ အပြည့်အစုံ — သင်လေ့လာသည့်အတိုင်း စီစဉ်ထား။",
    f2t="ဘာသာစကား ၁၇ မျိုးဖြင့် ဝေါဟာရ",
    f2d="သင်စဉ်းစားသည့် ဘာသာစကားဖြင့် လေ့လာပါ — မြန်မာ၊ အင်္ဂလိပ်၊ တရုတ် စသည်။",
    f3t="မူရင်းအသံပါ ကာနာဇယားများ",
    f3d="ဟီရာဂနာနှင့် ခတခနာ စာလုံးတိုင်းကို မူရင်းဘာသာစကားပြောသူများ အသံထွက်ပေးထား။ တို့၊ နားထောင်၊ လိုက်ဆို။",
    f4t="ဉာဏ်စမ်းနှင့် နားထောင်မုဒ်",
    f4d="ဖတ်ပြီးရွေး သို့မဟုတ် အရင်နားထောင်ပြီး ကြားသည့်စကားလုံးကို ရွေး — မှတ်မိစေရန် နည်းနှစ်မျိုး။",
    f5t="Tinder ပုံစံ ကတ်ပြားများ",
    f5d="သိရင် ညာဘက်ပွတ်ဆွဲ၊ မသိရင် ဘယ်ဘက်။ ပြန်လေ့လာခြင်း ဒီထက်မြန်ဖူးမရှိ။",
    f6t="ရေးလေ့ကျင့်ခန်း",
    f6d="ကာနာစာလုံးတိုင်းကို မှန်ကန်သော စာလုံးရေးအစဉ်အတိုင်း လက်ကမှတ်မိသည်အထိ ရေးလေ့ကျင့်ပါ။",
    f7t="Today ဝိဂျက်",
    f7d="Home Screen နှင့် Lock Screen ပေါ်တွင် နေ့စဉ် စကားလုံးအသစ် — ဖုန်းမဖွင့်ခင်ကတည်းက လေ့လာနိုင်။",
    quiz_title="စမ်းကြည့်ပါ — သင်ခန်းစာ ၁ ဉာဏ်စမ်း",
    quiz_badge="အပြန်အလှန်တုံ့ပြန်နိုင်သည် — အက်ပ်ဒေါင်းလုဒ်မလိုပါ",
    quiz_sub="Minna no Nihongo သင်ခန်းစာ ၁ မှ စစ်မှန်သော ဝေါဟာရများ — ဘရောက်ဇာထဲမှာပင်။",
    q_prompt="ဤစကားလုံး၏ အဓိပ္ပာယ်က ဘာလဲ။",
    q_score="{y} ခုမှ {x} ခု မှန်သည်!",
    q_pitch="ပျော်စရာကောင်းတယ်နော်။ အိတ်ကပ်ထဲ ထည့်ထားလိုက်ပါ — အသံပါ သင်ခန်းစာ ၅၀ လုံး၊ ကတ်ပြားများနှင့် နားထောင်ဉာဏ်စမ်း။ ဂျပန်စာကို ဘယ်အချိန်ဘယ်နေရာမဆို လေ့လာပါ။",
    cta_sub="ဒီနေ့ပဲ ဂျပန်စာ အလေ့အထ စတင်ပါ။ တစ်နေ့ တစ်လုံးစီ။",
    lang_label="ဘာသာစကား",
    rights="မူပိုင်ခွင့် အားလုံး လက်ဝယ်ရှိသည်။",
    hero_alt2="Japanese Daily အက်ပ်၏ အပြန်အလှန် ဟီရာဂနာ/ခတခနာ ဇယား မျက်နှာပြင်ဓာတ်ပုံ",
    hero_alt3="Japanese Daily အက်ပ်၏ Tinder ပုံစံ ဝေါဟာရ ကတ်ပြား မျက်နှာပြင်ဓာတ်ပုံ",
    how_kicker="အသုံးပြုပုံ",
    how_title="ပထမဆုံး ဂျပန်စကားလုံးများအတွက် အဆင့်သုံးဆင့်",
    how_sub="အကောင့်ဖွင့်ရန် မလို၊ စနစ်ထူထောင်ရန် မလို — အက်ပ်ကိုဖွင့်၍ ယနေ့၏ ကာနာ သို့မဟုတ် ဝေါဟာရဖြင့် စတင်ပါ။",
    how1t="၁။ ကာနာဖြင့် အလေးမှုပေးပါ",
    how1d="မူရင်းအသံဖြင့် ဟီရာဂနာနှင့် ခတခနာကို တစ်လုံးချင်း၊ သင့်ကိုယ်ပိုင်နှုန်းဖြင့် လေ့လာပါ။",
    how2t="၂။ Minna no Nihongo အတိုင်း လေ့လာပါ",
    how2d="သင်ခန်းစာတစ်ခုရွေးပြီး ကတ်ပြား၊ ဉာဏ်စမ်းနှင့် နားထောင်လေ့ကျင့်ခန်းဖြင့် ဝေါဟာရကို ပြန်လည်လေ့ကျင့်ပါ။",
    how3t="၃။ နေ့စဉ် အလေ့အထ တည်ဆောက်ပါ",
    how3d="နံနက်တိုင်း Today ဝိဂျက်ကို ကြည့်ပြီး စကားလုံးအသစ်ကို လေ့လာပါ၊ တိုးတက်မှုဘားကို သင်ခန်းစာအလိုက် ပြည့်လာသည်ကို ကြည့်ပါ။",
    faq_kicker="မေးလေ့ရှိသောမေးခွန်းများ",
    faq_title="မေးလေ့ရှိသောမေးခွန်းများ",
    faq_sub="စတင်မလုပ်မီ သင်သိချင်နိုင်သည့် အရာအားလုံး။",
    faq1q="Japanese Daily အခမဲ့လား။",
    faq1a="ဟုတ်ကဲ့။ ဟီရာဂနာနှင့် ခတခနာ လေ့ကျင့်ခန်းကို အခမဲ့ လုပ်နိုင်ပြီး Minna no Nihongo ပထမ ၅ သင်ခန်းစာလည်း အခမဲ့ဖြစ်သည်။ တစ်ကြိမ်ဝယ်ခြင်း သို့မဟုတ် စာရင်းသွင်းခြင်းဖြင့် သင်ခန်းစာ ၅၀ လုံးကို ဖွင့်ပြီး ကြော်ငြာများကို ဖယ်ရှားနိုင်သည်။",
    faq2q="အင်တာနက် ချိတ်ဆက်ရန် လိုသလား။",
    faq2a="မလိုပါ။ ဝေါဟာရ၊ ကာနာဇယားနှင့် မူရင်းအသံ အားလုံးကို အက်ပ်ထဲတွင် ထည့်သွင်းထားသောကြောင့် လေယာဉ်ပေါ်၊ ရထားပေါ် သို့မဟုတ် မည်သည့်နေရာတွင်မဆို အော့ဖ်လိုင်း လေ့လာနိုင်သည်။",
    faq3q="မည်သည့် ဘာသာစကားများကို ပံ့ပိုးပေးသနည်း။",
    faq3a="ဝေါဟာရနှင့် အက်ပ်၏ ဒီဇိုင်းကိုယ်တိုင် ဘာသာစကား ၁၇ မျိုးဖြင့် ရနိုင်သည် — အင်္ဂလိပ်၊ စပိန်မှ ဗီယက်နမ်၊ ဟိန္ဒီနှင့် ကိုရီးယားအထိ — သင်စဉ်းစားသည့် ဘာသာစကားကို ရွေးလိုက်ပါ။",
    faq4q="ဒါက အစစ်အမှန် စာအုပ်ပေါ် အခြေခံသလား။",
    faq4a="ဟုတ်ကဲ့။ Japanese Daily သည် ကမ္ဘာတစ်ဝှမ်း စာသင်ခန်းများတွင် အသုံးအများဆုံး ဂျပန်စာသင်ကြားစာအုပ်များထဲမှ တစ်ခုဖြစ်သော Minna no Nihongo ကို လိုက်နာထားပြီး၊ သင်ခန်းစာ ၅၀ လုံး၏ ဝေါဟာရကို စာအုပ်အတိုင်းစီစဉ်ထားသည် — JLPT အဆင့် လေ့လာမီ ခိုင်မာသော အခြေခံတစ်ခု ဖြစ်သည်။",
),
"es": dict(
    autonym="Español",
    title="Japanese Daily 每日日本語 — Aprende japonés, un poco cada día",
    desc="Aprende japonés cada día: 50 lecciones de Minna no Nihongo, Hiragana y Katakana con audio nativo, tests y tarjetas en 17 idiomas — gratis en iPhone y iPad.",
    kicker="un poco cada día",
    tagline="Vocabulario completo, tablas de kana, tests, práctica de escucha y tarjetas — todo en una preciosa app para iOS.",
    hero_alt="Captura de pantalla de la app Japanese Daily mostrando vocabulario de Minna no Nihongo",
    free_note="Gratis en iPhone y iPad",
    feat_h2="Todo lo que necesitas, {z} en una sola app",
    feat_sub="Desde tu primer あ hasta dominar todo Minna no Nihongo — tu compañero de estudio diario.",
    f1t="50 lecciones de Minna no Nihongo",
    f1d="El vocabulario completo de las 50 lecciones del libro clásico, organizado tal y como estudias.",
    f2t="Vocabulario en 17 idiomas",
    f2d="Aprende en el idioma en el que piensas — español, inglés, 中文, français y más.",
    f3t="Tablas de kana con audio nativo",
    f3d="Cada hiragana y katakana con voz de hablantes nativos. Toca, escucha, repite.",
    f4t="Tests y modo de escucha",
    f4d="Lee y elige, o escucha primero y elige lo que oíste — dos formas de que se te quede.",
    f5t="Tarjetas estilo Tinder",
    f5d="Desliza a la derecha si la sabes, a la izquierda si no. Repasar nunca fue tan rápido.",
    f6t="Práctica de escritura",
    f6d="Traza cada kana con el orden de trazos correcto hasta que tu mano también lo recuerde.",
    f7t="Widget de Hoy",
    f7d="Una palabra nueva cada día en tu pantalla de inicio y de bloqueo — aprende antes de desbloquear.",
    quiz_title="Pruébalo: test de la Lección 1",
    quiz_badge="Interactivo — sin descargar nada",
    quiz_sub="Vocabulario real de la Lección 1 de Minna no Nihongo — aquí, en tu navegador.",
    q_prompt="¿Qué significa esta palabra?",
    q_score="¡{x} de {y} correctas!",
    q_pitch="Divertido, ¿verdad? Llévalo en el bolsillo: las 50 lecciones con audio, tarjetas y tests de escucha. Aprende japonés en cualquier momento y lugar.",
    cta_sub="Empieza hoy tu hábito de japonés. Una palabra cada vez.",
    lang_label="Idioma",
    rights="Todos los derechos reservados.",
    hero_alt2="Captura de pantalla de la app Japanese Daily mostrando la tabla interactiva de Hiragana y Katakana",
    hero_alt3="Captura de pantalla de la app Japanese Daily mostrando tarjetas de vocabulario estilo Tinder",
    how_kicker="cómo funciona",
    how_title="Tres pasos para tus primeras palabras en japonés",
    how_sub="Sin cuenta, sin configuración: abre la app y empieza con el kana o el vocabulario de hoy.",
    how1t="1. Calienta con el Kana",
    how1d="Aprende Hiragana y Katakana con audio nativo, carácter a carácter, a tu propio ritmo.",
    how2t="2. Avanza con Minna no Nihongo",
    how2d="Elige una lección y repasa su vocabulario con tarjetas, tests y práctica de escucha.",
    how3t="3. Crea un hábito diario",
    how3d="Consulta el widget de Hoy cada mañana para una palabra nueva y mira cómo se llena tu barra de progreso lección a lección.",
    faq_kicker="preguntas frecuentes",
    faq_title="Preguntas frecuentes",
    faq_sub="Todo lo que querrías saber antes de empezar.",
    faq1q="¿Japanese Daily es gratis?",
    faq1a="Sí. La práctica de Hiragana y Katakana es gratuita, igual que las primeras 5 lecciones de Minna no Nihongo. Una compra única o una suscripción desbloquea las 50 lecciones y elimina los anuncios.",
    faq2q="¿Necesito conexión a internet?",
    faq2a="No. Todo el vocabulario, las tablas de kana y el audio nativo vienen incluidos en la app, así que puedes estudiar sin conexión en un avión, un tren o donde sea.",
    faq3q="¿Qué idiomas admite?",
    faq3a="Tanto el vocabulario como la interfaz de la app están disponibles en 17 idiomas, desde inglés y español hasta vietnamita, hindi y coreano — elige el idioma en el que piensas.",
    faq4q="¿Se basa en un libro de texto real?",
    faq4a="Sí. Japanese Daily sigue Minna no Nihongo, uno de los manuales de japonés más usados en aulas de todo el mundo, con el vocabulario de las 50 lecciones organizado tal cual aparece en el libro — una base sólida antes de abordar el nivel JLPT.",
),
"fr": dict(
    autonym="Français",
    title="Japanese Daily 每日日本語 — Apprenez le japonais, un peu chaque jour",
    desc="Apprenez le japonais avec Minna no Nihongo : 50 leçons, Hiragana/Katakana en audio natif, quiz et cartes mémo, en 17 langues — gratuit sur iPhone et iPad.",
    kicker="un peu chaque jour",
    tagline="Vocabulaire complet, tableaux de kana, quiz, écoute et cartes mémo — le tout dans une belle app iOS.",
    hero_alt="Capture d'écran de l'application Japanese Daily montrant le vocabulaire de Minna no Nihongo",
    free_note="Gratuit sur iPhone et iPad",
    feat_h2="Tout ce qu'il vous faut, {z} dans une seule app",
    feat_sub="De votre tout premier あ à la maîtrise complète de Minna no Nihongo — votre compagnon d'étude quotidien.",
    f1t="Les 50 leçons de Minna no Nihongo",
    f1d="Le vocabulaire complet des 50 leçons du manuel classique, organisé exactement comme vous étudiez.",
    f2t="Du vocabulaire en 17 langues",
    f2d="Apprenez dans la langue dans laquelle vous pensez — français, anglais, 中文, español et plus.",
    f3t="Tableaux de kana avec audio natif",
    f3d="Chaque hiragana et katakana prononcé par des locuteurs natifs. Touchez, écoutez, répétez.",
    f4t="Quiz et mode écoute",
    f4d="Lisez et choisissez, ou écoutez d'abord puis choisissez ce que vous avez entendu — deux façons de mémoriser.",
    f5t="Cartes mémo façon Tinder",
    f5d="Glissez à droite si vous savez, à gauche sinon. Réviser n'a jamais été aussi rapide.",
    f6t="Entraînement à l'écriture",
    f6d="Tracez chaque kana dans le bon ordre des traits, jusqu'à ce que votre main s'en souvienne aussi.",
    f7t="Widget Aujourd'hui",
    f7d="Un nouveau mot chaque jour sur l'écran d'accueil et l'écran verrouillé — apprenez avant même de déverrouiller.",
    quiz_title="Essayez : le quiz de la leçon 1",
    quiz_badge="Interactif — aucun téléchargement requis",
    quiz_sub="Du vrai vocabulaire de la leçon 1 de Minna no Nihongo — directement dans votre navigateur.",
    q_prompt="Que signifie ce mot ?",
    q_score="{x} sur {y} !",
    q_pitch="Amusant, non ? Glissez-le dans votre poche : les 50 leçons avec audio, cartes mémo et quiz d'écoute. Apprenez le japonais où et quand vous voulez.",
    cta_sub="Commencez votre habitude japonaise dès aujourd'hui. Un mot à la fois.",
    lang_label="Langue",
    rights="Tous droits réservés.",
    hero_alt2="Capture d'écran de l'application Japanese Daily montrant le tableau interactif Hiragana et Katakana",
    hero_alt3="Capture d'écran de l'application Japanese Daily montrant des cartes de vocabulaire façon Tinder",
    how_kicker="comment ça marche",
    how_title="Trois étapes vers vos premiers vrais mots japonais",
    how_sub="Pas de compte, pas de configuration — ouvrez l'app et commencez avec le kana ou le vocabulaire du jour.",
    how1t="1. Échauffez-vous avec le Kana",
    how1d="Apprenez le Hiragana et le Katakana avec audio natif, caractère par caractère, à votre rythme.",
    how2t="2. Progressez avec Minna no Nihongo",
    how2d="Choisissez une leçon et révisez son vocabulaire avec des cartes mémo, des quiz et de l'écoute.",
    how3t="3. Créez une habitude quotidienne",
    how3d="Consultez le widget Aujourd'hui chaque matin pour un nouveau mot, et regardez votre barre de progression se remplir leçon après leçon.",
    faq_kicker="questions fréquentes",
    faq_title="Questions fréquentes",
    faq_sub="Tout ce que vous voudriez savoir avant de commencer.",
    faq1q="Japanese Daily est-il gratuit ?",
    faq1a="Oui. L'entraînement au Hiragana et au Katakana est gratuit, tout comme les 5 premières leçons de Minna no Nihongo. Un achat unique ou un abonnement débloque les 50 leçons et supprime les publicités.",
    faq2q="Ai-je besoin d'une connexion internet ?",
    faq2a="Non. Tout le vocabulaire, les tableaux de kana et l'audio natif sont intégrés à l'app, vous pouvez donc étudier hors ligne dans l'avion, le train, ou n'importe où.",
    faq3q="Quelles langues sont prises en charge ?",
    faq3a="Le vocabulaire et l'interface de l'app sont tous deux disponibles en 17 langues, de l'anglais et l'espagnol au vietnamien, à l'hindi et au coréen — choisissez celle dans laquelle vous pensez.",
    faq4q="Est-ce basé sur un vrai manuel ?",
    faq4a="Oui. Japanese Daily suit Minna no Nihongo, l'un des manuels de japonais les plus utilisés dans les salles de classe du monde entier, avec le vocabulaire des 50 leçons organisé exactement comme dans le livre — une base solide avant d'aborder le niveau JLPT.",
),
"ru": dict(
    autonym="Русский",
    title="Japanese Daily 每日日本語 — учите японский понемногу каждый день",
    desc="Учите японский каждый день: 50 уроков Minna no Nihongo, хирагана и катакана с озвучкой носителями, тесты и карточки на 17 языках — бесплатно на iPhone и iPad.",
    kicker="понемногу каждый день",
    tagline="Полный словарный запас, таблицы каны, тесты, аудирование и карточки — всё в одном красивом iOS-приложении.",
    hero_alt="Скриншот приложения Japanese Daily с лексикой Minna no Nihongo",
    free_note="Бесплатно на iPhone и iPad",
    feat_h2="Всё, что нужно, — {z} в одном приложении",
    feat_sub="От самого первого あ до полного владения Minna no Nihongo — ваш ежедневный спутник.",
    f1t="50 уроков Minna no Nihongo",
    f1d="Полная лексика всех 50 уроков классического учебника — в том порядке, в котором вы занимаетесь.",
    f2t="Лексика на 17 языках",
    f2d="Учите на языке, на котором думаете — русском, английском, китайском, испанском и других.",
    f3t="Таблицы каны с озвучкой",
    f3d="Каждый знак хираганы и катаканы озвучен носителями языка. Нажмите, послушайте, повторите.",
    f4t="Тесты и аудирование",
    f4d="Читайте и выбирайте — или сначала слушайте, а потом выбирайте услышанное. Два способа запомнить.",
    f5t="Карточки в стиле Tinder",
    f5d="Свайп вправо, если знаете, влево — если нет. Повторение ещё никогда не было таким быстрым.",
    f6t="Прописи",
    f6d="Обводите каждый знак каны в правильном порядке черт, пока рука тоже не запомнит.",
    f7t="Виджет «Сегодня»",
    f7d="Новое слово каждый день на главном экране и экране блокировки — учитесь ещё до разблокировки.",
    quiz_title="Попробуйте: тест по уроку 1",
    quiz_badge="Интерактивно — без установки приложения",
    quiz_sub="Настоящая лексика из первого урока Minna no Nihongo — прямо в браузере.",
    q_prompt="Что значит это слово?",
    q_score="Правильно {x} из {y}!",
    q_pitch="Понравилось? Положите это в карман: все 50 уроков с озвучкой, карточками и аудированием. Учите японский где и когда угодно.",
    cta_sub="Начните привычку учить японский сегодня. По одному слову за раз.",
    lang_label="Язык",
    rights="Все права защищены.",
    hero_alt2="Скриншот приложения Japanese Daily с интерактивной таблицей хираганы и катаканы",
    hero_alt3="Скриншот приложения Japanese Daily с карточками слов в стиле Tinder",
    how_kicker="как это работает",
    how_title="Три шага к первым настоящим японским словам",
    how_sub="Без регистрации и настроек — просто откройте приложение и начните с каны или слов на сегодня.",
    how1t="1. Разминка с каной",
    how1d="Учите хирагану и катакану с озвучкой носителями языка, знак за знаком, в своём темпе.",
    how2t="2. Проходите Minna no Nihongo",
    how2d="Выберите урок и закрепляйте его лексику карточками, тестами и аудированием.",
    how3t="3. Формируйте ежедневную привычку",
    how3d="Каждое утро смотрите виджет «Сегодня», чтобы выучить новое слово, и наблюдайте, как заполняется полоса прогресса от урока к уроку.",
    faq_kicker="частые вопросы",
    faq_title="Часто задаваемые вопросы",
    faq_sub="Всё, что вы хотели бы знать перед началом.",
    faq1q="Japanese Daily бесплатное?",
    faq1a="Да. Тренировка хираганы и катаканы бесплатна, как и первые 5 уроков Minna no Nihongo. Разовая покупка или подписка открывают все 50 уроков и убирают рекламу.",
    faq2q="Нужен ли интернет?",
    faq2a="Нет. Вся лексика, таблицы каны и озвучка носителями встроены в приложение, так что можно учиться офлайн — в самолёте, в поезде или где угодно.",
    faq3q="Какие языки поддерживаются?",
    faq3a="И лексика, и интерфейс приложения доступны на 17 языках — от английского и испанского до вьетнамского, хинди и корейского. Выбирайте тот, на котором думаете.",
    faq4q="Это основано на настоящем учебнике?",
    faq4a="Да. Japanese Daily следует Minna no Nihongo — одному из самых распространённых учебников японского в мире, а лексика всех 50 уроков организована точно так же, как в книге. Это прочная основа перед изучением уровней JLPT.",
),
"bn": dict(
    autonym="বাংলা",
    title="Japanese Daily 每日日本語 — প্রতিদিন কিছুটা জাপানি শিখুন",
    desc="প্রতিদিন জাপানি শিখুন: Minna no Nihongo-র ৫০টি পাঠ, নেটিভ অডিওসহ হিরাগানা ও কাতাকানা, ১৭টি ভাষায় কুইজ ও ফ্ল্যাশকার্ড — আইফোন ও আইপ্যাডে সম্পূর্ণ ফ্রি।",
    kicker="প্রতিদিন একটু একটু",
    tagline="সম্পূর্ণ শব্দভাণ্ডার, হিরাগানা ও কাতাকানা টেবিল, কুইজ, শোনার অনুশীলন এবং ফ্ল্যাশকার্ড — একটি সুন্দর iOS অ্যাপে সবকিছু।",
    hero_alt="Minna no Nihongo শব্দভাণ্ডার দেখাচ্ছে এমন Japanese Daily অ্যাপের স্ক্রিনশট",
    free_note="আইফোন ও আইপ্যাডে ফ্রি",
    feat_h2="প্রয়োজনীয় সবকিছু, {z} এক অ্যাপে",
    feat_sub="প্রথম あ থেকে শুরু করে সম্পূর্ণ Minna no Nihongo শব্দভাণ্ডার আয়ত্ত করা পর্যন্ত — আপনার প্রতিদিনের সঙ্গী।",
    f1t="Minna no Nihongo-র সম্পূর্ণ ৫০টি পাঠ",
    f1d="ক্লাসিক টেক্সটবুকের সব ৫০টি পাঠের সম্পূর্ণ শব্দভাণ্ডার, ঠিক যেভাবে আপনি পড়েন সেভাবে সাজানো।",
    f2t="১৭টি ভাষায় শব্দভাণ্ডার",
    f2d="আপনি যে ভাষায় ভাবেন সেই ভাষায় শিখুন — বাংলা, ইংরেজি, চীনা, স্প্যানিশ এবং আরও অনেক।",
    f3t="নেটিভ অডিওসহ কানা টেবিল",
    f3d="প্রতিটি হিরাগানা ও কাতাকানা অক্ষর নেটিভ স্পিকারের কণ্ঠে। ট্যাপ করুন, শুনুন, পুনরাবৃত্তি করুন।",
    f4t="কুইজ ও শোনার মোড",
    f4d="পড়ে বেছে নিন, বা আগে শুনে তারপর যা শুনেছেন তা বেছে নিন — মনে রাখার দুটি উপায়।",
    f5t="Tinder-স্টাইল ফ্ল্যাশকার্ড",
    f5d="জানলে ডানে সোয়াইপ, না জানলে বামে। রিভিশন এত দ্রুত আগে কখনো হয়নি।",
    f6t="লেখা অনুশীলন",
    f6d="সঠিক স্ট্রোক অর্ডারে প্রতিটি কানা ট্রেস করুন যতক্ষণ না আপনার হাতও এটি মনে রাখে।",
    f7t="Today উইজেট",
    f7d="হোম স্ক্রিন ও লক স্ক্রিনে প্রতিদিন একটি নতুন শব্দ — আনলক করার আগেই শিখে নিন।",
    quiz_title="চেষ্টা করুন: পাঠ ১-এর কুইজ",
    quiz_badge="ইন্টারেক্টিভ — অ্যাপ ডাউনলোডের প্রয়োজন নেই",
    quiz_sub="Minna no Nihongo পাঠ ১-এর আসল শব্দভাণ্ডার — সরাসরি আপনার ব্রাউজারে।",
    q_prompt="এই শব্দটির অর্থ কী?",
    q_score="আপনি {y}-এর মধ্যে {x} সঠিক করেছেন!",
    q_pitch="মজা লাগছে, তাই না? এবার এটি পকেটে নিয়ে নিন — অডিও, ফ্ল্যাশকার্ড ও শোনার কুইজসহ সম্পূর্ণ ৫০টি পাঠ। যখনই, যেখানেই ইচ্ছা জাপানি শিখুন।",
    cta_sub="আজই আপনার জাপানি শেখার অভ্যাস শুরু করুন। একবারে একটি শব্দ।",
    lang_label="ভাষা",
    rights="সমস্ত অধিকার সংরক্ষিত।",
    hero_alt2="Minna no Nihongo ইন্টারেক্টিভ হিরাগানা ও কাতাকানা টেবিল দেখাচ্ছে এমন Japanese Daily অ্যাপের স্ক্রিনশট",
    hero_alt3="Tinder-স্টাইল শব্দভাণ্ডার ফ্ল্যাশকার্ড দেখাচ্ছে এমন Japanese Daily অ্যাপের স্ক্রিনশট",
    how_kicker="কীভাবে কাজ করে",
    how_title="আপনার প্রথম জাপানি শব্দের জন্য তিনটি পদক্ষেপ",
    how_sub="কোনো অ্যাকাউন্ট লাগবে না, সেটআপও লাগবে না — অ্যাপ খুলুন এবং আজকের কানা বা শব্দভাণ্ডার দিয়ে শুরু করুন।",
    how1t="১. কানা দিয়ে ওয়ার্মআপ করুন",
    how1d="নেটিভ অডিওসহ হিরাগানা ও কাতাকানা শিখুন, একটি একটি করে, আপনার নিজের গতিতে।",
    how2t="২. Minna no Nihongo অনুসরণ করুন",
    how2d="একটি পাঠ বেছে নিন এবং ফ্ল্যাশকার্ড, কুইজ ও শোনার অনুশীলনের মাধ্যমে শব্দভাণ্ডার শিখুন।",
    how3t="৩. প্রতিদিনের অভ্যাস তৈরি করুন",
    how3d="প্রতিদিন সকালে নতুন একটি শব্দের জন্য Today উইজেট দেখুন, এবং প্রতিটি পাঠে আপনার অগ্রগতি বার ভরে ওঠা দেখুন।",
    faq_kicker="সাধারণ প্রশ্ন",
    faq_title="সাধারণ জিজ্ঞাসা",
    faq_sub="শুরু করার আগে আপনি যা জানতে চাইতে পারেন।",
    faq1q="Japanese Daily কি ফ্রি?",
    faq1a="হ্যাঁ। হিরাগানা ও কাতাকানা অনুশীলন সম্পূর্ণ ফ্রি, এবং Minna no Nihongo-র প্রথম ৫টি পাঠও ফ্রি। একবার কেনাকাটা বা সাবস্ক্রিপশনে সব ৫০টি পাঠ আনলক হয় এবং বিজ্ঞাপন বন্ধ হয়ে যায়।",
    faq2q="ইন্টারনেট সংযোগ লাগবে কি?",
    faq2a="না। সব শব্দভাণ্ডার, কানা টেবিল ও নেটিভ অডিও অ্যাপের সাথেই থাকে, তাই আপনি বিমানে, ট্রেনে বা যেকোনো জায়গায় অফলাইনে পড়তে পারবেন।",
    faq3q="কোন ভাষাগুলো সমর্থিত?",
    faq3a="শব্দভাণ্ডার ও অ্যাপের ইন্টারফেস দুটোই ১৭টি ভাষায় পাওয়া যায় — ইংরেজি, স্প্যানিশ থেকে ভিয়েতনামি, হিন্দি ও কোরিয়ান পর্যন্ত — আপনি যেই ভাষায় ভাবেন তা বেছে নিন।",
    faq4q="এটি কি বাস্তব কোনো পাঠ্যবইয়ের উপর ভিত্তি করে তৈরি?",
    faq4a="হ্যাঁ। Japanese Daily অনুসরণ করে Minna no Nihongo, বিশ্বজুড়ে ক্লাসরুমে সবচেয়ে বহুল ব্যবহৃত জাপানি পাঠ্যবইগুলোর একটি, যেখানে সব ৫০টি পাঠের শব্দভাণ্ডার বইয়ের মতোই সাজানো — JLPT স্তরে যাওয়ার আগে একটি দৃঢ় ভিত্তি।",
),
"hi": dict(
    autonym="हिन्दी",
    title="Japanese Daily 每日日本語 — हर दिन थोड़ा जापानी सीखें",
    desc="हर दिन जापानी सीखें: Minna no Nihongo के 50 पाठ, मूल ऑडियो के साथ हिरागाना और कातकाना, 17 भाषाओं में क्विज़ और फ़्लैशकार्ड — iPhone और iPad पर मुफ़्त।",
    kicker="हर दिन थोड़ा-थोड़ा",
    tagline="पूरी शब्दावली, काना टेबल, क्विज़, सुनने का अभ्यास और फ़्लैशकार्ड — सब एक सुंदर iOS ऐप में।",
    hero_alt="Minna no Nihongo शब्दावली दिखाता Japanese Daily ऐप का स्क्रीनशॉट",
    free_note="iPhone और iPad पर मुफ़्त",
    feat_h2="जो भी चाहिए, {z} एक ऐप में",
    feat_sub="पहले あ से लेकर पूरे Minna no Nihongo में महारत तक — आपका रोज़ का साथी।",
    f1t="Minna no Nihongo के सभी 50 पाठ",
    f1d="क्लासिक किताब के सभी 50 पाठों की पूरी शब्दावली, वैसे ही व्यवस्थित जैसे आप पढ़ते हैं।",
    f2t="17 भाषाओं में शब्दावली",
    f2d="उस भाषा में सीखें जिसमें आप सोचते हैं — हिन्दी, अंग्रेज़ी, चीनी, स्पैनिश और भी बहुत कुछ।",
    f3t="मूल ऑडियो के साथ काना टेबल",
    f3d="हर हिरागाना और कातकाना अक्षर मूल वक्ताओं की आवाज़ में। टैप करें, सुनें, दोहराएँ।",
    f4t="क्विज़ और सुनने का मोड",
    f4d="पढ़कर चुनें, या पहले सुनें और फिर जो सुना वह चुनें — याद रखने के दो तरीके।",
    f5t="Tinder-स्टाइल फ़्लैशकार्ड",
    f5d="आती है तो दाएँ स्वाइप करें, नहीं तो बाएँ। रिवीज़न कभी इतना तेज़ नहीं लगा।",
    f6t="लिखने का अभ्यास",
    f6d="हर काना को सही स्ट्रोक क्रम में तब तक ट्रेस करें जब तक आपका हाथ भी उसे याद न कर ले।",
    f7t="Today विजेट",
    f7d="होम स्क्रीन और लॉक स्क्रीन पर हर दिन एक नया शब्द — अनलॉक करने से पहले ही सीख लें।",
    quiz_title="आज़माएँ: पाठ 1 का क्विज़",
    quiz_badge="इंटरैक्टिव — ऐप डाउनलोड करने की ज़रूरत नहीं",
    quiz_sub="Minna no Nihongo के पाठ 1 की असली शब्दावली — सीधे आपके ब्राउज़र में।",
    q_prompt="इस शब्द का मतलब क्या है?",
    q_score="आपने {y} में से {x} सही किए!",
    q_pitch="मज़ा आया, है ना? इसे अपनी जेब में रखें — ऑडियो, फ़्लैशकार्ड और सुनने के क्विज़ के साथ सभी 50 पाठ। कभी भी, कहीं भी जापानी सीखें।",
    cta_sub="आज ही अपनी जापानी सीखने की आदत शुरू करें। एक बार में एक शब्द।",
    lang_label="भाषा",
    rights="सर्वाधिकार सुरक्षित।",
    hero_alt2="Japanese Daily ऐप का स्क्रीनशॉट, जिसमें इंटरैक्टिव हिरागाना और कातकाना टेबल दिख रही है",
    hero_alt3="Japanese Daily ऐप का स्क्रीनशॉट, जिसमें Tinder-स्टाइल शब्दावली फ़्लैशकार्ड दिख रहे हैं",
    how_kicker="यह कैसे काम करता है",
    how_title="आपके पहले असली जापानी शब्दों तक तीन कदम",
    how_sub="कोई अकाउंट नहीं, कोई सेटअप नहीं — बस ऐप खोलें और आज के काना या शब्दावली से शुरू करें।",
    how1t="1. काना से वार्मअप करें",
    how1d="मूल ऑडियो के साथ हिरागाना और कातकाना सीखें, एक-एक अक्षर, अपनी ही रफ़्तार से।",
    how2t="2. Minna no Nihongo के साथ आगे बढ़ें",
    how2d="एक पाठ चुनें और फ़्लैशकार्ड, क्विज़ और सुनने के अभ्यास से उसकी शब्दावली सीखें।",
    how3t="3. रोज़ की आदत बनाएँ",
    how3d="हर सुबह Today विजेट में एक नया शब्द देखें, और अपनी प्रोग्रेस बार को पाठ-दर-पाठ भरते देखें।",
    faq_kicker="सामान्य सवाल",
    faq_title="अक्सर पूछे जाने वाले सवाल",
    faq_sub="शुरू करने से पहले आप जो कुछ जानना चाहें।",
    faq1q="क्या Japanese Daily मुफ़्त है?",
    faq1a="हाँ। हिरागाना और कातकाना का अभ्यास मुफ़्त है, और Minna no Nihongo के पहले 5 पाठ भी मुफ़्त हैं। एक बार की खरीद या सब्सक्रिप्शन से सभी 50 पाठ अनलॉक होते हैं और विज्ञापन हट जाते हैं।",
    faq2q="क्या मुझे इंटरनेट कनेक्शन चाहिए?",
    faq2a="नहीं। सारी शब्दावली, काना टेबल और मूल ऑडियो ऐप में ही मौजूद हैं, इसलिए आप फ्लाइट में, ट्रेन में या कहीं भी ऑफ़लाइन पढ़ सकते हैं।",
    faq3q="कौन-कौन सी भाषाएँ समर्थित हैं?",
    faq3a="शब्दावली और ऐप का इंटरफ़ेस दोनों 17 भाषाओं में उपलब्ध हैं — अंग्रेज़ी, स्पैनिश से लेकर वियतनामी, हिन्दी और कोरियाई तक — जिस भाषा में आप सोचते हैं वही चुनें।",
    faq4q="क्या यह किसी असली किताब पर आधारित है?",
    faq4a="हाँ। Japanese Daily, Minna no Nihongo पर आधारित है, जो दुनिया भर की कक्षाओं में सबसे ज़्यादा इस्तेमाल होने वाली जापानी किताबों में से एक है, जिसमें सभी 50 पाठों की शब्दावली किताब जैसी ही क्रम में है — JLPT स्तर की तैयारी से पहले एक मज़बूत आधार।",
),
"ta": dict(
    autonym="தமிழ்",
    title="Japanese Daily 每日日本語 — ஒவ்வொரு நாளும் சிறிது ஜப்பானிய மொழி கற்போம்",
    desc="ஜப்பானியம் தினமும் கற்கவும்: Minna no Nihongo 50 பாடங்கள், ஹிரகானா & கடகானா, வினாடி வினா & ஃப்ளாஷ்கார்டுகள் 17 மொழிகளில் — iPhone & iPad-இல் இலவசம்.",
    kicker="ஒவ்வொரு நாளும் சிறிது",
    tagline="முழுமையான சொற்களஞ்சியம், கானா அட்டவணைகள், வினாடி வினாக்கள், கேட்டல் பயிற்சி மற்றும் ஃப்ளாஷ்கார்டுகள் — அனைத்தும் ஒரு அழகான iOS செயலியில்.",
    hero_alt="Minna no Nihongo சொற்களஞ்சியத்தைக் காட்டும் Japanese Daily செயலியின் திரைப்படம்",
    free_note="iPhone & iPad-இல் இலவசம்",
    feat_h2="தேவையான அனைத்தும், {z} ஒரே செயலியில்",
    feat_sub="முதல் あ முதல் Minna no Nihongo முழுவதையும் தேர்ச்சி பெறும் வரை — உங்கள் தினசரி துணை.",
    f1t="Minna no Nihongo-வின் அனைத்து 50 பாடங்கள்",
    f1d="பாரம்பரிய பாடநூலின் அனைத்து 50 பாடங்களின் முழுமையான சொற்களஞ்சியம், நீங்கள் படிக்கும் வழியிலேயே வரிசைப்படுத்தப்பட்டுள்ளது.",
    f2t="17 மொழிகளில் சொற்களஞ்சியம்",
    f2d="நீங்கள் நினைக்கும் மொழியில் கற்றுக்கொள்ளுங்கள் — தமிழ், ஆங்கிலம், சீனம், ஸ்பானிஷ் மற்றும் இன்னும் பல.",
    f3t="சொந்த குரல் ஒலியுடன் கானா அட்டவணைகள்",
    f3d="ஒவ்வொரு ஹிரகானா மற்றும் கடகானா எழுத்தும் சொந்த மொழி பேசுபவர்களால் குரல் கொடுக்கப்பட்டுள்ளது. தட்டவும், கேளுங்கள், மீண்டும் சொல்லுங்கள்.",
    f4t="வினாடி வினா & கேட்டல் முறை",
    f4d="படித்து தேர்வு செய்யுங்கள், அல்லது முதலில் கேட்டு பின் நீங்கள் கேட்டதைத் தேர்வு செய்யுங்கள் — நினைவில் நிற்க இரண்டு வழிகள்.",
    f5t="Tinder பாணி ஃப்ளாஷ்கார்டுகள்",
    f5d="தெரிந்தால் வலதுபுறம் ஸ்வைப் செய்யுங்கள், தெரியாவிட்டால் இடதுபுறம். மறுபடிப்பு இதற்கு முன் இவ்வளவு வேகமாக இருந்ததில்லை.",
    f6t="எழுதும் பயிற்சி",
    f6d="உங்கள் கையும் நினைவில் கொள்ளும் வரை ஒவ்வொரு கானாவையும் சரியான கோடு வரிசையில் வரையுங்கள்.",
    f7t="Today விட்ஜெட்",
    f7d="முகப்புத் திரை மற்றும் பூட்டுத் திரையில் ஒவ்வொரு நாளும் ஒரு புதிய சொல் — பூட்டைத் திறப்பதற்கு முன்பே கற்றுக்கொள்ளுங்கள்.",
    quiz_title="முயற்சிக்கவும்: பாடம் 1 வினாடி வினா",
    quiz_badge="இயங்குநிலை — ஆப் பதிவிறக்கம் தேவையில்லை",
    quiz_sub="Minna no Nihongo பாடம் 1-ன் உண்மையான சொற்களஞ்சியம் — உங்கள் உலாவியிலேயே.",
    q_prompt="இந்த சொல்லின் பொருள் என்ன?",
    q_score="{y}-இல் {x} சரியாக பதிலளித்தீர்கள்!",
    q_pitch="சுவாரஸ்யமா இல்லையா? இதை உங்கள் பாக்கெட்டில் வைத்துக் கொள்ளுங்கள் — ஒலியுடன் அனைத்து 50 பாடங்கள், ஃப்ளாஷ்கார்டுகள் மற்றும் கேட்டல் வினாடி வினாக்கள். எப்போது வேண்டுமானாலும், எங்கு வேண்டுமானாலும் ஜப்பானிய மொழி கற்றுக்கொள்ளுங்கள்.",
    cta_sub="இன்றே உங்கள் ஜப்பானிய மொழி பழக்கத்தைத் தொடங்குங்கள். ஒரு நேரத்தில் ஒரு சொல்.",
    lang_label="மொழி",
    rights="அனைத்து உரிமைகளும் பாதுகாக்கப்பட்டவை.",
    hero_alt2="ஊடாடும் ஹிரகானா மற்றும் கடகானா அட்டவணையைக் காட்டும் Japanese Daily செயலியின் திரைப்படம்",
    hero_alt3="Tinder பாணி சொற்களஞ்சிய ஃப்ளாஷ்கார்டுகளைக் காட்டும் Japanese Daily செயலியின் திரைப்படம்",
    how_kicker="இது எப்படி வேலை செய்கிறது",
    how_title="உங்கள் முதல் உண்மையான ஜப்பானிய சொற்களுக்கு மூன்று படிகள்",
    how_sub="கணக்கு தேவையில்லை, அமைப்பு தேவையில்லை — செயலியைத் திறந்து இன்றைய கானா அல்லது சொற்களஞ்சியத்துடன் தொடங்குங்கள்.",
    how1t="1. கானாவுடன் தொடங்குங்கள்",
    how1d="சொந்த குரலுடன் ஹிரகானா மற்றும் கடகானாவை ஒரு எழுத்தாக, உங்கள் வேகத்தில் கற்றுக்கொள்ளுங்கள்.",
    how2t="2. Minna no Nihongo-வைப் பின்பற்றுங்கள்",
    how2d="ஒரு பாடத்தைத் தேர்ந்து ஃப்ளாஷ்கார்டுகள், வினாடி வினாக்கள் மற்றும் கேட்டல் பயிற்சியுடன் சொற்களஞ்சியத்தைப் பயிலுங்கள்.",
    how3t="3. தினசரி பழக்கத்தை உருவாக்குங்கள்",
    how3d="ஒவ்வொரு காலையும் Today விட்ஜெட்டைப் பார்த்து புதிய சொல் ஒன்றைக் கற்றுக்கொள்ளுங்கள், பாடம் பாடமாக உங்கள் முன்னேற்றப் பட்டை நிரம்புவதைக் காணுங்கள்.",
    faq_kicker="அடிக்கடி கேட்கப்படும் கேள்விகள்",
    faq_title="அடிக்கடி கேட்கப்படும் கேள்விகள்",
    faq_sub="தொடங்குவதற்கு முன் நீங்கள் அறிய விரும்பும் அனைத்தும்.",
    faq1q="Japanese Daily இலவசமா?",
    faq1a="ஆம். ஹிரகானா மற்றும் கடகானா பயிற்சி முற்றிலும் இலவசம், அதோடு Minna no Nihongo-வின் முதல் 5 பாடங்களும் இலவசம். ஒரு முறை வாங்குதல் அல்லது சந்தா மூலம் அனைத்து 50 பாடங்களையும் திறந்து விளம்பரங்களை அகற்றலாம்.",
    faq2q="எனக்கு இன்டர்நெட் இணைப்பு தேவையா?",
    faq2a="தேவையில்லை. அனைத்து சொற்களஞ்சியம், கானா அட்டவணைகள் மற்றும் சொந்த குரல் ஒலி செயலியிலேயே உள்ளன, எனவே விமானத்திலோ, ரெயிலிலோ, எங்கிருந்தும் ஆஃப்லைனில் படிக்கலாம்.",
    faq3q="எந்த மொழிகள் ஆதரிக்கப்படுகின்றன?",
    faq3a="சொற்களஞ்சியம் மற்றும் செயலியின் இடைமுகம் இரண்டும் 17 மொழிகளில் கிடைக்கின்றன — ஆங்கிலம், ஸ்பானிஷ் முதல் வியட்நாமீஸ், ஹிந்தி மற்றும் கொரியன் வரை — நீங்கள் நினைக்கும் மொழியைத் தேர்ந்துகொள்ளுங்கள்.",
    faq4q="இது ஒரு உண்மையான பாடநூலை அடிப்படையாகக் கொண்டதா?",
    faq4a="ஆம். Japanese Daily, உலகெங்கிலும் வகுப்பறைகளில் மிகவும் பரவலாகப் பயன்படுத்தப்படும் ஜப்பானிய பாடநூல்களில் ஒன்றான Minna no Nihongo-வைப் பின்பற்றுகிறது, அனைத்து 50 பாடங்களின் சொற்களஞ்சியமும் புத்தகத்தில் உள்ளதைப் போலவே வரிசைப்படுத்தப்பட்டுள்ளது — JLPT நிலைக்குச் செல்வதற்கு முன் ஒரு உறுதியான அடித்தளம்.",
),
"te": dict(
    autonym="తెలుగు",
    title="Japanese Daily 每日日本語 — ప్రతిరోజూ కొంచెం జపనీస్ నేర్చుకోండి",
    desc="ప్రతిరోజూ జపనీస్ నేర్చుకోండి: Minna no Nihongo 50 పాఠాలు, స్థానిక ఆడియోతో హిరగానా & కటకానా, 17 భాషల్లో క్విజ్‌లు & ఫ్లాష్‌కార్డ్‌లు — iPhone & iPad‌లో ఉచితం.",
    kicker="ప్రతిరోజూ కొంచెం కొంచెం",
    tagline="పూర్తి పదజాలం, కానా పట్టికలు, క్విజ్‌లు, వినే అభ్యాసం మరియు ఫ్లాష్‌కార్డ్‌లు — అన్నీ ఒక అందమైన iOS యాప్‌లో.",
    hero_alt="Minna no Nihongo పదజాలాన్ని చూపే Japanese Daily యాప్ స్క్రీన్‌షాట్",
    free_note="iPhone & iPad‌లో ఉచితం",
    feat_h2="అవసరమైనవన్నీ, {z} ఒక్క యాప్‌లో",
    feat_sub="మొదటి あ నుండి పూర్తి Minna no Nihongo నైపుణ్యం వరకు — మీ రోజువారీ సహచరుడు.",
    f1t="Minna no Nihongo మొత్తం 50 పాఠాలు",
    f1d="క్లాసిక్ పాఠ్యపుస్తకంలోని అన్ని 50 పాఠాల పూర్తి పదజాలం, మీరు చదివే విధంగానే అమర్చబడింది.",
    f2t="17 భాషల్లో పదజాలం",
    f2d="మీరు ఆలోచించే భాషలో నేర్చుకోండి — తెలుగు, ఇంగ్లీష్, చైనీస్, స్పానిష్ మరియు మరిన్ని.",
    f3t="స్థానిక ఆడియోతో కానా పట్టికలు",
    f3d="ప్రతి హిరగానా మరియు కటకానా అక్షరం స్థానిక భాషికుల స్వరంతో. నొక్కండి, వినండి, పునరావృతం చేయండి.",
    f4t="క్విజ్‌లు & వినే మోడ్",
    f4d="చదివి ఎంచుకోండి, లేదా ముందు విని తర్వాత మీరు విన్నది ఎంచుకోండి — గుర్తుంచుకోవడానికి రెండు మార్గాలు.",
    f5t="Tinder-శైలి ఫ్లాష్‌కార్డ్‌లు",
    f5d="తెలిస్తే కుడివైపు స్వైప్ చేయండి, తెలియకపోతే ఎడమవైపు. రివిజన్ ఇంత వేగంగా ఎప్పుడూ అనిపించలేదు.",
    f6t="రైటింగ్ ప్రాక్టీస్",
    f6d="మీ చేయి కూడా గుర్తుంచుకునే వరకు ప్రతి కానాను సరైన స్ట్రోక్ క్రమంలో ట్రేస్ చేయండి.",
    f7t="Today విడ్జెట్",
    f7d="హోమ్ స్క్రీన్ మరియు లాక్ స్క్రీన్‌పై ప్రతిరోజూ ఒక కొత్త పదం — అన్‌లాక్ చేయడానికి ముందే నేర్చుకోండి.",
    quiz_title="ప్రయత్నించండి: పాఠం 1 క్విజ్",
    quiz_badge="ఇంటరాక్టివ్ — యాప్ డౌన్‌లోడ్ అవసరం లేదు",
    quiz_sub="Minna no Nihongo పాఠం 1 నుండి నిజమైన పదజాలం — నేరుగా మీ బ్రౌజర్‌లో.",
    q_prompt="ఈ పదానికి అర్థం ఏమిటి?",
    q_score="మీరు {y}‌లో {x} సరిగ్గా చెప్పారు!",
    q_pitch="సరదాగా ఉంది, కదా? దీన్ని మీ జేబులో పెట్టుకోండి — ఆడియో, ఫ్లాష్‌కార్డ్‌లు మరియు వినే క్విజ్‌లతో మొత్తం 50 పాఠాలు. ఎప్పుడైనా, ఎక్కడైనా జపనీస్ నేర్చుకోండి.",
    cta_sub="ఈరోజే మీ జపనీస్ అలవాటును ప్రారంభించండి. ఒక్కసారి ఒక పదం.",
    lang_label="భాష",
    rights="అన్ని హక్కులు ప్రత్యేకించబడ్డాయి.",
    hero_alt2="ఇంటరాక్టివ్ హిరగానా మరియు కటకానా పట్టికను చూపే Japanese Daily యాప్ స్క్రీన్‌షాట్",
    hero_alt3="Tinder-శైలి పదజాల ఫ్లాష్‌కార్డ్‌లను చూపే Japanese Daily యాప్ స్క్రీన్‌షాట్",
    how_kicker="ఇది ఎలా పని చేస్తుంది",
    how_title="మీ మొదటి నిజమైన జపనీస్ పదాలకు మూడు దశలు",
    how_sub="ఖాతా అవసరం లేదు, సెటప్ అవసరం లేదు — యాప్‌ను తెరిచి, నేటి కానా లేదా పదజాలంతో మొదలుపెట్టండి.",
    how1t="1. కానాతో వేడెక్కండి",
    how1d="స్థానిక ఆడియోతో హిరగానా మరియు కటకానాను ఒక్కో అక్షరంగా, మీ స్వంత వేగంతో నేర్చుకోండి.",
    how2t="2. Minna no Nihongo ప్రకారం ముందుకు సాగండి",
    how2d="ఒక పాఠాన్ని ఎంచుకుని ఫ్లాష్‌కార్డ్‌లు, క్విజ్‌లు మరియు వినే అభ్యాసంతో దాని పదజాలాన్ని సాధన చేయండి.",
    how3t="3. రోజువారీ అలవాటును పెంచుకోండి",
    how3d="ప్రతి ఉదయం కొత్త పదం కోసం Today విడ్జెట్‌ను చూడండి, మరియు మీ ప్రోగ్రెస్ బార్ పాఠం వారీగా నిండటం చూడండి.",
    faq_kicker="తరచుగా అడిగే ప్రశ్నలు",
    faq_title="తరచుగా అడిగే ప్రశ్నలు",
    faq_sub="మొదలుపెట్టే ముందు మీరు తెలుసుకోవాల్సిన ప్రతిదీ.",
    faq1q="Japanese Daily ఉచితమా?",
    faq1a="అవును. హిరగానా మరియు కటకానా సాధన పూర్తిగా ఉచితం, అలాగే Minna no Nihongo మొదటి 5 పాఠాలు కూడా ఉచితం. ఒకేసారి కొనుగోలు లేదా సబ్‌స్క్రిప్షన్‌తో మొత్తం 50 పాఠాలను అన్‌లాక్ చేసి ప్రకటనలను తీసివేయవచ్చు.",
    faq2q="నాకు ఇంటర్నెట్ కనెక్షన్ అవసరమా?",
    faq2a="అవసరం లేదు. అన్ని పదజాలం, కానా పట్టికలు మరియు స్థానిక ఆడియో యాప్‌లోనే ఉంటాయి, కాబట్టి మీరు విమానంలో, రైలులో లేదా ఎక్కడైనా ఆఫ్‌లైన్‌లో చదువుకోవచ్చు.",
    faq3q="ఏ భాషలు మద్దతు ఇస్తారు?",
    faq3a="పదజాలం మరియు యాప్ ఇంటర్‌ఫేస్ రెండూ 17 భాషల్లో అందుబాటులో ఉన్నాయి — ఇంగ్లీష్, స్పానిష్ నుండి వియత్నామీస్, హిందీ మరియు కొరియన్ వరకు — మీరు ఆలోచించే భాషను ఎంచుకోండి.",
    faq4q="ఇది నిజమైన పాఠ్యపుస్తకం ఆధారంగా ఉందా?",
    faq4a="అవును. Japanese Daily ప్రపంచవ్యాప్తంగా తరగతి గదులలో అత్యంత విస్తృతంగా ఉపయోగించే జపనీస్ పాఠ్యపుస్తకాలలో ఒకటైన Minna no Nihongo‌ను అనుసరిస్తుంది, మొత్తం 50 పాఠాల పదజాలం పుస్తకంలో ఉన్నట్లుగానే అమర్చబడింది — JLPT స్థాయికి వెళ్లే ముందు దృఢమైన పునాది.",
),
"fil": dict(
    autonym="Filipino",
    title="Japanese Daily 每日日本語 — Matuto ng Japanese, kaunti bawat araw",
    desc="Matuto ng Japanese araw-araw: 50 aralin ng Minna no Nihongo, Hiragana & Katakana may native audio, pagsusulit at flashcards sa 17 wika — libre sa iPhone at iPad.",
    kicker="kaunti bawat araw",
    tagline="Kumpletong bokabularyo, mga talahanayan ng kana, pagsusulit, pagsasanay sa pakikinig at flashcards — lahat sa isang magandang iOS app.",
    hero_alt="Screenshot ng Japanese Daily app na nagpapakita ng bokabularyo ng Minna no Nihongo",
    free_note="Libre sa iPhone & iPad",
    feat_h2="Lahat ng kailangan mo, {z} sa isang app",
    feat_sub="Mula sa iyong unang あ hanggang sa ganap na kahusayan sa Minna no Nihongo — ang iyong araw-araw na kasama.",
    f1t="50 aralin ng Minna no Nihongo",
    f1d="Kumpletong bokabularyo ng lahat ng 50 aralin mula sa klasikong aklat, hinanay eksakto sa paraan ng iyong pag-aaral.",
    f2t="Bokabularyo sa 17 wika",
    f2d="Matuto sa wikang iniisip mo — Filipino, English, Chinese, Spanish, at higit pa.",
    f3t="Mga talahanayan ng kana na may native audio",
    f3d="Bawat Hiragana at Katakana ay binibigkas ng katutubong tagapagsalita. Tapikin, pakinggan, ulitin.",
    f4t="Mga pagsusulit at listening mode",
    f4d="Basahin at piliin, o pakinggan muna at piliin ang naringgan — dalawang paraan para tumatak ito.",
    f5t="Flashcards na Tinder-style",
    f5d="Mag-swipe pakanan kung alam mo, pakaliwa kung hindi. Hindi pa kailanman ganito ang bilis ng pag-review.",
    f6t="Pagsasanay sa pagsulat",
    f6d="Tracein ang bawat kana sa tamang stroke order hanggang matandaan din ito ng kamay mo.",
    f7t="Today widget",
    f7d="Bagong salita araw-araw sa Home Screen at Lock Screen — matuto bago mo pa ma-unlock ang telepono.",
    quiz_title="Subukan: pagsusulit sa Aralin 1",
    quiz_badge="Interactive — walang kailangang i-download",
    quiz_sub="Totoong bokabularyo mula sa Aralin 1 ng Minna no Nihongo — dito mismo sa iyong browser.",
    q_prompt="Ano ang kahulugan ng salitang ito?",
    q_score="Nakuha mo ang {x} sa {y}!",
    q_pitch="Masaya, di ba? Dalhin mo na ito sa bulsa mo — buong 50 aralin na may audio, flashcards, at listening quiz. Matuto ng Japanese anumang oras, saanman.",
    cta_sub="Simulan mo na ang ugali mong mag-Japanese ngayong araw. Isang salita sa bawat pagkakataon.",
    lang_label="Wika",
    rights="Nakalaan ang lahat ng karapatan.",
    hero_alt2="Screenshot ng Japanese Daily app na nagpapakita ng interactive na talahanayan ng Hiragana at Katakana",
    hero_alt3="Screenshot ng Japanese Daily app na nagpapakita ng Tinder-style na flashcards ng bokabularyo",
    how_kicker="paano ito gumagana",
    how_title="Tatlong hakbang tungo sa iyong unang tunay na mga salitang Japanese",
    how_sub="Walang account, walang setup — buksan lang ang app at magsimula sa kana o bokabularyo ngayong araw.",
    how1t="1. Mag-warm up sa Kana",
    how1d="Matuto ng Hiragana at Katakana na may native audio, isa-isang karakter, sa sarili mong bilis.",
    how2t="2. Sundan ang Minna no Nihongo",
    how2d="Pumili ng aralin at pag-aralan ang bokabularyo nito gamit ang flashcards, pagsusulit at pagsasanay sa pakikinig.",
    how3t="3. Bumuo ng araw-araw na gawi",
    how3d="Tingnan ang Today widget bawat umaga para sa bagong salita, at panoorin ang iyong progress bar na napupuno aralin sa aralin.",
    faq_kicker="mga madalas itanong",
    faq_title="Mga madalas itanong",
    faq_sub="Lahat ng dapat mong malaman bago magsimula.",
    faq1q="Libre ba ang Japanese Daily?",
    faq1a="Oo. Libre ang pagsasanay sa Hiragana at Katakana, gayundin ang unang 5 aralin ng Minna no Nihongo. Isang beses na bili o subscription ay nag-a-unlock ng lahat ng 50 aralin at nag-aalis ng mga ad.",
    faq2q="Kailangan ko ba ng internet connection?",
    faq2a="Hindi. Lahat ng bokabularyo, talahanayan ng kana, at native audio ay nakapaloob na sa app, kaya makakapag-aral ka offline sa eroplano, tren, o kahit saan.",
    faq3q="Anong mga wika ang suportado?",
    faq3a="Ang bokabularyo at ang interface mismo ng app ay available sa 17 wika, mula English at Spanish hanggang Vietnamese, Hindi, at Korean — piliin lang ang wikang iniisip mo.",
    faq4q="Base ba ito sa isang tunay na aklat-aralin?",
    faq4a="Oo. Sinusunod ng Japanese Daily ang Minna no Nihongo, isa sa mga pinakalaganap na gamiting aklat-aralin sa Japanese sa mga silid-aralan sa buong mundo, kung saan ang bokabularyo ng lahat ng 50 aralin ay inayos eksakto gaya ng sa aklat — isang matibay na pundasyon bago harapin ang antas ng JLPT.",
),
"id": dict(
    autonym="Bahasa Indonesia",
    title="Japanese Daily 每日日本語 — Belajar bahasa Jepang, sedikit setiap hari",
    desc="Belajar bahasa Jepang setiap hari: 50 pelajaran Minna no Nihongo, Hiragana & Katakana audio asli, kuis & kartu kilas dalam 17 bahasa — gratis di iPhone & iPad.",
    kicker="sedikit setiap hari",
    tagline="Kosakata lengkap, tabel kana, kuis, latihan menyimak, dan kartu kilas — semua dalam satu aplikasi iOS yang indah.",
    hero_alt="Tangkapan layar aplikasi Japanese Daily yang menampilkan kosakata Minna no Nihongo",
    free_note="Gratis di iPhone & iPad",
    feat_h2="Semua yang Anda butuhkan, {z} dalam satu aplikasi",
    feat_sub="Dari あ pertama Anda hingga menguasai seluruh Minna no Nihongo — teman belajar harian Anda.",
    f1t="50 pelajaran Minna no Nihongo",
    f1d="Kosakata lengkap dari semua 50 pelajaran buku teks klasik, disusun tepat seperti cara Anda belajar.",
    f2t="Kosakata dalam 17 bahasa",
    f2d="Belajar dalam bahasa yang Anda pikirkan — Bahasa Indonesia, Inggris, Mandarin, Spanyol, dan lainnya.",
    f3t="Tabel kana dengan audio asli",
    f3d="Setiap Hiragana dan Katakana disuarakan oleh penutur asli. Ketuk, dengarkan, ulangi.",
    f4t="Kuis & mode menyimak",
    f4d="Baca lalu pilih, atau dengarkan dulu baru pilih apa yang Anda dengar — dua cara agar lebih mudah diingat.",
    f5t="Kartu kilas gaya Tinder",
    f5d="Geser kanan jika Anda tahu, kiri jika tidak. Mengulang materi belum pernah secepat ini.",
    f6t="Latihan menulis",
    f6d="Jiplak setiap kana dengan urutan garis yang benar sampai tangan Anda pun mengingatnya.",
    f7t="Widget Hari Ini",
    f7d="Kata baru setiap hari di Layar Utama dan Layar Kunci — belajar bahkan sebelum Anda membuka kunci.",
    quiz_title="Coba sekarang: kuis Pelajaran 1",
    quiz_badge="Interaktif — tanpa perlu unduh aplikasi",
    quiz_sub="Kosakata asli dari Pelajaran 1 Minna no Nihongo — langsung di browser Anda.",
    q_prompt="Apa arti kata ini?",
    q_score="Anda benar {x} dari {y}!",
    q_pitch="Seru, kan? Bawa dalam saku Anda — 50 pelajaran lengkap dengan audio, kartu kilas, dan kuis menyimak. Belajar bahasa Jepang kapan saja, di mana saja.",
    cta_sub="Mulai kebiasaan belajar bahasa Jepang Anda hari ini. Satu kata setiap kali.",
    lang_label="Bahasa",
    rights="Semua hak dilindungi.",
    hero_alt2="Tangkapan layar aplikasi Japanese Daily yang menampilkan tabel Hiragana dan Katakana interaktif",
    hero_alt3="Tangkapan layar aplikasi Japanese Daily yang menampilkan kartu kilas kosakata bergaya Tinder",
    how_kicker="cara kerjanya",
    how_title="Tiga langkah menuju kata-kata Jepang pertama Anda",
    how_sub="Tanpa akun, tanpa pengaturan — cukup buka aplikasi dan mulai dengan kana atau kosakata hari ini.",
    how1t="1. Pemanasan dengan Kana",
    how1d="Pelajari Hiragana dan Katakana dengan audio asli, satu karakter setiap kalinya, sesuai kecepatan Anda sendiri.",
    how2t="2. Ikuti Minna no Nihongo",
    how2d="Pilih satu pelajaran dan pelajari kosakatanya dengan kartu kilas, kuis, dan latihan menyimak.",
    how3t="3. Bangun kebiasaan harian",
    how3d="Cek widget Hari Ini setiap pagi untuk kata baru, dan lihat progres Anda terisi pelajaran demi pelajaran.",
    faq_kicker="pertanyaan umum",
    faq_title="Pertanyaan yang sering diajukan",
    faq_sub="Semua yang ingin Anda ketahui sebelum mulai.",
    faq1q="Apakah Japanese Daily gratis?",
    faq1a="Ya. Latihan Hiragana dan Katakana gratis, begitu juga 5 pelajaran pertama Minna no Nihongo. Pembelian sekali atau berlangganan membuka semua 50 pelajaran dan menghapus iklan.",
    faq2q="Apakah saya perlu koneksi internet?",
    faq2a="Tidak. Semua kosakata, tabel kana, dan audio asli sudah tersedia di dalam aplikasi, jadi Anda bisa belajar offline di pesawat, kereta, atau di mana saja.",
    faq3q="Bahasa apa saja yang didukung?",
    faq3a="Kosakata maupun antarmuka aplikasi tersedia dalam 17 bahasa, dari Inggris dan Spanyol hingga Vietnam, Hindi, dan Korea — pilih bahasa yang Anda pikirkan.",
    faq4q="Apakah ini berdasarkan buku teks asli?",
    faq4a="Ya. Japanese Daily mengikuti Minna no Nihongo, salah satu buku teks bahasa Jepang yang paling banyak digunakan di ruang kelas di seluruh dunia, dengan kosakata dari semua 50 pelajaran disusun persis seperti di buku — dasar yang kuat sebelum menghadapi tingkat JLPT.",
),
"ko": dict(
    autonym="한국어",
    title="Japanese Daily 每日日本語 — 매일 조금씩 일본어 배우기",
    desc="매일 일본어를 배우세요: Minna no Nihongo 전체 50개 레슨의 어휘, 17개 언어로 번역, 원어민 오디오가 포함된 히라가나 및 가타카나 표, 퀴즈, 듣기 연습, 플래시카드, 필순 쓰기 연습까지 — iPhone과 iPad에서 무료로 이용하세요.",
    kicker="매일 조금씩",
    tagline="전체 어휘, 가나 표, 퀴즈, 듣기 연습, 플래시카드까지 — 아름다운 iOS 앱 하나에 모두 담았습니다.",
    hero_alt="Minna no Nihongo 어휘를 보여주는 Japanese Daily 앱 스크린샷",
    free_note="iPhone & iPad에서 무료",
    feat_h2="필요한 모든 것, {z} 앱 하나에",
    feat_sub="첫 あ부터 Minna no Nihongo 전체를 완전히 익힐 때까지 — 매일 함께하는 학습 동반자.",
    f1t="Minna no Nihongo 전체 50개 레슨",
    f1d="고전 교재 전체 50개 레슨의 완전한 어휘를 학습 순서 그대로 정리했습니다.",
    f2t="17개 언어로 된 어휘",
    f2d="생각하는 언어로 배우세요 — 한국어, 영어, 중국어, 스페인어 등.",
    f3t="원어민 오디오가 담긴 가나 표",
    f3d="모든 히라가나와 가타카나를 원어민이 발음합니다. 탭하고, 듣고, 따라 하세요.",
    f4t="퀴즈 & 듣기 모드",
    f4d="읽고 고르거나, 먼저 듣고 들은 것을 고르세요 — 기억에 남기는 두 가지 방법.",
    f5t="Tinder 스타일 플래시카드",
    f5d="알면 오른쪽으로, 모르면 왼쪽으로 스와이프하세요. 복습이 이렇게 빨랐던 적은 없습니다.",
    f6t="쓰기 연습",
    f6d="손이 기억할 때까지 올바른 필순으로 모든 가나를 따라 써 보세요.",
    f7t="Today 위젯",
    f7d="홈 화면과 잠금 화면에서 매일 새로운 단어를 만나보세요 — 잠금을 풀기도 전에 배울 수 있습니다.",
    quiz_title="체험하기: 레슨 1 퀴즈",
    quiz_badge="인터랙티브 — 앱 다운로드 없이 바로",
    quiz_sub="Minna no Nihongo 레슨 1의 실제 어휘를 바로 브라우저에서 만나보세요.",
    q_prompt="이 단어의 뜻은 무엇일까요?",
    q_score="{y}개 중 {x}개를 맞혔어요!",
    q_pitch="재미있죠? 이제 주머니에 넣어 다니세요 — 오디오, 플래시카드, 듣기 퀴즈까지 포함된 전체 50개 레슨. 언제 어디서나 일본어를 배우세요.",
    cta_sub="오늘부터 일본어 습관을 시작하세요. 한 단어씩 차근차근.",
    lang_label="언어",
    rights="모든 권리 보유.",
    hero_alt2="인터랙티브 히라가나 및 가타카나 표를 보여주는 Japanese Daily 앱 스크린샷",
    hero_alt3="Tinder 스타일 어휘 플래시카드를 보여주는 Japanese Daily 앱 스크린샷",
    how_kicker="이용 방법",
    how_title="첫 일본어 단어를 배우는 세 단계",
    how_sub="계정도, 설정도 필요 없어요 — 앱을 열고 오늘의 가나나 어휘부터 시작하세요.",
    how1t="1. 가나로 몸풀기",
    how1d="원어민 오디오로 히라가나와 가타카나를 한 글자씩, 자신의 속도로 배우세요.",
    how2t="2. Minna no Nihongo로 진행하기",
    how2d="레슨을 선택하고 플래시카드, 퀴즈, 듣기 연습으로 어휘를 익히세요.",
    how3t="3. 매일의 습관 만들기",
    how3d="매일 아침 Today 위젯에서 새 단어를 확인하고, 레슨마다 진행률 막대가 채워지는 것을 지켜보세요.",
    faq_kicker="자주 묻는 질문",
    faq_title="자주 묻는 질문",
    faq_sub="시작하기 전에 알아두면 좋은 모든 것.",
    faq1q="Japanese Daily는 무료인가요?",
    faq1a="네. 히라가나와 가타카나 연습은 무료이며, Minna no Nihongo의 처음 5개 레슨도 무료입니다. 1회 구매 또는 구독으로 전체 50개 레슨을 잠금 해제하고 광고를 제거할 수 있습니다.",
    faq2q="인터넷 연결이 필요한가요?",
    faq2a="아니요. 모든 어휘, 가나 표, 원어민 오디오가 앱에 내장되어 있어 비행기, 지하철, 어디서든 오프라인으로 학습할 수 있습니다.",
    faq3q="어떤 언어를 지원하나요?",
    faq3a="어휘와 앱 인터페이스 모두 17개 언어로 제공됩니다 — 영어, 스페인어부터 베트남어, 힌디어, 한국어까지 — 생각하는 언어를 선택하세요.",
    faq4q="실제 교재를 기반으로 하나요?",
    faq4a="네. Japanese Daily는 전 세계 교실에서 가장 널리 사용되는 일본어 교재 중 하나인 Minna no Nihongo를 따르며, 전체 50개 레슨의 어휘가 책과 동일한 순서로 구성되어 있습니다 — JLPT 수준 공부를 시작하기 전 튼튼한 기초가 됩니다.",
),
}

# ---------------------------------------------------------------- build logic
import html as _html
import json as _json
import sys as _sys

QUIZ_ROMAJI = ["watashi", "anata", "gakusei", "isha",
               "daigaku", "byouin", "hai", "dare"]

def load_quiz_words():
    """Pull Lesson 1 quiz words + per-language meanings from the app's data."""
    data = _json.load(open(ROOT / "nihongo" / "Resources" / "MinnaData.json"))
    entries = {e["romaji"]: e for e in data["lessons"][0]["entries"]}
    words = {}
    for lang in data["languages"]:
        tr = data["translations"][lang]["1"]
        words[lang] = [
            {"w": entries[r]["kanji"], "k": entries[r]["kana"],
             "r": r, "m": tr[r]}
            for r in QUIZ_ROMAJI if r in entries and r in tr
        ]
    return words

def load_app_strings():
    """Borrow UI strings straight from the app so web + app stay in sync."""
    return _json.load(open(ROOT / "nihongo" / "UIStrings.json"))

def build(langs_to_build):
    quiz_words = load_quiz_words()
    ui = load_app_strings()
    built = [m for m in LANG_META if m[0] in langs_to_build and m[0] in T]

    for code, html_lang, hreflang, og_locale in built:
        t = T[code]
        s = ui.get(code, ui["en"])
        is_root = code == "en"
        canonical = BASE_URL + "/" if is_root else BASE_URL + "/" + code + "/"

        # hreflang alternates — only for pages that actually exist
        alt = []
        for c2, _, hl2, _ in built:
            url2 = BASE_URL + "/" if c2 == "en" else BASE_URL + "/" + c2 + "/"
            alt.append('<link rel="alternate" hreflang="%s" href="%s">' % (hl2, url2))
        alt.append('<link rel="alternate" hreflang="x-default" href="%s/">' % BASE_URL)
        hreflangs = "\n".join(alt)

        # language switcher — omit entirely when only one page is built
        if len(built) > 1:
            links = []
            for c2, _, _, _ in built:
                url2 = "/" if c2 == "en" else "/" + c2 + "/"
                cur = ' aria-current="true"' if c2 == code else ""
                links.append('      <a href="%s"%s>%s</a>' % (url2, cur, T[c2]["autonym"]))
            switcher_block = (
                '  <div class="lang-switch">\n'
                '    <span class="lang-label" id="lang-label">%s</span>\n'
                '    <nav aria-labelledby="lang-label">\n%s\n    </nav>\n'
                '  </div>'
            ) % (_html.escape(t["lang_label"]), "\n".join(links))
        else:
            switcher_block = ""

        i18n = {
            "prompt": t["q_prompt"],
            "correct": s.get("Correct!", "Correct!"),
            "wrong": s.get("Wrong", "Wrong"),
            "next": s.get("Next", "Next"),
            "restart": s.get("Restart", "Restart"),
            "score": t["q_score"],
            "pitch": t["q_pitch"],
        }

        faq_schema = {
            "@context": "https://schema.org",
            "@type": "FAQPage",
            "mainEntity": [
                {"@type": "Question", "name": t["faq1q"],
                 "acceptedAnswer": {"@type": "Answer", "text": t["faq1a"]}},
                {"@type": "Question", "name": t["faq2q"],
                 "acceptedAnswer": {"@type": "Answer", "text": t["faq2a"]}},
                {"@type": "Question", "name": t["faq3q"],
                 "acceptedAnswer": {"@type": "Answer", "text": t["faq3a"]}},
                {"@type": "Question", "name": t["faq4q"],
                 "acceptedAnswer": {"@type": "Answer", "text": t["faq4a"]}},
            ],
        }

        page = TEMPLATE.substitute(
            html_lang=html_lang,
            hreflang=hreflang,
            hreflangs=hreflangs,
            og_locale=og_locale,
            canonical=canonical,
            app_store=APP_STORE,
            title=_html.escape(t["title"], quote=False),
            desc=_html.escape(t["desc"], quote=False),
            kicker=t["kicker"],
            tagline=t["tagline"],
            hero_alt=_html.escape(t["hero_alt"], quote=True),
            hero_alt2=_html.escape(t["hero_alt2"], quote=True),
            hero_alt3=_html.escape(t["hero_alt3"], quote=True),
            free_note=t["free_note"],
            feat_h2=t["feat_h2"].replace("{z}", '<span class="jp">ぜんぶ</span>'),
            feat_sub=t["feat_sub"],
            f1t=t["f1t"], f1d=t["f1d"],
            f2t=t["f2t"], f2d=t["f2d"],
            f3t=t["f3t"], f3d=t["f3d"],
            f4t=t["f4t"], f4d=t["f4d"],
            f5t=t["f5t"], f5d=t["f5d"],
            f6t=t["f6t"], f6d=t["f6d"],
            f7t=t["f7t"], f7d=t["f7d"],
            how_kicker=t["how_kicker"],
            how_title=t["how_title"],
            how_sub=t["how_sub"],
            how1t=t["how1t"], how1d=t["how1d"],
            how2t=t["how2t"], how2d=t["how2d"],
            how3t=t["how3t"], how3d=t["how3d"],
            quiz_badge=t["quiz_badge"],
            quiz_title=t["quiz_title"],
            quiz_sub=t["quiz_sub"],
            quiz_data=_json.dumps(quiz_words.get(code, quiz_words["en"]), ensure_ascii=False),
            quiz_i18n=_json.dumps(i18n, ensure_ascii=False),
            faq_kicker=t["faq_kicker"],
            faq_title=t["faq_title"],
            faq_sub=t["faq_sub"],
            faq1q=t["faq1q"], faq1a=t["faq1a"],
            faq2q=t["faq2q"], faq2a=t["faq2a"],
            faq3q=t["faq3q"], faq3a=t["faq3a"],
            faq4q=t["faq4q"], faq4a=t["faq4a"],
            faq_jsonld=_json.dumps(faq_schema, ensure_ascii=False, indent=2),
            cta_sub=t["cta_sub"],
            privacy=s.get("Privacy Policy", "Privacy Policy"),
            terms=s.get("Terms of Use", "Terms of Use"),
            rights=t["rights"],
            switcher_block=switcher_block,
        )

        out = WEB / "index.html" if is_root else WEB / code / "index.html"
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(page, encoding="utf-8")
        print("wrote", out.relative_to(ROOT))

if __name__ == "__main__":
    if "--all" in _sys.argv:
        build([m[0] for m in LANG_META])
    else:
        build(["en"])  # translations paused — English only for now
