"""The listening and comparing parts of the Hifz Academy recitation teacher.

  Recording  - takes the recitation as it streams in, finds each breath with a voice
               detector (Silero VAD) so background noise and silence are skipped, and
               sends every finished breath to the model straight away (so the result is
               nearly ready by the time the learner stops).
  Model      - Quran Muaalem: audio -> Quran phonetic script.
  Reference  - the verified Uthmani words of one or more Ayahs (Tanzil Uthmani 1.1, via
               quran-transcript) and their phonetic script.
  analyse()  - matches each breath to the words it covers, compares sound by sound, and
               sorts every difference into a real mistake or just a tip.
"""
from __future__ import annotations

import os
import threading
from concurrent.futures import Future, ThreadPoolExecutor
from dataclasses import dataclass, field

import Levenshtein as lv
import numpy as np
import torch
from quran_transcript import Aya, MoshafAttributes, explain_error, quran_phonetizer

MODEL = os.environ.get("MUAALEM_MODEL", "obadx/muaalem-model-v3_2")
SR = 16000
MAX_BREATH_SECONDS = 14.0  # the model was trained on segments up to ~15 s
MAX_SECONDS = 3600.0  # one session: up to an hour of recitation


# --------------------------------------------------------------------- model --
class Model:
    def __init__(self) -> None:
        self.ready = False
        self.error: str | None = None
        self._lock = threading.Lock()

    def load(self) -> None:
        with self._lock:
            if self.ready:
                return
            try:
                from transformers import AutoFeatureExtractor

                from quran_muaalem.modeling.modeling_multi_level_ctc import Wav2Vec2BertForMultilevelCTC
                from quran_muaalem.modeling.multi_level_tokenizer import MultiLevelTokenizer

                self.processor = AutoFeatureExtractor.from_pretrained(MODEL)
                self.tokenizer = MultiLevelTokenizer(MODEL)
                model = Wav2Vec2BertForMultilevelCTC.from_pretrained(MODEL)
                model.to("cpu", dtype=torch.float32).eval()
                if os.environ.get("HIFZ_INT8") == "1":
                    model = torch.ao.quantization.quantize_dynamic(model, {torch.nn.Linear}, dtype=torch.qint8)
                self.model = model
                self.vocab = self.tokenizer.id_to_vocab["phonemes"]
                self.ready = True
            except Exception as e:  # reported by /health
                self.error = f"{type(e).__name__}: {e}"

    def phonemes(self, wave: np.ndarray) -> tuple[str, float]:
        """Phonetic script of one breath, and the model's mean confidence (0-1)."""
        feats = self.processor(wave, sampling_rate=SR, return_tensors="pt")
        with torch.inference_mode():
            out = self.model(feats["input_features"], feats.get("attention_mask"), return_dict=False)[0]
        probs = torch.softmax(out["phonemes"][0].float(), dim=-1)
        top_p, top_id = probs.max(dim=-1)
        text, confs, prev = [], [], 0
        for p, i in zip(top_p.tolist(), top_id.tolist()):
            if i != 0 and i != prev:
                text.append(self.vocab[int(i)])
                confs.append(p)
            prev = i
        return "".join(text), (float(np.mean(confs)) if confs else 0.0)


M = Model()
_EXEC = ThreadPoolExecutor(max_workers=1)  # one breath at a time; torch uses all cores for it


# ----------------------------------------------------------------- recording --
@dataclass
class Breath:
    start: int
    end: int
    future: Future


@dataclass
class Recording:
    """Audio arriving in pieces. Each breath (speech between pauses of a third of a
    second or more) goes to the model as soon as it ends."""

    buf: np.ndarray = field(default_factory=lambda: np.zeros(0, dtype=np.float32))
    pos: int = 0
    cur: int | None = None
    breaths: list = field(default_factory=list)
    lock: threading.Lock = field(default_factory=threading.Lock)

    def __post_init__(self):
        from silero_vad import VADIterator, load_silero_vad

        # Each recording has its own small detector: it keeps state between pieces.
        self.it = VADIterator(load_silero_vad(), threshold=0.5, sampling_rate=SR, min_silence_duration_ms=550, speech_pad_ms=150)
        self.it.reset_states()

    @property
    def seconds(self) -> float:
        return len(self.buf) / SR

    def feed(self, pcm: np.ndarray) -> None:
        with self.lock:
            self.buf = np.concatenate([self.buf, pcm.astype(np.float32)])
            while self.pos + 512 <= len(self.buf):
                ev = self.it(torch.from_numpy(self.buf[self.pos:self.pos + 512].copy()))
                self.pos += 512
                if ev and "start" in ev and self.cur is None:
                    self.cur = int(ev["start"])
                if ev and "end" in ev and self.cur is not None:
                    self._close(self.cur, int(ev["end"]))
                    self.cur = None
                if self.cur is not None and self.pos - self.cur > MAX_BREATH_SECONDS * SR:
                    cut = self._quietest(self.pos - 3 * SR, self.pos)
                    self._close(self.cur, cut)
                    self.cur = cut

    def _quietest(self, a: int, b: int) -> int:
        """Where to split a very long breath: the quietest 20 ms in the window."""
        a = max(a, (self.cur or 0) + SR)
        frame = 320
        if b - a < frame * 2:
            return b
        x = self.buf[a:b]
        n = len(x) // frame
        rms = np.sqrt((x[: n * frame].reshape(n, frame) ** 2).mean(axis=1))
        return a + int(np.argmin(rms)) * frame + frame // 2

    def _close(self, s: int, e: int) -> None:
        s, e = max(0, s), min(len(self.buf), e)
        if e - s < 0.25 * SR:
            return
        wave = self.buf[s:e].copy()
        self.breaths.append(Breath(s, e, _EXEC.submit(M.phonemes, wave)))

    def finish(self) -> list[tuple[str, float]]:
        with self.lock:
            if self.cur is not None:
                self._close(self.cur, len(self.buf))
                self.cur = None
            breaths = list(self.breaths)
        return [b.future.result() for b in breaths]


