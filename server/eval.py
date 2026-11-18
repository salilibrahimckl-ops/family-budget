"""Stress test of the AI teacher on many real recitations.

Every recording used is a correct recitation by a known reciter, so anything the teacher
calls a mistake on the clean, phone and learner versions is a false mistake. Then real
mistakes are put in on purpose (a skipped phrase, a wrong Ayah) to check they are still
caught, and that the "You" clip points at the right place.

Usage: python eval.py <shard> <shards>    (writes eval-<shard>.json and prints a report)
"""
import json, os, random, subprocess, sys, time, urllib.request
import numpy as np

if len(sys.argv) > 1 and sys.argv[1] == "debug":
    os.environ["HIFZ_DEBUG"] = "1"

import app as server
import engine

SR = 16000

RECITERS = [
    "Husary_128kbps", "Alafasy_128kbps", "Minshawy_Murattal_128kbps", "Abdul_Basit_Murattal_192kbps",
    "Ghamadi_40kbps", "Hudhaify_128kbps", "Muhammad_Ayyoub_128kbps", "Abdullah_Basfar_192kbps",
    "Ali_Jaber_64kbps", "Husary_Muallim_128kbps", "Minshawy_Teacher_128kbps", "Karim_Mansoori_40kbps",
    "Parhizgar_48kbps", "aziz_alili_128kbps", "Ayman_Sowaid_64kbps", "Muhammad_Jibreel_128kbps",
    "Abu_Bakr_Ash-Shaatree_128kbps", "Yasser_Ad-Dussary_128kbps", "Nasser_Alqatami_128kbps",
    "Salaah_AbdulRahman_Bukhatir_128kbps", "Fares_Abbad_64kbps", "Hani_Rifai_192kbps",
    "Saood_ash-Shuraym_128kbps", "MaherAlMuaiqly128kbps",
]
PASSAGES = [(1, 1, 7), (112, 1, 4), (63, 1, 3), (2, 255, 255), (67, 1, 4), (36, 1, 8), (78, 1, 8),
            (103, 1, 3), (114, 1, 6), (2, 1, 5), (18, 1, 3), (55, 1, 9), (93, 1, 11), (63, 6, 8)]


def fetch(reciter, sura, aya):
    url = f"https://everyayah.com/data/{reciter}/{sura:03d}{aya:03d}.mp3"
    for _ in range(3):
        try:
            data = urllib.request.urlopen(url, timeout=60).read()
            raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", "pipe:0", "-ac", "1", "-ar", str(SR), "-f", "s16le", "pipe:1"],
                                 input=data, capture_output=True).stdout
            x = np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768.0
            # Trim long silence at the ends (some files have seconds of it).
            env = np.convolve(np.abs(x), np.ones(400) / 400, mode="same")
            idx = np.where(env > 0.003)[0]
            if len(idx) == 0:
                return None
            return x[max(0, idx[0] - 4800): idx[-1] + 4800]
        except Exception:
            time.sleep(2)
    return None


def phone(x, rng, snr_db):
    f = np.fft.rfft(x); fr = np.fft.rfftfreq(len(x), 1 / SR)
    f[(fr < 100) | (fr > 7000)] = 0
    y = np.fft.irfft(f, len(x)).astype(np.float32) * rng.uniform(0.3, 0.8)
    r = rng.normal(0, 1, len(y))
    r *= np.sqrt(np.mean(y ** 2) / np.mean(r ** 2)) * 10 ** (-snr_db / 20)
    return (y + r).astype(np.float32)


def gap(rng, a=0.5, b=1.4):
    return (np.random.default_rng(int(rng.integers(1 << 30))).normal(0, 0.002, int(SR * rng.uniform(a, b)))).astype(np.float32)


def run(audio, sura, a0, a1):
    ref = server._reference(sura, a0, a1, server._moshaf(4, 4, 4)) if hasattr(server, "_reference") else \
        engine.build_reference(sura, a0, a1, server._moshaf(4, 4, 4))
    rec = engine.Recording()
    for i in range(0, len(audio), 2 * SR):  # the app sends 2-second pieces
        rec.feed(audio[i:i + 2 * SR])
    segs = rec.finish()
    return engine.analyse(segs, ref, strict=False), ref


def mistakes(res):
    out = []
    for a in res["ayahs"]:
        for e in a["errors"]:
            if e["severity"] == "mistake":
                out.append((a["aya"], a["words"], e))
    return out


