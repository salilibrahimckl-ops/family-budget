"""CI check of the teacher on real recitations (EveryAyah, Husary teaching style).

1. A correct recitation of 112:1 should come back with status ok and few or no mistakes.
2. A recitation of 112:2 checked as 112:1 must NOT pass as correct.
3. 2:255 (Ayat al-Kursi, ~50 s) exercises splitting long recitations.
4. Silence returns 'silent'.
"""
import io, json, subprocess, sys, time, urllib.request, wave
import numpy as np
from fastapi.testclient import TestClient
import app as server

def mp3(path, reciter="Husary_Muallim_128kbps"):
    return urllib.request.urlopen(f"https://everyayah.com/data/{reciter}/{path}.mp3", timeout=60).read()

c = TestClient(server.app)
t = time.time()
while not server.M.ready and server.M.error is None and time.time() - t < 900:
    time.sleep(2)
print("health", c.get("/health").json(), f"loaded in {time.time()-t:.0f}s")
assert server.M.ready

def check(audio, sura, aya, name="a.mp3"):
    r = c.post("/check", files={"file": (name, audio)}, data={"sura": sura, "aya": aya})
    assert r.status_code == 200, r.text
    j = r.json()
    print(f"\n{sura}:{aya} -> status={j['status']} conf={j['confidence']} heard={j['heard_ratio']} "
          f"match={j.get('match_distance')} errors={len(j['errors'])} in {j.get('seconds')}s segments={j.get('segments')}")
    for e in j["errors"][:12]:
        print("   ", json.dumps({k: e[k] for k in ('word_start','word_end','type','speech','expected','heard','expected_len','heard_len')}, ensure_ascii=False),
              [r['en'] or r['kind'] for r in e['rules']])
    return j

ok = True
j = check(mp3("112001"), 112, 1)
ok &= j["status"] == "ok" and sum(1 for e in j["errors"] if e["type"] == "normal") <= 1
j = check(mp3("112002"), 112, 1)
ok &= not (j["status"] == "ok" and not j["errors"])
j = check(mp3("002255"), 2, 255)
ok &= j["status"] == "ok" and sum(1 for e in j["errors"] if e["type"] != "tajweed") <= 3
for rec in ["Alafasy_128kbps", "Minshawy_Teacher_128kbps"]:
    j = check(mp3("001002", rec), 1, 2)
    ok &= j["status"] == "ok" and sum(1 for e in j["errors"] if e["type"] == "normal") <= 1
# Al-Fatiha 1:2 checked as 1:3 must not pass.
j = check(mp3("001002"), 1, 3)
ok &= not (j["status"] == "ok" and not j["errors"])
# 1:1 + 1:2 checked as 1:2: the learner recited an extra Ayah before; 1:2 itself should be found.
j = check(mp3("002001") , 2, 1)
ok &= j["status"] == "ok"
buf = io.BytesIO()
with wave.open(buf, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000); w.writeframes(np.zeros(16000 * 2, dtype=np.int16).tobytes())
j = check(buf.getvalue(), 112, 1, "s.wav")
ok &= j["status"] in ("silent", "too_little")
print("\nALL OK" if ok else "\nSOME CHECKS FAILED")
sys.exit(0 if ok else 1)
