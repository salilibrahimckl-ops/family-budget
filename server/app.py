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

import librosa
import numpy as np
import torch
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
import Levenshtein as lv
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
    """Splits the recitation into breaths: every pause of about a third of a second or
    more is treated as a stop (waqf), because that's how the next word must then be
    pronounced. Very long breaths are cut evenly to fit the model."""
    intervals = librosa.effects.split(wave, top_db=35, frame_length=1024, hop_length=256)
    if len(intervals) == 0:
        return []
    merged: list[list[int]] = []
    for s, e in intervals:
        if merged and (s - merged[-1][1]) / SR < 0.3:
            merged[-1][1] = e  # a tiny gap inside a word or between letters
        else:
            merged.append([s, e])
    pad = int(0.12 * SR)
    out = []
    for s, e in merged:
        s, e = max(0, s - pad), min(len(wave), e + pad)
        n = int(np.ceil((e - s) / SR / CHUNK_SECONDS))
        step = int(np.ceil((e - s) / n))
        out += [wave[s + k * step: min(e, s + (k + 1) * step)] for k in range(n)]
    return [w for w in out if len(w) > 0.25 * SR]


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


def _reference(sura: int, aya: int) -> tuple[list[str], int, list[int]]:
    """Words the learner may recite: optional Isti'adha and (for the first Ayah) Basmala,
    then the Ayah. Returns (all words, index of the Ayah's first word, allowed start words)."""
    a = Aya(sura, aya).get()
    ayah_words = a.uthmani.split(" ")
    prefix: list[str] = []
    starts = []
    if a.istiaatha_uthmani:
        starts.append(len(prefix))
        prefix += a.istiaatha_uthmani.split(" ")
    if aya == 1 and a.bismillah_uthmani:
        starts.append(len(prefix))
        prefix += a.bismillah_uthmani.split(" ")
    starts.append(len(prefix))
    return prefix + ayah_words, len(prefix), starts


class _Phon:
    """Cached phonetic script of word ranges. A range is phonetized on its own, so its
    last word is read as a stop (waqf) and its first word as a fresh start, exactly as
    a learner who pauses mid-Ayah pronounces them."""

    def __init__(self, words: list[str], moshaf: MoshafAttributes, sura: int):
        self.words, self.moshaf, self.sura, self.cache = words, moshaf, sura, {}
        self.word_len = [max(1, len(self.get(i, i).phonemes)) for i in range(len(words))]

    def text(self, s: int, e: int) -> str:
        return " ".join(self.words[s:e + 1])

    def get(self, s: int, e: int):
        k = (s, e)
        if k not in self.cache:
            self.cache[k] = quran_phonetizer(self.text(s, e), self.moshaf, remove_spaces=True, sura_idx=self.sura)
        return self.cache[k]


def _align(segs_ph: list[str], ph: _Phon, ayah_start: int, starts: list[int]) -> list[tuple[int, int, int, float]]:
    """Finds which words each breath (segment) covers. Learners may repeat a word or two
    when they resume after a pause, so a segment may start slightly before where the last
    one ended. Returns (segment index, first word, last word, distance 0-1)."""
    n = len(ph.words)
    out, pointer = [], None
    for k, seg in enumerate(segs_ph):
        if not seg:
            continue
        L = len(seg)
        if pointer is None:
            cand_s = sorted(set(starts))
        else:
            # resume where they stopped, repeat a few words, or start the Ayah again
            cand_s = sorted(set(range(max(0, pointer - 3), min(n, pointer + 2))) | {ayah_start})
        best = None
        for s0 in cand_s:
            acc = 0
            for e in range(s0, n):
                acc += ph.word_len[e]
                if acc < 0.5 * L:
                    continue
                if acc > 1.7 * L + 4:
                    break
                ref = ph.get(s0, e).phonemes
                d = lv.distance(seg, ref) / max(len(seg), len(ref))
                if best is None or d < best[0] - 1e-9 or (abs(d - best[0]) < 1e-9 and e > best[2]):
                    best = (d, s0, e)
        if best is None:  # very short or unusual: give it the next word
            s0 = cand_s[0] if pointer is None else min(n - 1, pointer)
            best = (1.0, s0, s0)
        d, s0, e = best
        out.append((k, s0, e, d))
        pointer = e + 1
    return out


