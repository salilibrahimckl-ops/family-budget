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
                self.char_to_id = {str(v): int(k) for k, v in self.vocab.items() if int(k) != 0 and len(str(v)) == 1}
                self.ready = True
            except Exception as e:  # reported by /health
                self.error = f"{type(e).__name__}: {e}"

    def phonemes(self, wave: np.ndarray) -> tuple[str, float, np.ndarray]:
        """Phonetic script of one breath, the model's mean confidence (0-1), and its
        per-frame log-probabilities (kept to double-check findings later)."""
        feats = self.processor(wave, sampling_rate=SR, return_tensors="pt")
        with torch.inference_mode():
            out = self.model(feats["input_features"], feats.get("attention_mask"), return_dict=False)[0]
        logp = torch.log_softmax(out["phonemes"][0].float(), dim=-1)
        probs = logp.exp()
        top_p, top_id = probs.max(dim=-1)
        text, confs, prev = [], [], 0
        for p, i in zip(top_p.tolist(), top_id.tolist()):
            if i != 0 and i != prev:
                text.append(self.vocab[int(i)])
                confs.append(p)
            prev = i
        return "".join(text), (float(np.mean(confs)) if confs else 0.0), logp.numpy().astype(np.float32)


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

    def finish(self) -> list[tuple[str, float, np.ndarray, int, int]]:
        with self.lock:
            if self.cur is not None:
                self._close(self.cur, len(self.buf))
                self.cur = None
            breaths = list(self.breaths)
        return [(*b.future.result(), b.start, b.end) for b in breaths]


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


# ------------------------------------------------------------- double-check --
def ctc_support(logp: np.ndarray, ids: list[int], blank: int = 0) -> np.ndarray | None:
    """How well the audio supports each expected sound. Finds the best way to line the
    expected sounds up with the audio (CTC forced alignment) and returns, for each
    expected sound, the model's highest probability for it in the frames it was given.
    A sound the model *also* found plausible (even if its first guess was different) is
    likely right; one with no support was really missed or said differently."""
    T, L = logp.shape[0], len(ids)
    if L == 0:
        return np.zeros(0, dtype=np.float32)
    ext = [blank]
    for i in ids:
        ext += [i, blank]
    S = len(ext)
    if T < L:
        return None
    ext = np.array(ext)
    skip = np.zeros(S, dtype=bool)
    for s_ in range(2, S):
        skip[s_] = ext[s_] != blank and ext[s_] != ext[s_ - 2]
    NEG = -1e30
    emit = logp[:, ext]  # T x S
    dp = np.full(S, NEG)
    dp[0], dp[1] = emit[0, 0], emit[0, 1]
    back = np.zeros((T, S), dtype=np.int8)
    for t in range(1, T):
        b = np.concatenate(([NEG], dp[:-1]))
        c = np.where(skip, np.concatenate(([NEG, NEG], dp[:-2])), NEG)
        stack = np.stack([dp, b, c])
        arg = stack.argmax(axis=0)
        dp = stack[arg, np.arange(S)] + emit[t]
        back[t] = arg
    end = S - 1 if dp[S - 1] >= dp[S - 2] else S - 2
    if dp[end] <= NEG / 2:
        return None
    sup = np.zeros(L, dtype=np.float32)
    s_ = end
    for t in range(T - 1, -1, -1):
        if s_ % 2 == 1:
            j = (s_ - 1) // 2
            sup[j] = max(sup[j], float(np.exp(emit[t, s_])))
        s_ -= int(back[t, s_])
        if s_ < 0:
            break
    return sup