# ----------------------------------------------------------------- reference --
@dataclass
class Reference:
    sura: int
    aya_from: int
    aya_to: int
    words: list[str]  # all words, Isti'adha/Basmala first
    word_aya: list[int]  # Ayah number of each word (0 for the optional opening)
    word_pos: list[int]  # 0-based position inside its Ayah
    first_starts: list[int]  # where the first breath may begin
    ayah_start: dict[int, int]  # Ayah number -> index of its first word
    phon: object = None
    span: list[int] = field(default_factory=list)  # phoneme index where each word begins
    moshaf: MoshafAttributes = None
    cache: dict = field(default_factory=dict)

    @property
    def n(self) -> int:
        return len(self.words)

    def text(self, s: int, e: int) -> str:
        return " ".join(self.words[s:e + 1])

    def slice(self, s: int, e: int) -> str:
        """Phonetic script of words s..e as part of continuous recitation."""
        return self.phon.phonemes[self.span[s]:self.span[e + 1]]

    def alone(self, s: int, e: int):
        """Phonetic script of words s..e recited on their own (starting fresh and
        stopping at the end, as a learner does around a pause)."""
        k = (s, e)
        if k not in self.cache:
            self.cache[k] = quran_phonetizer(self.text(s, e), self.moshaf, remove_spaces=True, sura_idx=self.sura)
        return self.cache[k]


def build_reference(sura: int, aya_from: int, aya_to: int, moshaf: MoshafAttributes) -> Reference:
    words, word_aya, word_pos, starts = [], [], [], []
    first = Aya(sura, aya_from).get()
    if first.istiaatha_uthmani:
        starts.append(len(words))
        for w in first.istiaatha_uthmani.split(" "):
            words.append(w); word_aya.append(0); word_pos.append(-1)
    if aya_from == 1 and first.bismillah_uthmani:
        starts.append(len(words))
        for w in first.bismillah_uthmani.split(" "):
            words.append(w); word_aya.append(0); word_pos.append(-1)
    ayah_start = {}
    for a in range(aya_from, aya_to + 1):
        ayah_start[a] = len(words)
        for i, w in enumerate(Aya(sura, a).get().uthmani.split(" ")):
            words.append(w); word_aya.append(a); word_pos.append(i)
    starts.append(ayah_start[aya_from])
    ref = Reference(sura, aya_from, aya_to, words, word_aya, word_pos, starts, ayah_start, moshaf=moshaf)
    text = " ".join(words)
    ref.phon = quran_phonetizer(text, moshaf, remove_spaces=True, sura_idx=sura)
    # Where each word's sounds begin, from the character mappings of one phonetization.
    char_word, w = [], 0
    for ch in text:
        char_word.append(w)
        if ch == " ":
            w += 1
    begin = [None] * len(words)
    for ci, m in enumerate(ref.phon.mappings):
        if m is None or ci >= len(char_word) or text[ci] == " ":
            continue
        wi = char_word[ci]
        p = m.pos[0]
        if begin[wi] is None or p < begin[wi]:
            begin[wi] = p
    total = len(ref.phon.phonemes)
    for i in range(len(words) - 1, -1, -1):  # fill gaps from the right
        if begin[i] is None:
            begin[i] = begin[i + 1] if i + 1 < len(words) else total
    for i in range(1, len(words)):  # keep it monotonic
        begin[i] = max(begin[i], begin[i - 1])
    ref.span = begin + [total]
    return ref


