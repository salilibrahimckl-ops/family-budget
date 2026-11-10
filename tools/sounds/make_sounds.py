"""Generates the app's small sound effects (original, synthesised) as 16-bit mono WAV."""
import math, struct, sys, wave
from pathlib import Path

RATE = 22050

def tone(freq, dur, vol=0.35, shape="bell"):
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-4.5 * t / dur) if shape == "bell" else min(1, t * 40) * min(1, (dur - t) * 30)
        s = math.sin(2 * math.pi * freq * t) + 0.3 * math.sin(4 * math.pi * freq * t)
        out.append(vol * env * s / 1.3)
    return out

def seq(*parts, gap=0.0):
    out = []
    for p in parts:
        out += p + [0.0] * int(RATE * gap)
    return out

def write(path, samples):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32000)) for s in samples))

out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
C5, E5, G5, C6, E6 = 523.25, 659.25, 783.99, 1046.5, 1318.5
write(out / "success.wav", seq(tone(C5, .12), tone(E5, .12), tone(G5, .12), tone(C6, .35)))
write(out / "oops.wav", seq(tone(392, .15, .25, "flat"), tone(330, .28, .25, "flat")))
write(out / "star.wav", seq(tone(C6, .08, .25), tone(E6, .25, .25)))
write(out / "levelup.wav", seq(tone(C5, .1), tone(E5, .1), tone(G5, .1), tone(C6, .1), tone(G5, .1), tone(C6, .5)))
print("sounds written")