def ctc_score(logp: np.ndarray, ids: list[int], blank: int = 0) -> float:
    """Log-likelihood of the best way the audio could have said exactly these sounds."""
    T = logp.shape[0]
    ext = [blank]
    for i in ids:
        ext += [i, blank]
    S = len(ext)
    ext = np.array(ext)
    skip = np.zeros(S, dtype=bool)
    for s_ in range(2, S):
        skip[s_] = ext[s_] != blank and ext[s_] != ext[s_ - 2]
    NEG = -1e30
    emit = logp[:, ext]
    dp = np.full(S, NEG)
    dp[0] = emit[0, 0]
    if S > 1:
        dp[1] = emit[0, 1]
    for t in range(1, T):
        b = np.concatenate(([NEG], dp[:-1]))
        c = np.where(skip, np.concatenate(([NEG, NEG], dp[:-2])), NEG)
        dp = np.maximum(np.maximum(dp, b), c) + emit[t]
    best = max(dp[-1], dp[-2] if S > 1 else NEG)
    return float(best) if best > NEG / 2 else float("-inf")


def ctc_frames(logp: np.ndarray, ids: list[int], blank: int = 0) -> list[tuple[int, int]] | None:
    """For each expected sound, the first and last audio frame the best alignment gives it."""
    T, L = logp.shape[0], len(ids)
    if L == 0 or T < L:
        return None
    ext = [blank]
    for i in ids:
        ext += [i, blank]
    S = len(ext)
    ext = np.array(ext)
    skip = np.zeros(S, dtype=bool)
    for s_ in range(2, S):
        skip[s_] = ext[s_] != blank and ext[s_] != ext[s_ - 2]
    NEG = -1e30
    emit = logp[:, ext]
    dp = np.full(S, NEG)
    dp[0], dp[1] = emit[0, 0], emit[0, 1]
    back = np.zeros((T, S), dtype=np.int8)
    for t in range(1, T):
        b = np.concatenate(([NEG], dp[:-1]))
        c = np.where(skip, np.concatenate(([NEG, NEG], dp[:-2])), NEG)
        stack = np.stack([dp, b, c])
        arg = stack.argmax(axis=0)
        dp = stack[arg, np.arange(S)] + emit[t]
        back[t] = arg
    s_ = S - 1 if dp[S - 1] >= dp[S - 2] else S - 2
    if dp[s_] <= NEG / 2:
        return None
    first = [T] * L
    last = [-1] * L
    for t in range(T - 1, -1, -1):
        if s_ % 2 == 1:
            j = (s_ - 1) // 2
            first[j] = min(first[j], t)
            last[j] = max(last[j], t)
        s_ -= int(back[t, s_])
        if s_ < 0:
            break
    # A sound squeezed out of the path borrows its neighbours' place.
    for j in range(L):
        if last[j] < 0:
            first[j] = last[j] = last[j - 1] if j > 0 and last[j - 1] >= 0 else 0
    return list(zip(first, last))


def _ids(text: str) -> list[int]:
    return [M.char_to_id[ch] for ch in text if ch in M.char_to_id]


def model_prefers_reference(logp: np.ndarray, ref_ph: str, a: int, b: int, heard: str, ref_score: float,
                            margin: float = 2.0) -> bool:
    """Goodness-of-pronunciation check for one finding. Compares how well the audio fits
    the correct sounds against how well it fits what the model first wrote down, with
    everything else the same. If the correct version fits (nearly) as well, the model was
    only unsure and the finding is dropped; a real mistake fits clearly worse."""
    alt = ref_ph[:a] + heard + ref_ph[b:]
    alt_score = ctc_score(logp, _ids(alt))
    if ref_score == float("-inf"):
        return False
    return ref_score >= alt_score - margin


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


# Lenient mode follows the lengths taught in general Tajweed classes, with a little room
# for how a learner (and the model) counts.
_LENIENT_RANGE = {
    "NormalMaddRule": (2, 4),  # Madd Tabee'i: 2 counts (up to 4 accepted)
    "MonfaselMaddRule": (2, 6),  # Munfasil: 2, 4 or 5 in Hafs
    "MottaselMaddRule": (4, 6),  # Muttasil: 4-5 (6 when stopping)
    "MottaselMaddPauseRule": (4, 6),
    "LazemMaddRule": (5, 7),  # Lazim: 6
    "AaredMaddRule": (2, 6),  # 'Aarid lis-sukun: 2, 4 or 6
    "LeenMaddRule": (1, 6),  # Leen when stopping: 2, 4 or 6
    "Ghonnah": (2, 3),  # Ghunnah: 2 counts
    "MoshaddadOrModghamNoonRule": (2, 3),
}


