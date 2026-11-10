#!/usr/bin/env python3
"""Build-time fetch of two things the app bundles:

1. Explanations: "Al-Mukhtasar fi Tafsir al-Quran" (Tafsir Center for Quranic Studies),
   a short scholar-written explanation, in English, Malayalam and Arabic, from the
   QuranEnc.com API (King Fahd Complex / Islamic Content Service). Shown with credit,
   never edited. QuranEnc content: free to use with attribution, without modification.
2. Tanzil "simple-clean" text: the Quran in ordinary spelling without marks. Used only
   to compare against speech recognition (which writes ordinary spelling); never shown.

Every set must have exactly one entry per Ayah (6236) in Surah/Ayah order.
Usage: python3 -I tools/fetch_tafsir.py app/assets
"""
import json
import re
import sys
import time
import urllib.request
from pathlib import Path

UA = {"User-Agent": "HifzAcademy-build"}
WANT = [("en", "english"), ("ml", "malayalam"), ("ar", "arabic")]


def get(url: str, tries: int = 4) -> bytes:
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
                return r.read()
        except Exception:
            if i == tries - 1:
                raise
            time.sleep(3 * (i + 1))


def clean(html: str) -> str:
    t = re.sub(r"<br\s*/?>", "\n", html or "")
    t = re.sub(r"<[^>]+>", "", t)
    return re.sub(r"[ \t]+", " ", t).strip()


def fetch_quranenc(key: str, counts: list[int]) -> list[str]:
    rows = []
    for s, n in enumerate(counts, start=1):
        data = json.loads(get(f"https://quranenc.com/api/v1/translation/sura/{key}/{s}"))
        items = data["result"] if isinstance(data, dict) else data
        got = {int(it["aya"]): clean(it.get("translation", "")) for it in items if int(it["sura"]) == s}
        if sorted(got) != list(range(1, n + 1)):
            raise ValueError(f"{key}: Surah {s} has {len(got)} entries, expected {n}")
        rows += [got[a] for a in range(1, n + 1)]
    return rows


def main(assets: str) -> int:
    root = Path(assets)
    surahs = json.loads((root / "quran" / "surahs.json").read_text(encoding="utf-8"))
    counts = [s["c"] for s in surahs]
    ok = True

    # 1. Explanations
    out = root / "tafsir"
    out.mkdir(parents=True, exist_ok=True)
    catalogue = json.loads(get("https://quranenc.com/api/v1/translations/list"))
    catalogue = catalogue["translations"] if isinstance(catalogue, dict) else catalogue
    keys = {c["key"]: c for c in catalogue}
    index = []
    for lang, word in WANT:
        key = next((k for k in keys if k.startswith(word) and "mokhtasar" in k), None)
        if key is None:
            print(f"!! no Al-Mukhtasar found for {lang}")
            continue
        try:
            rows = fetch_quranenc(key, counts)
        except Exception as e:
            print(f"!! {key}: {e}")
            ok = False
            continue
        meta = keys[key]
        (out / f"{key}.json").write_text(json.dumps({
            "id": key, "lang": lang, "name": "Al-Mukhtasar (abridged explanation)",
            "author": "Tafsir Center for Quranic Studies", "version": meta.get("version", ""),
            "source": f"https://quranenc.com/en/browse/{key}", "rows": rows}, ensure_ascii=False), encoding="utf-8")
        index.append({"id": key, "lang": lang, "name": "Al-Mukhtasar", "author": "Tafsir Center for Quranic Studies"})
        print(f"ok {key}: {len(rows)} rows, v{meta.get('version', '?')}")
    (out / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=1), encoding="utf-8")

    # 2. Simple-clean text for recitation checking
    try:
        txt = get("https://tanzil.net/pub/download/index.php?quranType=simple-clean&outType=txt-2&agree=true").decode("utf-8")
        rows = []
        for line in txt.splitlines():
            m = re.match(r"^(\d+)\|(\d+)\|(.*)$", line)
            if m:
                rows.append(((int(m.group(1)), int(m.group(2))), m.group(3).strip()))
        expect = [(s + 1, a + 1) for s, n in enumerate(counts) for a in range(n)]
        if [k for k, _ in rows] != expect:
            raise ValueError(f"simple-clean has {len(rows)} rows in the wrong order")
        (root / "quran" / "simple_clean.json").write_text(json.dumps([t for _, t in rows], ensure_ascii=False), encoding="utf-8")
        print(f"ok simple-clean: {len(rows)} rows")
    except Exception as e:
        print(f"!! simple-clean: {e}")
        ok = False
    return 0 if ok or index else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
