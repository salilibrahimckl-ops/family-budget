"""Hifz Academy recitation teacher.

Listens to one recited Ayah and reports, word by word:
  - missed, extra or wrong words and letters,
  - wrong harakat (short vowels),
  - Tajweed: every Madd type (with the counts held), Ghunnah, Qalqalah, Idgham.

It runs the open-source Quran Muaalem model (obadx/muaalem-model-v3_2, Quran Muaalem
License): the recitation is turned into Quran phonetic script, then compared with the
phonetic script of the verified Uthmani text of that Ayah (Tanzil Uthmani 1.1, via
quran-transcript). Nothing is generated: the Quran text comes from the verified source
and every finding is a comparison against it.

AI advisory notice (required by the Quran Muaalem License, section 2.1):
  This Quranic Teacher is an artificial-intelligence model that may make mistakes. It is
  intended for assistance only and must not be relied upon. It is not a replacement for
  a proficient, authorized teacher, because the Quran is only received through oral
  transmission (mushafahah).

Audio is processed in memory and deleted after the check; nothing is stored.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
import threading
import time
from dataclasses import dataclass

import librosa
import numpy as np
import torch
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from quran_transcript import Aya, MoshafAttributes, explain_error, quran_phonetizer
from transformers import AutoFeatureExtractor

from quran_muaalem.modeling.modeling_multi_level_ctc import Wav2Vec2BertForMultilevelCTC
from quran_muaalem.modeling.multi_level_tokenizer import MultiLevelTokenizer

MODEL = os.environ.get("MUAALEM_MODEL", "obadx/muaalem-model-v3_2")
SR = 16000
CHUNK_SECONDS = 14.0  # the model was trained on segments up to ~15 s
MAX_SECONDS = 180.0
NOTICE = {
    "en": "This Quranic Teacher is an artificial-intelligence model that may make mistakes. "
    "It is intended for assistance only and must not be relied upon. It is not a replacement "
    "for a proficient, authorized teacher, because the Quran is only received through oral "
    "transmission (mushafahah).",
    "ar": "هذا المعلّم القرآني نموذج ذكاء اصطناعي قد يخطئ؛ فهو للإعانة فقط ولا يُعتمد عليه، "
    "وليس بديلاً عن معلّمٍ مُتقِنٍ مُجاز؛ لأنّ القرآن لا يُؤخذ إلا بالمشافهة.",
}

torch.set_num_threads(max(1, os.cpu_count() or 1))

app = FastAPI(title="Hifz Academy recitation teacher")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


class _Model:
    def __init__(self) -> None:
        self.ready = False
        self.error: str | None = None
        self.lock = threading.Lock()  # one recitation at a time on a small CPU

    def load(self) -> None:
        try:
            self.processor = AutoFeatureExtractor.from_pretrained(MODEL)
            self.tokenizer = MultiLevelTokenizer(MODEL)
            self.model = Wav2Vec2BertForMultilevelCTC.from_pretrained(MODEL)
            self.model.to("cpu", dtype=torch.float32).eval()
            self.ready = True
        except Exception as e:  # reported by /health
            self.error = f"{type(e).__name__}: {e}"

    def phonemes(self, wave: np.ndarray) -> tuple[str, float]:
        """Phonetic transcription of one segment, and the mean confidence of the
        phonemes the model emitted (0-1)."""
        feats = self.processor(wave, sampling_rate=SR, return_tensors="pt")
        with torch.inference_mode():
            out = self.model(feats["input_features"], feats.get("attention_mask"), return_dict=False)[0]
        probs = torch.softmax(out["phonemes"][0].float(), dim=-1)
        top_p, top_id = probs.max(dim=-1)
        vocab = self.tokenizer.id_to_vocab["phonemes"]
        text, confs, prev = [], [], 0
        for p, i in zip(top_p.tolist(), top_id.tolist()):
            if i != 0 and i != prev:
                text.append(vocab[int(i)])
                confs.append(p)
            prev = i
        return "".join(text), (float(np.mean(confs)) if confs else 0.0)


M = _Model()
threading.Thread(target=M.load, daemon=True).start()


def _decode(data: bytes, filename: str) -> np.ndarray:
    """Any phone/browser format (wav, m4a, webm/opus, ogg, mp3) -> 16 kHz mono."""
    suffix = os.path.splitext(filename or "")[1] or ".bin"
    with tempfile.TemporaryDirectory() as d:
        src, dst = os.path.join(d, "in" + suffix), os.path.join(d, "out.wav")
        with open(src, "wb") as f:
            f.write(data)
        r = subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-y", "-i", src, "-ac", "1", "-ar", str(SR), dst],
                           capture_output=True)
        if r.returncode != 0:
            raise HTTPException(400, "Could not read the recording.")
        wave, _ = librosa.load(dst, sr=SR, mono=True)
    return wave


def _segments(wave: np.ndarray) -> list[np.ndarray]:
    """Trims silence and splits long recitations at pauses into segments the model handles."""
    intervals = librosa.effects.split(wave, top_db=35, frame_length=1024, hop_length=256)
    if len(intervals) == 0:
        return []
    pad = int(0.15 * SR)
    segs, cur_s, cur_e = [], None, None
    for s, e in intervals:
        s, e = max(0, s - pad), min(len(wave), e + pad)
        if cur_s is None:
            cur_s, cur_e = s, e
        elif (e - cur_s) / SR <= CHUNK_SECONDS:
            cur_e = e
        else:
            segs.append((cur_s, cur_e))
            cur_s, cur_e = s, e
    segs.append((cur_s, cur_e))
    out = []
    for s, e in segs:  # a single breath longer than the limit is cut evenly
        n = int(np.ceil((e - s) / SR / CHUNK_SECONDS))
        step = int(np.ceil((e - s) / n))
        out += [wave[s + k * step: min(e, s + (k + 1) * step)] for k in range(n)]
    return [w for w in out if len(w) > 0.2 * SR]


# Accepted lengths (in counts) where scholars of Hafs allow a choice. A Madd held for any
# of these is not reported as a mistake.
_ALLOWED = {
    "Aared Madd": {2, 4, 6},
    "Leen Madd": {2, 4, 6},
    "Monfasel Madd": {2, 3, 4, 5},
    "Mottasel Madd": {4, 5, 6},
    "Mottasel Madd at Pause": {4, 5, 6},
}


_ALLOWED_KIND = {
    "AaredMaddRule": {2, 4, 6},
    "LeenMaddRule": {2, 4, 6},
    "MonfaselMaddRule": {2, 3, 4, 5},
    "MottaselMaddRule": {4, 5, 6},
    "MottaselMaddPauseRule": {4, 5, 6},
}


def _rule(r) -> dict:
    name = getattr(r, "name", None)
    return {
        "kind": type(r).__name__,  # e.g. LazemMaddRule, Qalqalah, Ghonnah
        "tag": getattr(r, "tag", None),
        "ar": getattr(name, "ar", "") or "",
        "en": getattr(name, "en", "") or "",
        "golden_len": getattr(r, "golden_len", None),
        "type": getattr(r, "correctness_type", None),
    }


@dataclass
class _Candidate:
    prefix_words: int
    text: str


def _candidates(sura: int, aya: int) -> tuple[list[_Candidate], list[str]]:
    a = Aya(sura, aya).get()
    words = a.uthmani.split(" ")
    out = [_Candidate(0, a.uthmani)]
    # Learners often begin with the Isti'adha and/or the Basmala; don't count those as mistakes.
    prefixes = [a.istiaatha_uthmani]
    if aya == 1 and a.bismillah_uthmani:
        prefixes += [a.bismillah_uthmani, f"{a.istiaatha_uthmani} {a.bismillah_uthmani}"]
    for p in prefixes:
        if p:
            out.append(_Candidate(len(p.split(" ")), f"{p} {a.uthmani}"))
    return out, words


def _analyse(text: str, prefix_words: int, n_words: int, predicted: str, moshaf: MoshafAttributes, sura: int):
    ref = quran_phonetizer(text, moshaf, remove_spaces=True, sura_idx=sura)
    errors = explain_error(uthmani_text=text, ref_ph_text=ref.phonemes, predicted_ph_text=predicted, mappings=ref.mappings)
    found, cost = [], 0
    for e in errors:
        start, end = e.uthmani_pos
        w0 = text[:start].count(" ") - prefix_words
        w1 = text[:max(start, end - 1)].count(" ") - prefix_words
        if w1 < 0:
            continue  # inside the Isti'adha/Basmala
        w0 = max(0, w0)
        rules = [_rule(r) for r in (e.ref_tajweed_rules or [])]
        if e.error_type == "tajweed" and e.predicted_len is not None:
            allowed = set()
            for r in rules:
                allowed |= _ALLOWED.get(r["en"], set()) | _ALLOWED_KIND.get(r["kind"], set())
            if e.predicted_len in allowed:
                continue
        cost += max(len(e.expected_ph), len(e.preditected_ph), 1)
        found.append({
            "word_start": w0,
            "word_end": min(w1, n_words - 1),
            "type": e.error_type,  # 'normal' (letters/words) | 'tashkeel' | 'tajweed'
            "speech": e.speech_error_type,  # insert | delete | replace
            "expected": e.expected_ph,
            "heard": e.preditected_ph,
            "expected_len": e.expected_len,
            "heard_len": e.predicted_len,
            "rules": rules,
            "missing_rules": [_rule(r) for r in (e.missing_tajweed_rules or [])],
            "extra_rules": [_rule(r) for r in (e.inserted_tajweed_rules or [])],
        })
    return found, cost, ref.phonemes


@app.get("/")
def root():
    return {"service": "Hifz Academy recitation teacher", "model": MODEL, "notice": NOTICE}


@app.get("/health")
def health():
    return {"ready": M.ready, "error": M.error, "model": MODEL}


@app.post("/check")
async def check(
    file: UploadFile = File(...),
    sura: int = Form(...),
    aya: int = Form(...),
    madd_monfasel_len: int = Form(4),
    madd_mottasel_len: int = Form(4),
    madd_aared_len: int = Form(4),
):
    if not M.ready:
        raise HTTPException(503, M.error or "The teacher is waking up. Try again in a minute.")
    t0 = time.time()
    try:
        candidates, words = _candidates(sura, aya)
    except Exception:
        raise HTTPException(400, "Unknown Surah or Ayah.")
    wave = _decode(await file.read(), file.filename or "audio.webm")
    if len(wave) > MAX_SECONDS * SR:
        raise HTTPException(413, "Recording is too long. Please recite one Ayah at a time.")
    segs = _segments(wave)

    base = {"sura": sura, "aya": aya, "words": words, "notice": NOTICE, "model": MODEL}
    if not segs:
        return {**base, "status": "silent", "errors": [], "heard_ratio": 0.0, "confidence": 0.0}

    with M.lock:
        parts = [M.phonemes(s) for s in segs]
    predicted = "".join(p for p, _ in parts)
    lens = [max(1, len(p)) for p, _ in parts]
    confidence = float(np.average([c for _, c in parts], weights=lens))

    moshaf = MoshafAttributes(
        rewaya="hafs",
        madd_monfasel_len=madd_monfasel_len,
        madd_mottasel_len=madd_mottasel_len,
        madd_mottasel_waqf=madd_mottasel_len,
        madd_aared_len=madd_aared_len,
    )
    best = None
    for c in candidates:
        found, cost, ref_ph = _analyse(c.text, c.prefix_words, len(words), predicted, moshaf, sura)
        if best is None or cost < best[1]:
            best = (found, cost, ref_ph)
    found, cost, ref_ph = best

    ref_len = len(quran_phonetizer(candidates[0].text, moshaf, remove_spaces=True, sura_idx=sura).phonemes)
    heard_ratio = len(predicted) / max(1, ref_len)
    wrong = sum(max(len(e["expected"]), len(e["heard"])) for e in found if e["type"] == "normal")
    if heard_ratio < 0.4:
        status = "too_little"  # recited only part of it, or the microphone didn't catch it
    elif wrong / max(1, ref_len) > 0.6:
        status = "different_ayah"  # mostly doesn't match: probably another Ayah
    elif confidence < 0.55:
        status = "unclear"  # noisy or unclear audio: findings are unreliable
    else:
        status = "ok"
    return {
        **base,
        "status": status,
        "errors": found if status in ("ok", "unclear") else [],
        "heard_ratio": round(heard_ratio, 3),
        "confidence": round(confidence, 3),
        "predicted_phonemes": predicted,
        "reference_phonemes": ref_ph,
        "seconds": round(time.time() - t0, 2),
    }