# ------------------------------------------------------------------ analysis --
_ALLOWED_KIND = {  # lengths (counts) scholars of Hafs accept as a choice
    "AaredMaddRule": {2, 4, 6},
    "LeenMaddRule": {2, 4, 6},
    "MonfaselMaddRule": {2, 3, 4, 5},
    "MottaselMaddRule": {4, 5, 6},
    "MottaselMaddPauseRule": {4, 5, 6},
}

# Letters non-Arab learners (and the model) most often swap. In lenient mode a swap of
# one of these is shown as a pronunciation tip rather than marked as a wrong word.
_CLOSE = {frozenset(p) for p in [
    "ثس", "ثت", "ذز", "ذد", "ظز", "ظذ", "ضد", "ضظ", "صس", "طت", "حه", "عء", "عا", "قك", "غخ", "قغ", "زج",
]}


def _rule(r) -> dict:
    name = getattr(r, "name", None)
    return {
        "kind": type(r).__name__,
        "tag": getattr(r, "tag", None),
        "ar": getattr(name, "ar", "") or "",
        "en": getattr(name, "en", "") or "",
        "golden_len": getattr(r, "golden_len", None),
    }


def _length_ok(rules: list[dict], expected: int | None, heard: int, strict: bool) -> bool:
    allowed = set()
    for r in rules:
        allowed |= _ALLOWED_KIND.get(r["kind"], set())
    if heard in allowed:
        return True
    if strict or expected is None:
        return heard == expected
    # Lenient: a count either way is fine; Madd Lazim needs at least 4.
    if any(r["kind"] == "LazemMaddRule" for r in rules):
        return heard >= 4
    if expected <= 2:
        return 1 <= heard <= 3
    return expected - 2 <= heard <= expected + 1


def _severity(e, rules: list[dict], strict: bool, seg_conf: float, word_phonemes: int) -> str | None:
    """'mistake' (shown and counted), 'tip' (shown softly, not counted) or None (dropped)."""
    unsure_audio = seg_conf < 0.8
    if e.error_type == "normal":
        exp, got = e.expected_ph, e.preditected_ph
        if e.speech_error_type == "delete":
            if len(exp) >= 3 or len(exp) >= 0.6 * word_phonemes:
                return "mistake"  # a word or most of it left out
            return "mistake" if strict else "tip"
        if e.speech_error_type == "insert":
            if len(got) >= 6:
                return "mistake"
            return ("mistake" if strict else "tip") if len(got) >= 3 else None
        # replace
        if len(exp) == 1 and len(got) == 1 and frozenset(exp + got) in _CLOSE:
            return "mistake" if strict else "tip"
        if max(len(exp), len(got)) <= 2:
            return "mistake" if strict else "tip"
        return "mistake"
    if unsure_audio:
        return "tip" if strict else None
    if e.error_type == "tashkeel":
        return "mistake" if strict else "tip"
    # tajweed
    if e.predicted_len is not None and e.expected_len is not None:
        return None if _length_ok(rules, e.expected_len, e.predicted_len, strict) else "mistake"
    return "mistake" if strict else "tip"


def _best(seg: str, ref: Reference, cand: list[int], pointer: int | None, min_e: int = 0):
    lens = [ref.span[i + 1] - ref.span[i] for i in range(ref.n)]
    L, best = len(seg), None
    for s0 in cand:
        acc = 0
        for e in range(s0, ref.n):
            acc += max(1, lens[e])
            if e < min_e or acc < 0.5 * L:
                continue
            if acc > 1.7 * L + 4:
                break
            r = ref.slice(s0, e)
            d = lv.distance(seg, r) / max(len(seg), len(r), 1)
            if pointer is not None and s0 > pointer:
                d += 0.01 * (s0 - pointer)
            if best is None or d < best[0] - 1e-9 or (abs(d - best[0]) < 1e-9 and e > best[2]):
                best = (d, s0, e)
    return best


def _align(segs: list[str], ref: Reference, debug: list | None = None) -> list[tuple[str, int, int, float]]:
    """Finds the words each breath covers. Returns (phonemes, first word, last word,
    distance). A short piece that only makes sense together with the breath before it
    (the voice detector sometimes splits a long Madd) is joined to it. Breaths that match
    nothing (someone else talking, background sounds) are left out."""
    n, out, pointer = ref.n, [], None
    for k, seg in enumerate(segs):
        if not seg:
            continue
        if pointer is None:
            cand = sorted(set(ref.first_starts))
        else:
            window = set(range(max(0, pointer - 3), min(n, pointer + 12)))
            # repeating a recent Ayah from its start
            window |= {s for s in ref.ayah_start.values() if pointer - 80 <= s <= pointer + 12}
            cand = sorted(window)
        best = _best(seg, ref, cand, pointer)
        if out and (best is None or best[0] > 0.3 or len(seg) < 10):
            # Try it as the end of the previous breath.
            pseg, ps0, pe, pd = out[-1]
            joined = pseg + seg
            jb = _best(joined, ref, [ps0], None, min_e=pe)
            if jb is not None and jb[0] <= max(pd + 0.05, 0.25) and (best is None or jb[0] <= best[0]):
                out[-1] = (joined, ps0, jb[2], jb[0])
                pointer = jb[2] + 1
                if debug is not None:
                    debug.append({"breath": k, "heard": seg, "joined_to_previous": [round(jb[0], 3), ps0, jb[2]]})
                continue
        if debug is not None:
            debug.append({"breath": k, "heard": seg, "best": best and [round(best[0], 3), best[1], best[2]],
                          "ref": best and ref.slice(best[1], best[2]), "pointer": pointer})
        if best is None or best[0] > 0.55:
            continue  # not part of these Ayahs
        d, s0, e = best
        out.append((seg, s0, e, d))
        pointer = e + 1
    return out


