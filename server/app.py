"""Hifz Academy recitation teacher (web API).

Listens to a recitation of one Ayah or a whole section of Ayahs and reports, word by
word: missed, extra or wrong words; wrong letters and harakat; and Tajweed (every Madd
with the counts held, Ghunnah, Qalqalah, Idgham). Differences are sorted into real
mistakes and gentle tips; lenient mode (the default) allows for non-Arab accents.

Built on the open-source Quran Muaalem model (obadx/muaalem-model-v3_2, Quran Muaalem
License). The Quran text comes from the verified source (Tanzil Uthmani 1.1 via
quran-transcript); every finding is a comparison against it. Nothing is generated.

AI advisory notice (required by the Quran Muaalem License, section 2.1):
  This Quranic Teacher is an artificial-intelligence model that may make mistakes. It is
  intended for assistance only and must not be relied upon. It is not a replacement for
  a proficient, authorized teacher, because the Quran is only received through oral
  transmission (mushafahah).

Two ways to send audio:
  - Streaming (fast): POST /session, then POST /session/{id}/audio with raw 16 kHz
    16-bit mono PCM every few seconds while reciting, then POST /session/{id}/finish.
    Breaths are analysed while the learner is still reciting.
  - One file: POST /check.
One session or one check counts as one use, however many Ayahs it covers.
Audio is processed in memory and discarded; nothing is stored.
"""
from __future__ import annotations

import asyncio
import os
import subprocess
import tempfile
import threading
import time
import uuid

import librosa
import numpy as np
import torch
from fastapi import FastAPI, File, Form, Header, HTTPException, Query, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from quran_transcript import Aya, MoshafAttributes

import engine
from engine import SR, M, Recording, analyse, build_reference
from fairuse import admit, is_family

NOTICE = {
    "en": "This Quranic Teacher is an artificial-intelligence model that may make mistakes. "
    "It is intended for assistance only and must not be relied upon. It is not a replacement "
    "for a proficient, authorized teacher, because the Quran is only received through oral "
    "transmission (mushafahah).",
    "ar": "هذا المعلّم القرآني نموذج ذكاء اصطناعي قد يخطئ؛ فهو للإعانة فقط ولا يُعتمد عليه، "
    "وليس بديلاً عن معلّمٍ مُتقِنٍ مُجاز؛ لأنّ القرآن لا يُؤخذ إلا بالمشافهة.",
}
MAX_AYAHS = 286  # per session: up to a whole Surah (Al-Baqarah has 286)

torch.set_num_threads(max(1, os.cpu_count() or 1))

app = FastAPI(title="Hifz Academy recitation teacher")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


@app.on_event("startup")
def _startup():
    if not M.ready:  # on Modal the model is already loaded (memory snapshot)
        threading.Thread(target=M.load, daemon=True).start()


async def _wait_ready():
    for _ in range(180):
        if M.ready or M.error:
            break
        await asyncio.sleep(0.5)
    if not M.ready:
        raise HTTPException(503, M.error or "The teacher is waking up. Try again in a minute.")


def _moshaf(monfasel: int, mottasel: int, aared: int) -> MoshafAttributes:
    return MoshafAttributes(
        rewaya="hafs",
        madd_monfasel_len=monfasel,
        madd_mottasel_len=mottasel,
        madd_mottasel_waqf=mottasel,
        madd_aared_len=aared,
    )


def _range(sura: int, aya_from: int, aya_to: int | None) -> tuple[int, int]:
    aya_to = aya_to or aya_from
    if aya_to < aya_from or aya_to - aya_from + 1 > MAX_AYAHS:
        raise HTTPException(400, "Choose up to one whole Surah at a time.")
    try:
        Aya(sura, aya_from).get()
        Aya(sura, aya_to).get()
    except Exception:
        raise HTTPException(400, "Unknown Surah or Ayah.")
    return aya_from, aya_to


def _result(rec: Recording, sura: int, aya_from: int, aya_to: int, strict: bool, moshaf, usage: dict, t0: float) -> dict:
    segs = rec.finish()
    t1 = time.time()
    ref = build_reference(sura, aya_from, aya_to, moshaf)
    out = analyse(segs, ref, strict)
    out.update({
        "sura": sura, "aya_from": aya_from, "aya_to": aya_to, "strict": strict,
        "notice": NOTICE, "model": engine.MODEL, "usage": usage,
        "seconds_audio": round(rec.seconds, 1),
        "seconds": round(time.time() - t0, 2),
        "seconds_compare": round(time.time() - t1, 2),
    })
    # Fields the 0.8/0.9 apps (one Ayah at a time) read.
    first = out["ayahs"][0]
    out["words"] = first["words"]
    out["errors"] = [dict(e, type={"word": "normal", "harakah": "tashkeel"}.get(e["type"], e["type"]))
                     for e in first["errors"] if e["severity"] == "mistake"]
    return out


# ------------------------------------------------------------------- routes --
@app.get("/")
def root():
    return {"service": "Hifz Academy recitation teacher", "model": engine.MODEL, "notice": NOTICE}


