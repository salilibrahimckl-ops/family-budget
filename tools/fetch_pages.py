"""Fetches the Madani Mushaf page starts (604 pages) from Tanzil's metadata
(https://tanzil.net/res/text/metadata/quran-data.js) into assets/quran/pages.json as
[[surah, ayah], ...] (page n starts at index n-1). Used for "recite a page"."""
import json, re, sys, urllib.request
from pathlib import Path

out = Path(sys.argv[1])
js = urllib.request.urlopen("https://tanzil.net/res/text/metadata/quran-data.js", timeout=60).read().decode("utf-8")
m = re.search(r"QuranData\.Page\s*=\s*\[(.*?)\];", js, re.S)
pairs = [[int(a), int(b)] for a, b in re.findall(r"\[\s*(\d+)\s*,\s*(\d+)\s*\]", m.group(1))]
if pairs and pairs[-1][0] == 115:
    pairs = pairs[:-1]  # end marker
assert len(pairs) == 604, len(pairs)
assert pairs[0] == [1, 1] and pairs[1] == [2, 1], pairs[:3]
out.write_text(json.dumps(pairs))
print("pages:", len(pairs), "last page starts at", pairs[-1])