def _length_ok(rules: list[dict], expected: int | None, heard: int, strict: bool) -> bool:
    allowed = set()
    for r in rules:
        allowed |= _ALLOWED_KIND.get(r["kind"], set())
    if heard in allowed:
        return True
    if strict or expected is None:
        return heard == expected
    for r in rules:
        rng = _LENIENT_RANGE.get(r["kind"])
        if rng:
            return rng[0] <= heard <= rng[1]
    return abs(heard - expected) <= 1


def _near_range(rules: list[dict], heard: int) -> bool:
    for r in rules:
        rng = _LENIENT_RANGE.get(r["kind"])
        if rng:
            return rng[0] - 1 <= heard <= rng[1] + 1
    return False


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
        if _length_ok(rules, e.expected_len, e.predicted_len, strict):
            return None
        if not strict and _near_range(rules, e.predicted_len):
            return "tip"  # one count out: worth a gentle note, not a mistake
        return "mistake"
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
            if acc > 1.7 * L + 4 and e > s0:  # always try at least one word (الٓمٓ is long)
                break
            r = ref.slice(s0, e)
            d = lv.distance(seg, r) / max(len(seg), len(r), 1)
            if pointer is not None and s0 > pointer:
                d += 0.01 * (s0 - pointer)
            if best is None or d < best[0] - 1e-9 or (abs(d - best[0]) < 1e-9 and e > best[2]):
                best = (d, s0, e)
    return best


def _align(segs: list[str], ref: Reference, debug: list | None = None) -> list[tuple[str, int, int, float, list[int]]]:
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
            if k > 0 or len(seg) < 12:
                # The first breath didn't fit (a cough, a word before starting, a poor
                # first second of audio): look anywhere in the first Ayahs and at any
                # Ayah start, so one bad breath can't lose the whole recitation.
                first_words = range(ref.ayah_start[ref.aya_from], ref.ayah_start.get(ref.aya_from + 3, n))
                cand = sorted(set(cand) | set(first_words) | set(ref.ayah_start.values()))
        else:
            window = set(range(max(0, pointer - 3), min(n, pointer + 12)))
            # repeating a recent Ayah from its start
            window |= {s for s in ref.ayah_start.values() if pointer - 80 <= s <= pointer + 12}
            cand = sorted(window)
        best = _best(seg, ref, cand, pointer)
        if pointer is None and best is not None and best[1] not in ref.first_starts and best[0] > 0.45:
            best = None
        if out and (best is None or best[0] > 0.3 or len(seg) < 10):
            # Try it as the end of the previous breath.
            pseg, ps0, pe, pd, pks = out[-1]
            joined = pseg + seg
            jb = _best(joined, ref, [ps0], None, min_e=pe)
            if jb is not None and jb[0] <= max(pd + 0.05, 0.25) and (best is None or jb[0] <= best[0]):
                out[-1] = (joined, ps0, jb[2], jb[0], pks + [k])
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
        out.append((seg, s0, e, d, [k]))
        pointer = e + 1
    return out


