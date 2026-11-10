#!/usr/bin/env python3
"""Fetches Quran translations from Tanzil.net (sura|aya|text format) into the app's assets.

Each file must contain exactly 6236 rows in Surah/Ayah order or it is rejected.
Translations are the translators' work: they are shown with credit and never edited.
Tanzil terms: free for non-commercial use with attribution; commercial use needs the
translator's or publisher's permission (see docs/ROADMAP.md before a paid launch).

Usage: python3 -I tools/fetch_translations.py app/assets/translations
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

TRANSLATIONS = [
    ("en.sahih", "en", "Saheeh International", "Saheeh International"),
    ("en.transliteration", "en", "Transliteration", "Tanzil Project"),
    ("en.hilali", "en", "Hilali & Khan", "Muhammad Taqi-ud-Din al-Hilali and Muhammad Muhsin Khan"),
    ("en.wahiduddin", "en", "Wahiduddin Khan", "Wahiduddin Khan"),
    ("ml.abdulhameed", "ml", "അബ്ദുൽ ഹമീദ് & പറപ്പൂർ", "Cheriyamundam Abdul Hameed and Kunhi Mohammed Parappoor"),
    ("ml.karakunnu", "ml", "കാരകുന്ന് & എളയാവൂർ", "Muhammad Karakunnu and Vanidas Elayavoor"),
]
AYAH_COUNTS = None  # filled from the verified Quran assets


def load_counts(app_assets: Path) -> list[int]:
    surahs = json.loads((app_assets / "quran" / "surahs.json").read_text(encoding="utf-8"))
    return [s["c"] for s in surahs]


def fetch(tid: str) -> str:
    url = f"https://tanzil.net/trans/?transID={tid}&type=txt-2"
    req = urllib.request.Request(url, headers={"User-Agent": "HifzAcademy-build"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8")


def parse(text: str, counts: list[int]) -> list[str]:
    rows = []
    expect = [(s + 1, a + 1) for s, n in enumerate(counts) for a in range(n)]
    head = re.compile(r"^(\d+)\|(\d+)\|(.*)$")
    for line in text.splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        m = head.match(line)
        if m:
            rows.append(((int(m.group(1)), int(m.group(2))), m.group(3).strip()))
        elif rows:  # a verse whose text continues on the next line (e.g. footnotes)
            (k, t) = rows[-1]
            rows[-1] = (k, (t + " " + line.strip()).strip())
        else:
            raise ValueError("text before the first verse")
    if [k for k, _ in rows] != expect:
        raise ValueError(f"rows do not match Surah/Ayah order ({len(rows)} rows)")
    return [t for _, t in rows]


def main(out_dir: str) -> int:
    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    counts = load_counts(out.parent)
    index = []
    for tid, lang, name, author in TRANSLATIONS:
        try:
            rows = parse(fetch(tid), counts)
        except Exception as e:  # keep building with the translations that did work
            print(f"!! {tid}: {e}")
            continue
        (out / f"{tid}.json").write_text(json.dumps(
            {"id": tid, "lang": lang, "name": name, "author": author,
             "source": f"https://tanzil.net/trans/{tid}", "rows": rows}, ensure_ascii=False), encoding="utf-8")
        index.append({"id": tid, "lang": lang, "name": name, "author": author})
        print(f"ok {tid}: {len(rows)} rows")
    (out / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=1), encoding="utf-8")
    return 0 if index else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
