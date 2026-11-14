"""CI check of the teacher on real recitations (EveryAyah).

Checks: correct recitations pass; a wrong Ayah doesn't; a whole section (Al-Fatiha
1-7) in one go; the streaming API; background noise; a skipped phrase; fair use.
Prints timings so speed can be watched over time.
"""
import io, json, subprocess, sys, time, urllib.request, wave
import numpy as np
from fastapi.testclient import TestClient

import app as server
import engine
import fairuse

SR = 16000


def mp3(path, reciter="Husary_Muallim_128kbps"):
    return urllib.request.urlopen(f"https://everyayah.com/data/{reciter}/{path}.mp3", timeout=60).read()


def pcm(audio_bytes) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", "pipe:0", "-ac", "1", "-ar", str(SR), "-f", "s16le", "pipe:1"],
                         input=audio_bytes, capture_output=True).stdout
    return np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0


def wav(x: np.ndarray) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR)
        f.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())
    return buf.getvalue()


H = {"X-Hifz-App": fairuse.APP_HEADER, "X-Hifz-Device": "ci-device-0001"}
c = TestClient(server.app, headers=H)
fairuse.DAILY_LIMIT = 1000
t = time.time()
engine.M.load()
print("health", c.get("/health").json(), f"loaded in {time.time()-t:.0f}s")
assert engine.M.ready


def show(j, label):
    mistakes = [(a["aya"], e) for a in j["ayahs"] for e in a["errors"] if e["severity"] == "mistake"]
    tips = sum(1 for a in j["ayahs"] for e in a["errors"] if e["severity"] == "tip")
    print(f"\n{label}: status={j['status']} conf={j['confidence']} breaths={j['breaths_used']}/{j['breaths']} "
          f"ayahs={[a['status'][0] for a in j['ayahs']]} mistakes={len(mistakes)} tips={tips} "
          f"audio={j['seconds_audio']}s took={j['seconds']}s (compare {j['seconds_compare']}s)")
    for a, e in mistakes[:10]:
        print("    ", a, json.dumps({k: e[k] for k in ("word_start", "word_end", "type", "speech", "expected", "heard", "expected_len", "heard_len")}, ensure_ascii=False),
              [r["kind"] for r in e["rules"]])
    return mistakes


def check(audio, sura, a0, a1=None, name="a.mp3", strict=False):
    data = {"sura": sura, "aya_from": a0, "strict": str(strict).lower()}
    if a1:
        data["aya_to"] = a1
    r = c.post("/check", files={"file": (name, audio)}, data=data)
    assert r.status_code == 200, r.text
    return r.json()


ok = True

# Fair use.
raw = TestClient(server.app)
ok &= raw.post("/check", data={"sura": 1, "aya": 1}, files={"file": ("a.wav", b"x")}).status_code == 401
ok &= c.get("/family", headers={"X-Hifz-Family": "HIFZ-0000-0000-0000"}).json()["family"] is False

# Old apps send `aya` only and read `words`/`errors`.
r = c.post("/check", files={"file": ("a.mp3", mp3("112001"))}, data={"sura": 112, "aya": 1}).json()
ok &= r["status"] == "ok" and r["words"] and r["errors"] == []
print("compat ok:", r["status"], r["words"], r["errors"])

j = check(mp3("112001"), 112, 1); m = show(j, "112:1 Husary"); ok &= j["status"] == "ok" and not m
j = check(mp3("112002"), 112, 1); m = show(j, "112:2 checked as 112:1"); ok &= not (j["status"] == "ok" and not m)
j = check(mp3("002255"), 2, 255); m = show(j, "2:255 Husary"); ok &= j["status"] == "ok" and len(m) <= 2
for rec in ["Alafasy_128kbps", "Minshawy_Teacher_128kbps", "Abdul_Basit_Murattal_192kbps"]:
    j = check(mp3("001002", rec), 1, 2); m = show(j, f"1:2 {rec}"); ok &= j["status"] == "ok" and len(m) <= 1
    js = check(mp3("001002", rec), 1, 2, strict=True); show(js, f"1:2 {rec} STRICT")

# A whole section in one go: Al-Fatiha 1-7 with short pauses between Ayahs.
gap = np.zeros(int(0.8 * SR), dtype=np.float32)
fatiha = np.concatenate(sum([[pcm(mp3(f"0010{a:02d}")), gap] for a in range(1, 8)], []))
j = check(wav(fatiha), 1, 1, 7, "fatiha.wav"); m = show(j, "Al-Fatiha 1-7 in one go")
ok &= j["status"] == "ok" and all(a["status"] == "recited" for a in j["ayahs"]) and len(m) <= 2