def _fill_gaps(spans: list, ref: Reference, debug: list | None = None) -> list:
    """Words between two breaths that no breath was matched to are usually not missing:
    the word was split by a pause, said at the very end of a breath and partly lost, or
    misheard. Give such a word to the breath before (or after) it when that breath's sounds
    account for most of it; only a word with nothing of it in the audio stays "left out"."""
    spans = list(spans)
    for _ in range(2):
        covered = set()
        for sp in spans:
            covered |= set(range(sp[1], sp[2] + 1))
        changed = False
        for idx, (heard, s0, e, d, ks) in enumerate(spans):
            # forward: words right after this span that nothing covers
            k = e + 1
            while k < ref.n and k not in covered:
                old = lv.distance(heard, ref.alone(s0, k - 1).phonemes)
                new = lv.distance(heard, ref.alone(s0, k).phonemes)
                wl = max(1, ref.span[k + 1] - ref.span[k])
                if new - old > 0.6 * wl:
                    break
                covered.add(k)
                e = k
                k += 1
                changed = True
            # backward: words right before this span
            k = s0 - 1
            while k >= 0 and k not in covered:
                old = lv.distance(heard, ref.alone(k + 1, e).phonemes)
                new = lv.distance(heard, ref.alone(k, e).phonemes)
                wl = max(1, ref.span[k + 1] - ref.span[k])
                if new - old > 0.6 * wl:
                    break
                covered.add(k)
                s0 = k
                k -= 1
                changed = True
            if (s0, e) != (spans[idx][1], spans[idx][2]):
                if debug is not None:
                    debug.append({"filled": [spans[idx][1], spans[idx][2]], "to": [s0, e]})
                spans[idx] = (heard, s0, e, d, ks)
        if not changed:
            break
    return spans


# Sounds that differ between stopping on a word and joining it to the next: the last
# vowel, tanween/noon (with its ghunnah) and a short Madd. Stopping is always allowed.
_WAQF_TAIL = set("ںنَُِاۦۥم")


