"""Original theme for the Lunar Cleanup ending (synthesised, no samples).
Follows the cinematic: a quiet swell over the spotless Moon (0-8 s), a countdown with
timpani (8-14 s), a huge chord at lift-off (14 s), the main anthem as the Moon falls
away (22-34 s), a key change heading for Earth (34-46 s) and a long resolve under the
end titles (46-64 s).
Usage: python3 tools/gen_ending_theme.py godot/assets/audio
"""
import sys, os, wave
import numpy as np

SR = 22050
LEN = 66.0
OUT = sys.argv[1] if len(sys.argv) > 1 else "godot/assets/audio"
rng = np.random.default_rng(7)
N = int(SR * LEN)
mix = np.zeros(N)


def hz(note):
    """MIDI note number -> frequency."""
    return 440.0 * 2 ** ((note - 69) / 12.0)


def add(start, sig):
    i = int(start * SR)
    j = min(N, i + len(sig))
    if j > i:
        mix[i:j] += sig[: j - i]


def adsr(n, a, d, s, r):
    e = np.full(n, s)
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = max(na, 1)
    e[:na] = np.linspace(0, 1, na)
    e[na:na + nd] = np.linspace(1, s, len(e[na:na + nd]))
    if nr > 0:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def tone(f, dur, harmonics=8, bright=1.0, vib=0.0):
    t = np.arange(int(SR * dur)) / SR
    ph = 2 * np.pi * f * t + (vib * np.sin(2 * np.pi * 5.2 * t) if vib else 0)
    out = np.zeros_like(t)
    for k in range(1, harmonics + 1):
        out += np.sin(ph * k) / (k ** (1.6 / bright))
    return out


def pad(start, notes, dur, vol=0.12, a=1.5, r=2.0):
    n = int(SR * dur)
    sig = np.zeros(n)
    for nt in notes:
        for det in (-0.08, 0.0, 0.08):          # a little chorus
            sig += tone(hz(nt + det), dur, 6, 0.7)[:n]
    add(start, sig * adsr(n, a, 0.5, 0.85, r) * vol / len(notes))


def brass(start, nt, dur, vol=0.22):
    n = int(SR * dur)
    sig = tone(hz(nt), dur, 12, 1.3, vib=0.004 * hz(nt))[:n]
    add(start, sig * adsr(n, 0.06, 0.2, 0.8, 0.35) * vol)


def bell(start, nt, vol=0.15, dur=2.5):
    t = np.arange(int(SR * dur)) / SR
    f = hz(nt)
    sig = (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 2.76 * t) + 0.25 * np.sin(2 * np.pi * f * 5.4 * t))
    add(start, sig * np.exp(-t * 2.2) * vol)


def timpani(start, nt=36, vol=0.5):
    t = np.arange(int(SR * 1.2)) / SR
    f = hz(nt) * (1 + 0.15 * np.exp(-t * 18))
    sig = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 3.5)
    sig += rng.standard_normal(len(t)) * np.exp(-t * 30) * 0.3
    add(start, sig * vol)


def rumble(start, dur, vol=0.35):
    n = int(SR * dur)
    x = rng.standard_normal(n)
    y = np.empty(n)
    acc = 0.0
    for i in range(n):            # low-passed noise
        acc = 0.985 * acc + 0.015 * x[i]
        y[i] = acc
    add(start, y / (np.abs(y).max() + 1e-9) * adsr(n, 0.3, 0.5, 0.8, 3.0) * vol)


# Chords (MIDI notes): C, G/B, Am, F, then up a tone to D, A, Bm, G
C, G, Am, F = [48, 55, 60, 64, 67], [47, 55, 59, 62, 67], [45, 52, 57, 60, 64], [41, 53, 57, 60, 65]
D, A, Bm, Gd = [50, 57, 62, 66, 69], [49, 57, 61, 64, 69], [47, 54, 59, 62, 66], [43, 55, 59, 62, 67]

# 0-8 s: the spotless Moon - quiet swell and a shimmering arpeggio
pad(0.0, [48, 55, 62, 64, 67], 8.5, 0.10, a=3.0, r=2.5)
for i in range(32):
    bell(0.5 + i * 0.25, [72, 76, 79, 83][i % 4], 0.05 + 0.002 * i, 1.2)

# 8-14 s: countdown - timpani on every second, tension chord
pad(8.0, [43, 50, 55, 59, 62], 6.2, 0.13, a=0.5, r=0.4)
for k in range(6):
    timpani(8.0 + k, 36 if k < 5 else 31, 0.35 + 0.06 * k)

# 14 s: lift-off - huge chord, rumble
pad(14.0, C + [72, 76], 8.0, 0.2, a=0.05, r=2.0)
for nt in (48, 55, 60, 64, 67, 72):
    brass(14.0, nt, 3.5, 0.08)
timpani(14.0, 31, 0.8)
rumble(14.0, 9.0, 0.3)

# 22-34 s: anthem - C G/B Am F, two bars each 1.5 s, melody on brass
prog = [C, G, Am, F, C, G, F, C]
for i, ch in enumerate(prog):
    pad(22.0 + i * 1.5, ch, 1.7, 0.13, a=0.08, r=0.4)
    timpani(22.0 + i * 1.5, 36, 0.22)
melody = [(0, 72, 1.0), (1.0, 74, 0.5), (1.5, 76, 1.5), (3.0, 79, 1.0), (4.0, 77, 0.5), (4.5, 76, 1.0),
          (5.5, 74, 0.5), (6.0, 72, 1.5), (7.5, 79, 1.5), (9.0, 81, 1.0), (10.0, 79, 0.5), (10.5, 77, 1.5)]
for s, nt, d in melody:
    brass(22.0 + s, nt, d + 0.15, 0.16)
    brass(22.0 + s, nt - 12, d + 0.15, 0.08)

# 34-46 s: heading home - up a tone, fuller
prog2 = [D, A, Bm, Gd, D, A, Gd, D]
for i, ch in enumerate(prog2):
    pad(34.0 + i * 1.5, ch + [ch[2] + 12], 1.7, 0.15, a=0.06, r=0.4)
    timpani(34.0 + i * 1.5, 38, 0.25)
for s, nt, d in melody:
    brass(34.0 + s, nt + 2, d + 0.15, 0.18)
    brass(34.0 + s, nt + 14, d + 0.15, 0.06)

# 46-66 s: resolve under the end titles - long D major, bells, fade
pad(46.0, [38, 50, 57, 62, 66, 69, 74], 19.0, 0.16, a=0.3, r=10.0)
brass(46.0, 74, 4.0, 0.12)
timpani(46.0, 38, 0.6)
for i in range(16):
    bell(47.0 + i * 1.1, [86, 81, 78, 74][i % 4], 0.07 * (1 - i / 18.0), 2.5)

# Master: gentle compression, normalise, fade the very end
mix = np.tanh(mix * 1.6) / 1.6
mix /= np.abs(mix).max() + 1e-9
mix *= 0.89
fade = int(SR * 2.0)
mix[-fade:] *= np.linspace(1, 0, fade)
os.makedirs(OUT, exist_ok=True)
with wave.open(os.path.join(OUT, "ending_theme.wav"), "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((mix * 32767).astype(np.int16).tobytes())
print("ending_theme.wav", LEN, "s")