def main():
    shard, shards = int(sys.argv[1]), int(sys.argv[2])
    engine.M.load()
    rows, falses, recall = [], [], []
    for ri, reciter in enumerate(RECITERS):
        if ri % shards != shard:
            continue
        rng = np.random.default_rng(ri * 7919 + 13)
        picks = [PASSAGES[k] for k in rng.choice(len(PASSAGES), 4, replace=False)]
        for (sura, a0, a1) in picks:
            ayahs = [fetch(reciter, sura, a) for a in range(a0, a1 + 1)]
            if any(x is None for x in ayahs):
                print(f"skip {reciter} {sura}:{a0}-{a1} (no audio)", flush=True)
                continue
            clean = np.concatenate([np.concatenate([x, gap(rng)]) for x in ayahs])
            scen = {"clean": clean, "phone": phone(clean, rng, rng.uniform(12, 20))}
            # Learner: restarts an Ayah after a few words, and repeats a phrase.
            parts = []
            for k, x in enumerate(ayahs):
                if k == 0 and len(x) > 3 * SR:
                    parts += [x[: int(len(x) * 0.4)], gap(rng, 0.7, 1.2)]
                parts += [x, gap(rng)]
                if k == len(ayahs) - 1 and len(x) > 3 * SR:
                    parts += [x[-int(1.8 * SR):], gap(rng)]
            scen["learner"] = phone(np.concatenate(parts), rng, rng.uniform(14, 22))
            for name, audio in scen.items():
                t = time.time()
                try:
                    res, ref = run(audio, sura, a0, a1)
                except Exception as ex:
                    print("ERROR", reciter, sura, a0, name, repr(ex), flush=True)
                    continue
                ms = mistakes(res)
                tips = sum(1 for a in res["ayahs"] for e in a["errors"] if e["severity"] == "tip")
                notrec = [a["aya"] for a in res["ayahs"] if a["status"] != "recited"]
                rows.append({"reciter": reciter, "passage": f"{sura}:{a0}-{a1}", "scenario": name, "status": res["status"],
                             "mistakes": len(ms), "tips": tips, "not_recited": notrec, "seconds": round(len(audio) / SR, 1),
                             "took": round(time.time() - t, 1), "dropped": res.get("double_checked_away")})
                for aya, words, e in ms:
                    falses.append({"reciter": reciter, "scenario": name, "sura": sura, "aya": aya,
                                   "word": " ".join(words[e["word_start"]:e["word_end"] + 1]), "type": e["type"],
                                   "speech": e["speech"], "expected": e["expected"], "heard": e["heard"],
                                   "exp_len": e.get("expected_len"), "heard_len": e.get("heard_len"),
                                   "rules": [r.get("kind") if isinstance(r, dict) else r for r in e.get("rules", [])]})
                print(f"{reciter:38s} {sura}:{a0}-{a1:<4} {name:8s} status={res['status']:9s} mistakes={len(ms)} tips={tips} "
                      f"not_recited={notrec} audio={len(audio)/SR:.0f}s took={time.time()-t:.0f}s", flush=True)
            # Real mistakes: one skipped phrase, and one Ayah replaced by another Ayah.
            k = int(rng.integers(len(ayahs)))
            x = ayahs[k]
            if len(x) > 4 * SR:
                # the loudest 1.5 s in the middle of the Ayah (so speech, not a pause, is cut)
                w = int(1.5 * SR)
                e2 = np.convolve(x ** 2, np.ones(w), mode="valid")
                lo, hi = int(len(x) * 0.2), max(int(len(x) * 0.2) + 1, int(len(x) * 0.8) - w)
                c0 = lo + int(np.argmax(e2[lo:hi])); c1 = c0 + w
                parts = [np.concatenate([y, gap(rng)]) for y in ayahs]
                start = sum(len(p) for p in parts[:k]) + c0
                parts[k] = np.concatenate([x[:c0], x[c1:], gap(rng)])
                res, _ = run(phone(np.concatenate(parts), rng, 18), sura, a0, a1)
                hit = [e for (aya, _, e) in mistakes(res) if aya == a0 + k and e["type"] == "word"]
                near = any(e.get("at") and e["at"][0] - 1.0 <= start / SR <= e["at"][1] + 1.0 for e in hit)
                recall.append({"reciter": reciter, "kind": "skip", "passage": f"{sura}:{a0 + k}", "caught": bool(hit), "clip_ok": near})
                print(f"{reciter:38s} SKIP {sura}:{a0 + k} caught={bool(hit)} clip_near={near}", flush=True)
            other = fetch(reciter, 113, 2) if sura != 113 else fetch(reciter, 114, 2)
            if other is not None and len(ayahs) >= 2:
                k = 1
                parts = [np.concatenate([y, gap(rng)]) for y in ayahs]
                parts[k] = np.concatenate([other, gap(rng)])
                res, _ = run(phone(np.concatenate(parts), rng, 18), sura, a0, a1)
                bad = [a for a in res["ayahs"] if a["aya"] == a0 + k]
                caught = bool(bad) and (bad[0]["status"] != "recited" or any(e["severity"] == "mistake" for e in bad[0]["errors"]))
                recall.append({"reciter": reciter, "kind": "wrong_ayah", "passage": f"{sura}:{a0 + k}", "caught": caught})
                print(f"{reciter:38s} WRONG-AYAH {sura}:{a0 + k} caught={caught}", flush=True)
    json.dump({"rows": rows, "falses": falses, "recall": recall}, open(f"eval-{shard}.json", "w"), ensure_ascii=False, indent=1)


DEBUG_CASES = [("Minshawy_Teacher_128kbps", 36, 1, 8), ("Hani_Rifai_192kbps", 63, 1, 3), ("Parhizgar_48kbps", 1, 1, 7),
               ("Husary_128kbps", 2, 1, 5), ("Salaah_AbdulRahman_Bukhatir_128kbps", 67, 1, 4),
               ("Muhammad_Ayyoub_128kbps", 114, 1, 6), ("Ali_Jaber_64kbps", 63, 6, 8)]


def debug():
    engine.M.load()
    for reciter, sura, a0, a1 in DEBUG_CASES:
        ayahs = [fetch(reciter, sura, a) for a in range(a0, a1 + 1)]
        if any(x is None for x in ayahs):
            continue
        rng = np.random.default_rng(1)
        audio = np.concatenate([np.concatenate([x, gap(rng)]) for x in ayahs])
        res, ref = run(audio, sura, a0, a1)
        print(f"\n===== {reciter} {sura}:{a0}-{a1} status={res['status']}")
        for d in res.get("debug") or []:
            print("  BREATH", json.dumps(d, ensure_ascii=False))
        for aya, words, e in mistakes(res):
            print("  MISTAKE", aya, " ".join(words[e["word_start"]:e["word_end"] + 1]),
                  json.dumps({k: e.get(k) for k in ("type", "speech", "expected", "heard", "origin", "at")}, ensure_ascii=False))


if __name__ == "__main__":
    debug() if sys.argv[1] == "debug" else main()