def analyse(segs: list[tuple], ref: Reference, strict: bool) -> dict:
    phon = [x[0] for x in segs]
    confs = [x[1] for x in segs]
    logps = [x[2] if len(x) > 2 else None for x in segs]
    bounds = [(x[3] / SR, x[4] / SR) if len(x) > 4 else None for x in segs]
    debug: list = []
    spans = _fill_gaps(_align(phon, ref, debug), ref, debug)
    # Breath edges that run straight on into another breath (a pause mid-phrase).
    edge_start = {sp[1] for sp in spans}
    edge_end = {sp[2] for sp in spans}
    by_word: dict[int, list[dict]] = {}
    covered: set[int] = set()
    span_time: list[tuple[int, int, float, float]] = []  # (first word, last word, start s, end s)
    seg_conf = float(np.mean(confs)) if confs else 0.0
    dropped = 0
    clip_stats = [0]
    for heard, s0, e, _, ks in spans:
        alone = ref.alone(s0, e)
        text = ref.text(s0, e)
        errs = explain_error(uthmani_text=text, ref_ph_text=alone.phonemes, predicted_ph_text=heard, mappings=alone.mappings)
        lp = [logps[k] for k in ks]
        have_lp = all(x is not None for x in lp) and M.ready
        joined_lp = np.concatenate(lp) if have_lp else None
        # Where in the recording each audio frame of this span lies (seconds).
        frame_t = None
        if have_lp and all(bounds[k] for k in ks):
            frame_t = np.concatenate([
                bounds[k][0] + (np.arange(logps[k].shape[0]) + 0.5) * (bounds[k][1] - bounds[k][0]) / max(1, logps[k].shape[0])
                for k in ks])
            span_time.append((s0, e, bounds[ks[0]][0], bounds[ks[-1]][1]))
        ref_score = ctc_score(joined_lp, _ids(alone.phonemes)) if (joined_lp is not None and errs) else None
        tok_frames, char_tok = None, []
        if errs and joined_lp is not None and frame_t is not None:
            n = 0
            for ch in alone.phonemes:
                char_tok.append(n)
                if ch in M.char_to_id:
                    n += 1
            try:
                tok_frames = ctc_frames(joined_lp, _ids(alone.phonemes))
            except Exception:
                tok_frames = None

        # Where each word of this span lies in the phonetic script.
        word_ph: list[tuple[int, int]] = []
        if True:
            wi, cur = 0, [10 ** 9, -1]
            for ci, ch in enumerate(text):
                if ch == " ":
                    word_ph.append((cur[0], cur[1])); wi += 1; cur = [10 ** 9, -1]
                    continue
                mp = alone.mappings[ci] if ci < len(alone.mappings) else None
                if mp is not None and mp.pos[1] > mp.pos[0]:
                    cur[0] = min(cur[0], mp.pos[0]); cur[1] = max(cur[1], mp.pos[1])
            word_ph.append((cur[0], cur[1]))
        span_t0, span_t1 = (bounds[ks[0]][0], bounds[ks[-1]][1]) if frame_t is not None else (0.0, 0.0)

        # What the model actually wrote down, and the audio frame of each sound. Clips are
        # cut from this, so "You" plays exactly the stretch the teacher compared.
        emit_t: list[float] = []
        if frame_t is not None:
            chars, off = [], 0
            for k in ks:
                ids = logps[k].argmax(axis=1)
                prev = 0
                for t, i in enumerate(ids.tolist()):
                    if i != 0 and i != prev:
                        chars.append(M.vocab[int(i)])
                        emit_t.append(float(frame_t[off + t]))
                    prev = i
                off += logps[k].shape[0]
            if "".join(chars) != heard:
                emit_t = []
        ref2h: list[int] = []
        missing: set[int] = set()
        if emit_t:
            ref2h = [0] * (len(alone.phonemes) + 1)
            for tag, i1, i2, j1, j2 in lv.opcodes(alone.phonemes, heard):
                for i in range(i1, i2):
                    if tag == "delete":
                        ref2h[i] = j1
                        missing.add(i)
                    else:
                        ref2h[i] = j1 + min(i - i1, max(0, j2 - j1 - 1))
            ref2h[-1] = len(heard)

        def heard_at(w0: int, w1: int):
            lw0, lw1 = w0 - s0, w1 - s0
            if not emit_t or not (0 <= lw0 <= lw1 < len(word_ph)):
                return None
            a0 = word_ph[lw0][0]
            b0 = max(word_ph[k][1] for k in range(lw0, lw1 + 1))
            if b0 < 0 or a0 >= 10 ** 9:
                return None
            hs = [ref2h[i] for i in range(a0, b0) if i not in missing]
            nh = len(emit_t)
            sp = lambda j: span_t0 if j < 0 else (span_t1 if j >= nh else emit_t[j])
            if hs:
                ha, hb = min(hs), max(hs) + 1
                t0 = (sp(ha - 1) + sp(ha)) / 2 if ha > 0 else span_t0
                t1 = sp(hb) if hb < nh else span_t1
            else:  # nothing of it was heard: the moment where it should have been
                ha = ref2h[a0]
                t0, t1 = sp(ha - 1) - 0.3, sp(ha) + 0.3
            t0, t1 = max(0.0, t0 - 0.12), t1 + 0.12
            if t1 - t0 < 0.6:
                t0 = max(0.0, (t0 + t1) / 2 - 0.3)
                t1 = t0 + 0.6
            return [round(t0, 2), round(t1, 2)]

        def at(w0: int, w1: int):
            got = heard_at(w0, w1)
            if got is not None:
                clip_stats[0] += 1
                return got
            return ctc_at(w0, w1)

        def ctc_at(w0: int, w1: int):
            """The stretch of the recording holding words w0..w1: from the end of the word
            before to the start of the word after, so nothing of the words is cut off."""
            if not tok_frames or not word_ph:
                return None
            lw0, lw1 = w0 - s0, w1 - s0
            if not (0 <= lw0 <= lw1 < len(word_ph)):
                return None
            a0 = word_ph[lw0][0]
            b0 = max(word_ph[k][1] for k in range(lw0, lw1 + 1))
            if b0 < 0 or a0 >= 10 ** 9:
                return None
            n = len(tok_frames)
            total = char_tok[-1] + (1 if alone.phonemes[-1] in M.char_to_id else 0)
            j0 = char_tok[a0] if a0 < len(char_tok) else total
            j1 = (char_tok[b0] if b0 < len(char_tok) else total) - 1
            t0 = float(frame_t[tok_frames[j0 - 1][1]]) + 0.02 if 0 < j0 <= n else span_t0
            t1 = float(frame_t[tok_frames[j1 + 1][0]]) if 0 <= j1 + 1 < n else span_t1
            t0, t1 = max(0.0, t0 - 0.15), t1 + 0.15
            if t1 - t0 < 0.6:
                t0 = max(0.0, (t0 + t1) / 2 - 0.3)
                t1 = t0 + 0.6
            return [round(t0, 2), round(t1, 2)]

        found = []
        for er in errs:
            sup = None
            # Lenient: double-check word and harakah findings against the audio itself.
            if (not strict and joined_lp is not None and er.error_type in ("normal", "tashkeel")
                    and er.speech_error_type != "insert"):
                a0, b0 = er.ph_pos
                try:
                    if model_prefers_reference(joined_lp, alone.phonemes, a0, b0, er.preditected_ph or "", ref_score):
                        dropped += 1
                        continue
                except Exception:
                    pass
            a, b = er.uthmani_pos
            w0 = s0 + text[:a].count(" ")
            w1 = s0 + text[:max(a, b - 1)].count(" ")
            rules = [_rule(r) for r in (er.ref_tajweed_rules or [])]
            wl = max(1, ref.span[w0 + 1] - ref.span[w0]) if w0 < ref.n else 1
            sev = _severity(er, rules, strict, seg_conf, wl)
            if sev is not None and not strict and er.error_type in ("normal", "tashkeel"):
                exp_, got_ = er.expected_ph or "", er.preditected_ph or ""
                lw = w1 - s0
                at_word_end = 0 <= lw < len(word_ph) and er.ph_pos[1] >= word_ph[lw][1]
                if at_word_end and len(exp_) <= 3 and set(exp_) <= _WAQF_TAIL and len(got_) <= len(exp_):
                    continue  # stopped on the word (waqf) instead of joining it: allowed
                # Only where this breath runs straight on from / into another breath, and
                # only for the very first or last sounds of the breath.
                at_edge = ((w0 == s0 and (s0 - 1) in edge_end and er.ph_pos[0] <= 3)
                           or (w1 == e and (e + 1) in edge_start and er.ph_pos[1] >= len(alone.phonemes) - 3))
                if at_edge and max(len(exp_), len(got_)) <= 4:
                    sev = "tip"  # right at a pause: the audio there is unreliable
            if sev is None:
                continue
            try:
                where = at(w0, w1)
            except Exception:
                where = None
            whole = False
            if er.speech_error_type == "delete" and er.error_type == "normal":
                lws = [k for k in range(w0 - s0, w1 - s0 + 1) if 0 <= k < len(word_ph)]
                whole = bool(lws) and er.ph_pos[0] <= word_ph[lws[0]][0] and er.ph_pos[1] >= word_ph[lws[-1]][1]
            found.append({
                "w0": w0, "w1": w1, "at": where, "whole": whole,
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
                    before = [t1 for (a_, b_, t0, t1) in span_time if b_ < i]
                    after = [t0 for (a_, b_, t0, t1) in span_time if a_ > i]
                    where = None
                    if before or after:
                        t0 = (max(before) if before else min(after) - 3.0) - 0.3
                        t1 = (min(after) if after else max(before) + 3.0) + 0.3
                        t0 = max(0.0, max(t0, t1 - 8.0))
                        where = [round(t0, 2), round(t1, 2)]
                    errors.append({"w0": i, "w1": i, "at": where, "whole": True, "origin": "uncovered", "type": "word", "severity": "mistake", "speech": "delete",
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
        "double_checked_away": dropped,
        "clips_from_heard": clip_stats[0],
        "debug": debug if os.environ.get("HIFZ_DEBUG") == "1" else None,
    }