# The same section, stopping after Ayah 4: Ayahs 5-7 are 'not recited', not failed.
part = np.concatenate(sum([[pcm(mp3(f"0010{a:02d}")), gap] for a in range(1, 5)], []))
j = check(wav(part), 1, 1, 7, "part.wav"); show(j, "Al-Fatiha, stopped after 4")
ok &= [a["status"] for a in j["ayahs"]] == ["recited"] * 4 + ["not_recited"] * 3

# Streaming: send 2-second pieces as if live, then time how quickly the result comes.
r = c.post("/session", data={"sura": 1, "aya_from": 1, "aya_to": 7})
sid = r.json()["id"]
pcm16 = (np.clip(fatiha, -1, 1) * 32767).astype("<i2").tobytes()
step = 2 * SR * 2
n = 0
for i in range(0, len(pcm16), step):
    rr = c.post(f"/session/{sid}/audio", params={"seq": n}, content=pcm16[i:i + step],
                headers={"Content-Type": "application/octet-stream"})
    assert rr.status_code == 200, rr.text
    n += 1
    time.sleep(1.0)  # (faster than real time, but leaves the model time to keep up)
t = time.time()
j = c.post(f"/session/{sid}/finish", params={"last_seq": n - 1}).json()
print(f"\nSTREAMING: result {time.time()-t:.2f}s after 'done'")
m = show(j, "Al-Fatiha streamed")
ok &= j["status"] == "ok" and len(m) <= 2

# Background noise: a fan-like hum and hiss at about 15 dB below the voice.
x = pcm(mp3("112001"))
rng = np.random.default_rng(0)
tt = np.arange(len(x)) / SR
noise = 0.5 * np.sin(2 * np.pi * 120 * tt) + rng.normal(0, 1, len(x))
noise *= np.sqrt(np.mean(x ** 2) / np.mean(noise ** 2)) * 10 ** (-15 / 20)
pad = 0.3 * rng.normal(0, 1, 2 * SR) * np.sqrt(np.mean(noise ** 2))
noisy = np.concatenate([pad, x + noise, pad])
j = check(wav(noisy), 112, 1, name="noisy.wav"); m = show(j, "112:1 with background noise")
ok &= j["status"] in ("ok", "unclear") and not m

# A skipped phrase: drop the middle breath of 1:7; its words must be reported missing.
from silero_vad import get_speech_timestamps, load_silero_vad
import torch
x = pcm(mp3("001007"))
ts = get_speech_timestamps(torch.from_numpy(x), load_silero_vad(), sampling_rate=SR, min_silence_duration_ms=350)
print("1:7 breaths:", len(ts))
if len(ts) >= 3:
    keep = [x[t["start"]:t["end"]] for k, t in enumerate(ts) if k != len(ts) // 2]
    audio = np.concatenate(sum([[k, gap] for k in keep], []))
    j = check(wav(audio), 1, 7, name="skip.wav"); m = show(j, "1:7 with a phrase skipped")
    ok &= any(e["type"] == "word" and e["speech"] == "delete" for _, e in m)

# Silence.
j = check(wav(np.zeros(2 * SR, dtype=np.float32)), 112, 1, name="s.wav"); show(j, "silence")
ok &= j["status"] in ("silent", "too_little")

# Daily limit.
fairuse.DAILY_LIMIT = 0
r = c.post("/check", files={"file": ("a.mp3", mp3("112001"))}, data={"sura": 112, "aya": 1})
print("limit ->", r.status_code, r.text[:120])
ok &= r.status_code == 429

# Speed: full-precision vs 8-bit model on Ayat al-Kursi (information only).
x = pcm(mp3("002255"))
ts = get_speech_timestamps(torch.from_numpy(x), load_silero_vad(), sampling_rate=SR, min_silence_duration_ms=350)
parts = [x[t["start"]:t["end"]] for t in ts]
t = time.time(); a = [engine.M.phonemes(p)[0] for p in parts]; t_fp = time.time() - t
import os
os.environ["HIFZ_INT8"] = "1"
q = engine.Model(); q.load()
t = time.time(); b = [q.phonemes(p)[0] for p in parts]; t_q = time.time() - t
import Levenshtein as lv
diff = sum(lv.distance(u, v) for u, v in zip(a, b)) / max(1, sum(len(u) for u in a))
print(f"\nSPEED 2:255 ({len(x)/SR:.0f}s audio): fp32 {t_fp:.1f}s, int8 {t_q:.1f}s, phoneme difference {diff:.3%}")

print("\nALL OK" if ok else "\nSOME CHECKS FAILED")
sys.exit(0 if ok else 1)