def analyse(segs: list[tuple[str, float]], ref: Reference, strict: bool) -> dict:
    phon = [p for p, _ in segs]
    confs = [c for _, c in segs]
    debug: list = []
    spans = _align(phon, ref, debug)
    by_word: dict[int, list[dict]] = {}
    covered: set[int] = set()
    seg_conf = float(np.mean(confs)) if confs else 0.0
    for heard, s0, e, _ in spans:
        alone = ref.alone(s0, e)
        text = ref.text(s0, e)
        errs = explain_error(uthmani_text=text, ref_ph_text=alone.phonemes, predicted_ph_text=heard, mappings=alone.mappings)
        found = []
        for er in errs:
            a, b = er.uthmani_pos
            w0 = s0 + text[:a].count(" ")
            w1 = s0 + text[:max(a, b - 1)].count(" ")
            rules = [_rule(r) for r in (er.ref_tajweed_rules or [])]
            wl = max(1, ref.span[w0 + 1] - ref.span[w0]) if w0 < ref.n else 1
            sev = _severity(er, rules, strict, seg_conf, wl)
            if sev is None:
                continue
            found.append({
                "w0": w0, "w1": w1,
                "type": {"normal": "word", "tashkeel": "harakah"}.get(er.error_type, "tajweed"),
                "severity": sev,
                "speech": er.speech_error_type,
                "expected": er.expected_ph,
                "heard": er.preditected_ph,
                "expected_len": er.expected_len,
                "heard_len": er.predicted_len,
                "rules": rules,
                "missing_rules": [_rule(r) for r in (er.missing_tajweed_rules or [])],
                "extra_rules": [_rule(r) for r in (er.inserted_tajweed_rules or [])],
            })
        span_words = set(range(s0, e + 1))
        for i in span_words:  # a word recited again later is judged by its last recitation
            by_word[i] = [f for f in found if f["w0"] <= i <= f["w1"]]
        covered |= span_words

    ayahs = []
    for a in range(ref.aya_from, ref.aya_to + 1):
        s = ref.ayah_start[a]
        e = ref.ayah_start.get(a + 1, ref.n) - 1
        idx = list(range(s, e + 1))
        got = [i for i in idx if i in covered]
        recited = len(got) >= max(1, 0.4 * len(idx))
        errors, seen = [], set()
        if recited:
            for i in idx:
                if i not in covered:
                    errors.append({"w0": i, "w1": i, "type": "word", "severity": "mistake", "speech": "delete",
                                   "expected": ref.slice(i, i), "heard": "", "expected_len": None, "heard_len": None,
                                   "rules": [], "missing_rules": [], "extra_rules": []})
                for f in by_word.get(i, []):
                    key = (f["w0"], f["w1"], f["type"], f["expected"], f["heard"])
                    if key not in seen:
                        seen.add(key)
                        errors.append(f)
        out_errors = []
        for f in errors:
            f = dict(f)
            f["word_start"] = max(0, f.pop("w0") - s)
            f["word_end"] = min(len(idx) - 1, f.pop("w1") - s)
            out_errors.append(f)
        ayahs.append({
            "aya": a,
            "words": ref.words[s:e + 1],
            "status": "recited" if recited else "not_recited",
            "errors": out_errors,
        })

    weights = [max(1, len(p)) for p in phon]
    confidence = float(np.average(confs, weights=weights)) if phon else 0.0
    if not phon:
        status = "silent"
    elif not spans:
        status = "different_ayah" if confidence > 0.8 and sum(len(p) for p in phon) > 15 else "too_little"
    elif not any(x["status"] == "recited" for x in ayahs):
        status = "too_little"
    elif confidence < 0.55:
        status = "unclear"
    else:
        status = "ok"
    return {
        "status": status,
        "ayahs": ayahs,
        "confidence": round(confidence, 3),
        "breaths": len(phon),
        "breaths_used": len(spans),
        "debug": debug if os.environ.get("HIFZ_DEBUG") == "1" else None,
    }