def _explain(ph: _Phon, s: int, e: int, predicted: str, ayah_start: int, n_ayah: int) -> tuple[list[dict], int]:
    ref = ph.get(s, e)
    text = ph.text(s, e)
    errors = explain_error(uthmani_text=text, ref_ph_text=ref.phonemes, predicted_ph_text=predicted, mappings=ref.mappings)
    found, wrong = [], 0
    for er in errors:
        a, b = er.uthmani_pos
        w0 = s + text[:a].count(" ") - ayah_start
        w1 = s + text[:max(a, b - 1)].count(" ") - ayah_start
        if w1 < 0 or w0 >= n_ayah:
            continue  # inside the Isti'adha/Basmala
        w0, w1 = max(0, w0), min(w1, n_ayah - 1)
        rules = [_rule(r) for r in (er.ref_tajweed_rules or [])]
        if er.error_type == "tajweed" and er.predicted_len is not None:
            allowed = set()
            for r in rules:
                allowed |= _ALLOWED.get(r["en"], set()) | _ALLOWED_KIND.get(r["kind"], set())
            if er.predicted_len in allowed:
                continue
        if er.error_type == "normal":
            wrong += max(len(er.expected_ph), len(er.preditected_ph), 1)
        found.append({
            "word_start": w0,
            "word_end": w1,
            "type": er.error_type,  # 'normal' (letters/words) | 'tashkeel' | 'tajweed'
            "speech": er.speech_error_type,  # insert | delete | replace
            "expected": er.expected_ph,
            "heard": er.preditected_ph,
            "expected_len": er.expected_len,
            "heard_len": er.predicted_len,
            "rules": rules,
            "missing_rules": [_rule(r) for r in (er.missing_tajweed_rules or [])],
            "extra_rules": [_rule(r) for r in (er.inserted_tajweed_rules or [])],
        })
    return found, wrong


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
        words = Aya(sura, aya).get().uthmani.split(" ")
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
    words_all, ayah_start, starts = _reference(sura, aya)
    n_ayah = len(words_all) - ayah_start
    ph = _Phon(words_all, moshaf, sura)
    segs_ph = [p for p, _ in parts]
    spans = _align(segs_ph, ph, ayah_start, starts)

    # Errors per word: a word recited more than once (repeated after a pause) is judged
    # by its last recitation.
    by_word: dict[int, list[dict]] = {}
    covered: set[int] = set()
    wrong = 0
    for k, s0, e, _ in spans:
        found, w = _explain(ph, s0, e, segs_ph[k], ayah_start, n_ayah)
        wrong += w
        span_words = {i - ayah_start for i in range(s0, e + 1) if i >= ayah_start}
        for i in span_words:
            by_word[i] = [f for f in found if f["word_start"] <= i <= f["word_end"]]
        covered |= span_words
    for i in range(n_ayah):
        if i not in covered:
            by_word[i] = [{
                "word_start": i, "word_end": i, "type": "normal", "speech": "delete",
                "expected": ph.get(ayah_start + i, ayah_start + i).phonemes, "heard": "",
                "expected_len": None, "heard_len": None, "rules": [], "missing_rules": [], "extra_rules": [],
            }]
    seen, found = set(), []
    for i in sorted(by_word):
        for f in by_word[i]:
            key = (f["word_start"], f["word_end"], f["type"], f["expected"], f["heard"])
            if key not in seen:
                seen.add(key)
                found.append(f)

    ref_len = sum(ph.word_len[ayah_start:])
    seg_w = [max(1, len(segs_ph[k])) for k, *_ in spans]
    match_dist = float(np.average([d for *_, d in spans], weights=seg_w)) if spans else 1.0
    heard_ratio = len(covered) / max(1, n_ayah)
    missing = n_ayah - len(covered)
    if heard_ratio < 0.4 and match_dist > 0.5 and confidence > 0.8:
        status = "different_ayah"  # clearly recited, but not this Ayah
    elif heard_ratio < 0.4:
        status = "too_little"  # recited only part of it, or the microphone didn't catch it
    elif match_dist > 0.5 or (wrong + sum(ph.word_len[ayah_start + i] for i in range(n_ayah) if i not in covered)) / max(1, ref_len) > 0.6:
        status = "different_ayah"  # mostly doesn't match: probably another Ayah
    elif confidence < 0.55:
        status = "unclear"  # noisy or unclear audio: findings are unreliable
    else:
        status = "ok"
    ref_ph = ph.get(ayah_start, len(words_all) - 1).phonemes
    return {
        **base,
        "status": status,
        "errors": found if status in ("ok", "unclear") else [],
        "heard_ratio": round(heard_ratio, 3),
        "confidence": round(confidence, 3),
        "predicted_phonemes": predicted,
        "reference_phonemes": ref_ph,
        "segments": [{"words": [s0 - ayah_start, e - ayah_start], "distance": round(d, 3)} for k, s0, e, d in spans],
        "match_distance": round(match_dist, 3),
        "missing_words": missing,
        "seconds": round(time.time() - t0, 2),
    }
