"""Tests for import_tanzil.py.

MOCK DATA: fixtures use Latin placeholder strings (MOCK-...). They are not Quranic text
and exist only to exercise the checks. Run: python3 -I -m unittest discover -s tests
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import import_tanzil as it  # noqa: E402

HEADER = "<!--\n# MOCK fixture imitating the Tanzil header layout\n# Tanzil Quran Text (test)\n-->\n"


def quran_xml(suras):
    body = "".join(
        f'<sura index="{i}" name="MOCK{i}">' +
        "".join(f'<aya index="{a}" text="{t}"/>' for a, t in ayas) + "</sura>"
        for i, ayas in suras)
    return f'<?xml version="1.0" encoding="utf-8" ?>\n{HEADER}<quran>{body}</quran>'


def meta_xml(counts):
    s = "".join(f'<sura index="{i}" ayas="{n}" start="0" name="M{i}" tname="Mock {i}" ename="Mock" type="Meccan"/>'
                for i, n in counts)
    return (f'<quran><suras>{s}</suras><juzs><juz index="1" sura="1" aya="1"/><juz index="2" sura="2" aya="2"/></juzs>'
            f'<pages><page index="1" sura="1" aya="1"/></pages></quran>')


GOOD = [(1, [(1, "MOCK-A"), (2, "MOCK-B")]), (2, [(1, "MOCK-C"), (2, "MOCK-D"), (3, "MOCK-E")])]


class ImportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def files(self, suras=GOOD, counts=((1, 2), (2, 3)), header=True):
        q = self.tmp / "q.xml"
        txt = quran_xml(suras)
        if not header:
            txt = txt.replace(HEADER, "")
        q.write_text(txt, encoding="utf-8")
        m = self.tmp / "m.xml"
        m.write_text(meta_xml(counts), encoding="utf-8")
        return q, m

    def run_main(self, q, m, *extra):
        return it.main(["--quran", str(q), "--meta", str(m), "--out", str(self.tmp / "out"), "--allow-partial", *extra])

    def test_good_file_imports_text_unchanged(self):
        q, m = self.files()
        self.assertEqual(self.run_main(q, m), 0)
        data = json.loads((self.tmp / "out/quran_text.json").read_text(encoding="utf-8"))
        self.assertEqual([d["t"] for d in data], ["MOCK-A", "MOCK-B", "MOCK-C", "MOCK-D", "MOCK-E"])
        self.assertEqual([d["id"] for d in data], [1, 2, 3, 4, 5])
        self.assertEqual(data[3]["j"], 2)  # 2:2 starts juz 2 in the mock metadata

    def test_full_check_rejects_partial_quran(self):
        q, m = self.files()
        rc = it.main(["--quran", str(q), "--meta", str(m), "--out", str(self.tmp / "o")])
        self.assertEqual(rc, 1)

    def test_missing_licence_header_rejected(self):
        q, m = self.files(header=False)
        self.assertEqual(self.run_main(q, m), 1)

    def test_skipped_ayah_rejected(self):
        q, m = self.files(suras=[(1, [(1, "MOCK-A"), (3, "MOCK-B")]), (2, GOOD[1][1])])
        self.assertEqual(self.run_main(q, m), 1)

    def test_count_mismatch_with_metadata_rejected(self):
        q, m = self.files(counts=((1, 2), (2, 4)))
        self.assertEqual(self.run_main(q, m), 1)

    def test_whitespace_damage_rejected(self):
        q, m = self.files(suras=[(1, [(1, "MOCK-A "), (2, "MOCK-B")]), (2, GOOD[1][1])])
        self.assertEqual(self.run_main(q, m), 1)

    def test_pinned_hash_mismatch_rejected(self):
        q, m = self.files()
        self.assertEqual(self.run_main(q, m, "--pin-sha256", "0" * 64), 1)

    def test_pinned_hash_match_accepted(self):
        q, m = self.files()
        self.assertEqual(self.run_main(q, m, "--pin-sha256", it.sha256_file(q)), 0)

    def test_nothing_written_on_failure(self):
        q, m = self.files(counts=((1, 9), (2, 3)))
        self.run_main(q, m)
        self.assertFalse((self.tmp / "out").exists())

    def test_sql_wraps_import_session(self):
        q, m = self.files()
        self.run_main(q, m)
        sql = (self.tmp / "out/quran_import.sql").read_text(encoding="utf-8")
        self.assertTrue(sql.startswith("begin;\nset local app.quran_import = 'on';"))
        self.assertTrue(sql.rstrip().endswith("commit;"))


if __name__ == "__main__":
    unittest.main()