@app.get("/health")
def health():
    return {"ready": M.ready, "error": M.error, "model": engine.MODEL}


@app.get("/family")
def family(x_hifz_family: str | None = Header(None)):
    """Lets the app confirm a family code without using a check."""
    return {"family": is_family(x_hifz_family)}


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


@app.post("/check")
async def check(
    file: UploadFile = File(...),
    sura: int = Form(...),
    aya: int | None = Form(None),
    aya_from: int | None = Form(None),
    aya_to: int | None = Form(None),
    strict: bool = Form(False),
    madd_monfasel_len: int = Form(4),
    madd_mottasel_len: int = Form(4),
    madd_aared_len: int = Form(4),
    x_hifz_app: str | None = Header(None),
    x_hifz_device: str | None = Header(None),
    x_hifz_family: str | None = Header(None),
):
    """The whole recording in one file (also used when streaming isn't possible)."""
    usage = await admit(x_hifz_app, x_hifz_device, x_hifz_family)
    t0 = time.time()
    a0, a1 = _range(sura, aya_from or aya or 0, aya_to)
    await _wait_ready()
    wave = _decode(await file.read(), file.filename or "audio.webm")
    if len(wave) > engine.MAX_SECONDS * SR:
        raise HTTPException(413, "Recording is too long (one hour at most).")
    rec = Recording()
    await asyncio.to_thread(rec.feed, wave)
    moshaf = _moshaf(madd_monfasel_len, madd_mottasel_len, madd_aared_len)
    return await asyncio.to_thread(_result, rec, sura, a0, a1, strict, moshaf, usage, t0)


# Streaming sessions live in this container's memory (the app runs on a single
# container, so every piece of a session reaches the same one).
class _Session:
    def __init__(self, sura, a0, a1, strict, moshaf, usage):
        self.sura, self.a0, self.a1, self.strict, self.moshaf, self.usage = sura, a0, a1, strict, moshaf, usage
        self.rec = Recording()
        self.next_seq = 0
        self.pending: dict[int, bytes] = {}
        self.created = time.time()
        self.lock = asyncio.Lock()
        self.result: dict | None = None


_sessions: dict[str, _Session] = {}


def _sweep():
    now = time.time()
    for k in [k for k, s in _sessions.items() if now - s.created > 1800]:
        _sessions.pop(k, None)


@app.post("/session")
async def session_start(
    sura: int = Form(...),
    aya_from: int = Form(...),
    aya_to: int | None = Form(None),
    strict: bool = Form(False),
    madd_monfasel_len: int = Form(4),
    madd_mottasel_len: int = Form(4),
    madd_aared_len: int = Form(4),
    x_hifz_app: str | None = Header(None),
    x_hifz_device: str | None = Header(None),
    x_hifz_family: str | None = Header(None),
):
    usage = await admit(x_hifz_app, x_hifz_device, x_hifz_family)
    a0, a1 = _range(sura, aya_from, aya_to)
    _sweep()
    sid = uuid.uuid4().hex
    _sessions[sid] = _Session(sura, a0, a1, strict, _moshaf(madd_monfasel_len, madd_mottasel_len, madd_aared_len), usage)
    return {"id": sid, "usage": usage, "ready": M.ready}


def _pcm(data: bytes) -> np.ndarray:
    if len(data) % 2:
        data = data[:-1]
    return np.frombuffer(data, dtype="<i2").astype(np.float32) / 32768.0


async def _drain(s: _Session) -> None:
    while s.next_seq in s.pending:
        chunk = s.pending.pop(s.next_seq)
        s.next_seq += 1
        if s.rec.seconds > engine.MAX_SECONDS:
            continue  # past 10 minutes: ignore the rest
        await asyncio.to_thread(s.rec.feed, _pcm(chunk))


@app.post("/session/{sid}/audio")
async def session_audio(sid: str, request: Request, seq: int = Query(...)):
    s = _sessions.get(sid)
    if s is None:
        raise HTTPException(404, "Session not found.")
    data = await request.body()
    async with s.lock:
        s.pending[seq] = data
        if M.ready:  # while the model is still waking up, just keep the pieces
            await _drain(s)
    return {"ok": True, "seconds": round(s.rec.seconds, 1)}


@app.post("/session/{sid}/finish")
async def session_finish(sid: str, last_seq: int = Query(...)):
    s = _sessions.get(sid)
    if s is None:
        raise HTTPException(404, "Session not found.")
    t0 = time.time()
    await _wait_ready()
    for _ in range(100):  # wait up to 10 s for any late pieces
        if all(i in s.pending or i < s.next_seq for i in range(last_seq + 1)):
            break
        await asyncio.sleep(0.1)
    async with s.lock:
        if s.result is None:
            await _drain(s)
            s.result = await asyncio.to_thread(_result, s.rec, s.sura, s.a0, s.a1, s.strict, s.moshaf, s.usage, t0)
    _sessions.pop(sid, None)
    return s.result
