#!/usr/bin/env python3
"""Verify and convert a Tanzil Quran XML file into the app's read-only assets.

The tool never edits Quranic text. It only reads the file, checks it, and writes
the same strings out with their SHA-256 hashes. Any check that fails aborts the
whole import; nothing partial is written.

Usage:
  python3 -I import_tanzil.py --quran quran-uthmani.xml --meta quran-data.xml \
      --pin-sha256 <hash you recorded when downloading> --out build/

Inputs (download manually from https://tanzil.net/download and https://tanzil.net/docs/quran_metadata):
  quran-uthmani.xml  Uthmani text, XML format, with the Tanzil licence header intact.
  quran-data.xml     Tanzil metadata (surah names, ayah counts, juz/page boundaries).

Outputs:
  quran_text.json    {surah, ayah, id, text, sha256, juz, page} for the Flutter app (assets/quran/)
  quran_import.sql   INSERTs for Supabase, wrapped in an import session
  manifest.json      source file hashes + combined content hash, checked by the app at startup
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import unicodedata
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

EXPECTED_SURAHS = 114
EXPECTED_AYAHS = 6236  # Hafs 'an 'Asim, Kufan count (Medina Mushaf)


class ImportError_(Exception):
    pass


@dataclass(frozen=True)
class Ayah:
    id: int
    surah: int
    ayah: int
    text: str
    juz: int | None
    page: int | None

    @property
    def sha256(self) -> str:
        return hashlib.sha256(self.text.encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def read_licence_header(path: Path) -> str:
    raw = path.read_text(encoding="utf-8")
    start = raw.find("<!--")
    end = raw.find("-->", start)
    if start < 0 or end < 0 or "tanzil" not in raw[start:end].lower():
        raise ImportError_("Tanzil licence header missing: the file must be the unmodified download")
    return raw[start + 4 : end].strip()


def parse_meta(path: Path) -> tuple[list[dict], list[tuple[int, int]], list[tuple[int, int]]]:
    root = ET.parse(path).getroot()
    suras = []
    for s in root.iter("sura"):
        suras.append({
            "index": int(s.get("index")),
            "ayas": int(s.get("ayas")),
            "start": int(s.get("start")),
            "name": s.get("name"),
            "tname": s.get("tname"),
            "ename": s.get("ename"),
            "type": s.get("type"),
        })
    juz = [(int(j.get("sura")), int(j.get("aya"))) for j in root.iter("juz")]
    pages = [(int(p.get("sura")), int(p.get("aya"))) for p in root.iter("page")]
    return suras, juz, pages


def boundary_index(boundaries: list[tuple[int, int]], s: int, a: int) -> int | None:
    """1-based index of the last boundary at or before (s, a)."""
    if not boundaries:
        return None
    idx = None
    for i, b in enumerate(boundaries, start=1):
        if b <= (s, a):
            idx = i
        else:
            break
    return idx


def load(quran: Path, meta: Path, expect_full: bool = True) -> tuple[list[dict], list[Ayah]]:
    """Returns surah metadata (with verbatim 'bismillah' text where Tanzil provides it) and Ayahs."""
    read_licence_header(quran)
    suras_meta, juz, pages = parse_meta(meta)
    root = ET.parse(quran).getroot()

    ayahs: list[Ayah] = []
    seen_suras = []
    bism: dict[int, str | None] = {}
    gid = 0
    for s in root.iter("sura"):
        si = int(s.get("index"))
        seen_suras.append(si)
        bism[si] = None
        expected_ai = 1
        for a in s.iter("aya"):
            ai = int(a.get("index"))
            if ai != expected_ai:
                raise ImportError_(f"Surah {si}: expected ayah {expected_ai}, found {ai}")
            text = a.get("text")
            if ai == 1 and a.get("bismillah") is not None:
                b = a.get("bismillah")
                if not b.strip() or b != b.strip():
                    raise ImportError_(f"Surah {si}: malformed bismillah attribute")
                bism[si] = b
            if not text or not text.strip():
                raise ImportError_(f"{si}:{ai} has empty text")
            if text != text.strip():
                raise ImportError_(f"{si}:{ai} has leading/trailing whitespace")
            if any(unicodedata.category(c) == "Cc" for c in text):
                raise ImportError_(f"{si}:{ai} contains control characters")
            gid += 1
            ayahs.append(Ayah(gid, si, ai, text, boundary_index(juz, si, ai), boundary_index(pages, si, ai)))
            expected_ai += 1

    if seen_suras != list(range(1, len(seen_suras) + 1)):
        raise ImportError_("Surahs are missing or out of order")
    if len(seen_suras) != len(suras_meta):
        raise ImportError_(f"Text has {len(seen_suras)} surahs, metadata has {len(suras_meta)}")
    for m in suras_meta:
        n = sum(1 for x in ayahs if x.surah == m["index"])
        if n != m["ayas"]:
            raise ImportError_(f"Surah {m['index']}: text has {n} ayahs, metadata says {m['ayas']}")
    for m in suras_meta:
        m["bismillah"] = bism.get(m["index"])
    if expect_full and (len(seen_suras) != EXPECTED_SURAHS or len(ayahs) != EXPECTED_AYAHS):
        raise ImportError_(f"Expected {EXPECTED_SURAHS} surahs / {EXPECTED_AYAHS} ayahs, "
                           f"got {len(seen_suras)} / {len(ayahs)}")
    return suras_meta, ayahs


def sha(s: str) -> str:
    return hashlib.sha256(s.encode("utf-8")).hexdigest()


def words_of(text: str) -> list[str]:
    """Word = a space-separated token containing at least one letter. Pause marks (ۚ ۖ ...) are
    separate tokens in Tanzil and are not words. Same rule as the app (QuranWords in Dart)."""
    toks = text.split(" ")
    if " ".join(toks) != text:
        raise ImportError_("tokenisation is not lossless")
    return [t for t in toks if any(unicodedata.category(c).startswith("L") for c in t)]


def content_hash(ayahs: list[Ayah], suras: list[dict] | None = None) -> str:
    h = hashlib.sha256()
    for a in ayahs:
        h.update(f"{a.surah}:{a.ayah}:{a.sha256}\n".encode())
    for m in suras or []:
        if m.get("bismillah"):
            h.update(f"B:{m['index']}:{sha(m['bismillah'])}\n".encode())
    return h.hexdigest()


def sql_literal(s: str) -> str:
    return "'" + s.replace("'", "''") + "'"


def write_outputs(out: Path, quran: Path, meta: Path, suras: list[dict], ayahs: list[Ayah], version: str) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    qhash = sha256_file(quran)
    manifest = {
        "source": "Tanzil Uthmani",
        "source_url": "https://tanzil.net",
        "version": version,
        "license": "CC BY 3.0 — verbatim copies only; changing the text is not allowed; credit Tanzil.net",
        "quran_file_sha256": qhash,
        "meta_file_sha256": sha256_file(meta),
        "surah_count": len(suras),
        "ayah_count": len(ayahs),
        "word_count": sum(len(words_of(a.text)) for a in ayahs),
        "bismillah_count": sum(1 for m in suras if m.get("bismillah")),
        "content_sha256": content_hash(ayahs, suras),
    }
    (out / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    (out / "surahs.json").write_text(json.dumps(
        [{"i": m["index"], "n": m["name"], "t": m["tname"], "e": m["ename"],
          "m": "madinah" if (m["type"] or "").lower().startswith("medin") else "makkah",
          "c": m["ayas"], "b": m.get("bismillah"), "bh": sha(m["bismillah"]) if m.get("bismillah") else None}
         for m in suras], ensure_ascii=False), encoding="utf-8")
    (out / "quran_text.json").write_text(json.dumps(
        [{"id": a.id, "s": a.surah, "a": a.ayah, "t": a.text, "h": a.sha256, "j": a.juz, "p": a.page} for a in ayahs],
        ensure_ascii=False), encoding="utf-8")

    lines = ["begin;", "set local app.quran_import = 'on';",
             "insert into quran.sources(id,kind,name,url,version,license,file_sha256) values "
             f"(1,'text','Tanzil Uthmani','https://tanzil.net',{sql_literal(version)},"
             f"{sql_literal(manifest['license'])},'{qhash}');"]
    for m in suras:
        place = "madinah" if (m["type"] or "").lower().startswith("medin") else "makkah"
        b = m.get("bismillah")
        bsql = f"{sql_literal(b)},'{sha(b)}'" if b else "null,null"
        lines.append("insert into quran.surahs(id,name_arabic,name_transliterated,name_en,revelation_place,ayah_count,source_id,bismillah_text,bismillah_sha256) values ("
                     f"{m['index']},{sql_literal(m['name'])},{sql_literal(m['tname'])},"
                     f"{sql_literal(m['ename'])},'{place}',{m['ayas']},1,{bsql});")
    for a in ayahs:
        lines.append("insert into quran.ayahs(id,surah_id,ayah_number,text_uthmani,text_sha256,juz,page,source_id) values ("
                     f"{a.id},{a.surah},{a.ayah},{sql_literal(a.text)},'{a.sha256}',"
                     f"{a.juz if a.juz else 'null'},{a.page if a.page else 'null'},1);")
    src_words = "insert into quran.sources(id,kind,name,url,version,license,file_sha256) values " \
        f"(2,'words','Tanzil Uthmani, space tokenisation (letters only)','https://tanzil.net',{sql_literal(version)},'derived from source 1','{qhash}');"
    lines.append(src_words)
    for a in ayahs:
        for pos, w in enumerate(words_of(a.text), start=1):
            lines.append(f"insert into quran.words(id,ayah_id,position,text_uthmani,source_id) values "
                         f"({a.id * 1000 + pos},{a.id},{pos},{sql_literal(w)},2);")
    lines.append("commit;")
    (out / "quran_import.sql").write_text("\n".join(lines) + "\n", encoding="utf-8")
    write_chunks(out / "sql_chunks", lines[2:-1])
    return manifest


def write_chunks(folder: Path, statements: list[str], max_bytes: int = 350_000) -> int:
    """Same statements split into files small enough to paste into the Supabase SQL editor.
    Each file is its own import session; run them in order (01, 02, ...)."""
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("*.sql"):
        old.unlink()
    parts: list[list[str]] = [[]]
    size = 0
    for st in statements:
        n = len(st.encode("utf-8")) + 1
        if size + n > max_bytes and parts[-1]:
            parts.append([])
            size = 0
        parts[-1].append(st)
        size += n
    for i, part in enumerate(parts, start=1):
        body = "\n".join(["begin;", "set local app.quran_import = 'on';", *part, "commit;"]) + "\n"
        (folder / f"{i:02d}.sql").write_text(body, encoding="utf-8")
    return len(parts)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--quran", type=Path, required=True)
    ap.add_argument("--meta", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--version", default="unspecified", help="Tanzil version or download date")
    ap.add_argument("--pin-sha256", help="SHA-256 recorded at download; import aborts if the file differs")
    ap.add_argument("--allow-partial", action="store_true", help="TEST ONLY: skip the 114/6236 completeness check")
    args = ap.parse_args(argv)

    try:
        if args.pin_sha256 and sha256_file(args.quran) != args.pin_sha256.lower():
            raise ImportError_("Quran file hash does not match the pinned hash — file changed since download")
        suras, ayahs = load(args.quran, args.meta, expect_full=not args.allow_partial)
        manifest = write_outputs(args.out, args.quran, args.meta, suras, ayahs, args.version)
    except (ImportError_, ET.ParseError, ValueError, TypeError) as e:
        print(f"IMPORT ABORTED: {e}", file=sys.stderr)
        return 1
    print(json.dumps(manifest, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
