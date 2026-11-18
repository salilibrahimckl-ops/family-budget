"""Merges eval-*.json and prints the report."""
import glob, json, collections
rows, falses, recall = [], [], []
for f in sorted(glob.glob("**/eval-*.json", recursive=True)):
    d = json.load(open(f)); rows += d["rows"]; falses += d["falses"]; recall += d["recall"]
print(f"sessions: {len(rows)}  audio: {sum(r['seconds'] for r in rows)/60:.0f} min")
by = collections.defaultdict(lambda: [0, 0, 0])
for r in rows:
    b = by[r["scenario"]]; b[0] += 1; b[1] += r["mistakes"]; b[2] += (r["mistakes"] == 0)
for k, (n, m, z) in by.items():
    print(f"  {k:8s} sessions={n} false mistakes={m} ({m/n:.2f}/session)  sessions with none={z}/{n}")
print("not recognised as recited:", sum(len(r["not_recited"]) for r in rows), [ (r['reciter'], r['passage'], r['scenario'], r['not_recited']) for r in rows if r['not_recited']][:15])
print("by reciter:")
br = collections.Counter(); bn = collections.Counter()
for r in rows: br[r["reciter"]] += r["mistakes"]; bn[r["reciter"]] += 1
for k, v in br.most_common(): print(f"  {k:38s} {v} in {bn[k]} sessions")
print("by type/speech:", collections.Counter((f["type"], f["speech"]) for f in falses).most_common())
print("tajweed rules:", collections.Counter(tuple(f["rules"]) for f in falses if f["type"] == "tajweed").most_common(10))
print("most common expected->heard:", collections.Counter((f["type"], f["expected"], f["heard"]) for f in falses).most_common(25))
rc = collections.defaultdict(lambda: [0, 0, 0])
for r in recall:
    b = rc[r["kind"]]; b[0] += 1; b[1] += r["caught"]; b[2] += r.get("clip_ok", False)
for k, (n, c, ok) in rc.items(): print(f"real mistakes {k}: caught {c}/{n}" + (f", clip at the right place {ok}/{c}" if k == "skip" else ""))
print("ALL FALSES:")
for f in falses: print("  ", json.dumps(f, ensure_ascii=False))
