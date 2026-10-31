#!/usr/bin/env python3
"""Procedural audio generator for The Irish Pub Simulator.

Every sound effect and music track in the game is synthesised by this script
from scratch (numpy oscillators, filtered noise and Karplus-Strong strings).
The tunes are original compositions written for this project. Output is
written to ../assets/audio as Ogg Vorbis via ffmpeg.

Run:  python3 tools/gen_audio.py
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
rng = np.random.default_rng(1916)


# ---------------------------------------------------------------- helpers
def t_axis(dur):
    return np.arange(int(dur * SR)) / SR


def noise(dur):
    return rng.uniform(-1, 1, int(dur * SR))


def lowpass(x, cutoff):
    """One-pole lowpass (cheap, stable)."""
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y


def lowpass_fast(x, cutoff):
    # vectorised approximation via FFT brickwall with soft knee
    n = len(x)
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    resp = 1 / np.sqrt(1 + (freqs / max(cutoff, 1)) ** 4)
    return np.fft.irfft(f * resp, n)


def bandpass_fast(x, lo, hi):
    n = len(x)
    f = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    resp = 1 / np.sqrt(1 + (freqs / max(hi, 1)) ** 4) * (1 - 1 / np.sqrt(1 + (freqs / max(lo, 1)) ** 4))
    return np.fft.irfft(f * resp, n)


def env_adsr(n, a, d, s, r):
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    s_n = max(0, n - a_n - d_n - r_n)
    e = np.concatenate([
        np.linspace(0, 1, max(a_n, 1)),
        np.linspace(1, s, max(d_n, 1)),
        np.full(s_n, s),
        np.linspace(s, 0, max(r_n, 1)),
    ])
    if len(e) < n:
        e = np.pad(e, (0, n - len(e)))
    return e[:n]


def normalize(x, peak=0.9):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def loopify(x, fade=0.4):
    """Crossfade the tail into the head so the clip loops seamlessly."""
    f = int(fade * SR)
    head = x[:f].copy()
    tail = x[-f:].copy()
    ramp = np.linspace(0, 1, f)
    x = x[:-f].copy()
    x[:f] = head * ramp + tail * (1 - ramp)
    return x


def save(name, x, loop=False):
    os.makedirs(OUT, exist_ok=True)
    x = np.clip(x, -1, 1)
    pcm = (x * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        path = tmp.name
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    dst = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-c:a", "libvorbis", "-q:a", "3", dst], check=True)
    os.remove(path)
    print("wrote", dst, f"{len(x) / SR:.1f}s")


# ---------------------------------------------------------------- sfx
def sfx_pour_loop():
    d = 3.0
    n = noise(d)
    body = bandpass_fast(n, 300, 2200) * 0.6
    # gurgle: amplitude modulated by slow random wobble
    wob = lowpass_fast(noise(d), 9) * 6
    gurgle = bandpass_fast(noise(d), 500, 1200) * (0.5 + 0.5 * np.sin(2 * np.pi * (11 + wob) * t_axis(d)))
    return loopify(normalize(body + 0.5 * gurgle, 0.6))


def sfx_bubbles_loop():
    d = 3.0
    x = np.zeros(int(d * SR))
    for _ in range(260):
        start = rng.integers(0, len(x) - 2000)
        f0 = rng.uniform(900, 3200)
        ln = rng.integers(300, 900)
        tt = np.arange(ln) / SR
        blip = np.sin(2 * np.pi * (f0 + 2500 * tt) * tt) * np.exp(-tt * 90)
        x[start:start + ln] += blip * rng.uniform(0.1, 0.4)
    return loopify(normalize(x, 0.4))


def sfx_tap_clunk():
    d = 0.35
    tt = t_axis(d)
    thud = np.sin(2 * np.pi * 140 * tt) * np.exp(-tt * 28)
    metal = (np.sin(2 * np.pi * 1730 * tt) + 0.6 * np.sin(2 * np.pi * 2810 * tt)) * np.exp(-tt * 22)
    click = noise(d) * np.exp(-tt * 200)
    return normalize(thud + 0.35 * metal + 0.4 * click, 0.8)


def sfx_glass_place():
    d = 0.5
    tt = t_axis(d)
    knock = lowpass_fast(noise(d), 1500) * np.exp(-tt * 60)
    ring = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt * k) * g for f, k, g in [(2310, 9, .4), (3570, 12, .25), (5120, 16, .15)])
    return normalize(knock + ring, 0.7)


def sfx_clink():
    d = 0.9
    tt = t_axis(d)
    ring = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt * k) * g for f, k, g in [(2630, 5, .5), (2655, 5, .4), (4210, 7, .3), (6060, 10, .2)])
    return normalize(ring + noise(d) * np.exp(-tt * 300) * 0.3, 0.7)


def sfx_coins():
    d = 0.9
    x = np.zeros(int(d * SR))
    for i in range(7):
        st = int((0.02 + i * 0.07 + rng.uniform(0, 0.03)) * SR)
        ln = int(0.3 * SR)
        tt = np.arange(ln) / SR
        f = rng.uniform(3200, 5200)
        x[st:st + ln] += (np.sin(2 * np.pi * f * tt) + 0.5 * np.sin(2 * np.pi * f * 1.48 * tt)) * np.exp(-tt * 25) * rng.uniform(.4, 1)
    return normalize(x, 0.6)


def sfx_till():
    d = 1.2
    tt = t_axis(d)
    bell = (np.sin(2 * np.pi * 1568 * tt) + 0.4 * np.sin(2 * np.pi * 3136 * tt)) * np.exp(-tt * 4)
    drawer = lowpass_fast(noise(d), 600) * np.exp(-((tt - 0.05) ** 2) / 0.002) * 0.6
    return normalize(bell + drawer, 0.6)


def sfx_wash_loop():
    d = 3.0
    water = bandpass_fast(noise(d), 800, 5000)
    slosh = lowpass_fast(noise(d), 4) * 8
    return loopify(normalize(water * (0.6 + 0.4 * np.clip(slosh, -1, 1)), 0.45))


def sfx_squeak():
    d = 0.4
    tt = t_axis(d)
    f = 1800 + 600 * np.sin(2 * np.pi * 7 * tt)
    ph = np.cumsum(f) / SR
    return normalize(np.sin(2 * np.pi * ph) * env_adsr(len(tt), .03, .1, .6, .15) * 0.5 + bandpass_fast(noise(d), 2000, 6000) * 0.2, 0.4)


def sfx_step(seed):
    r = np.random.default_rng(seed)
    d = 0.22
    tt = t_axis(d)
    thump = np.sin(2 * np.pi * r.uniform(85, 110) * tt) * np.exp(-tt * 35)
    creak = bandpass_fast(r.uniform(-1, 1, len(tt)), 200, 900) * np.exp(-tt * 40)
    return normalize(thump + 0.5 * creak, 0.5)


def sfx_knock():
    """Three firm knocks on a wooden door."""
    out = np.zeros(int(SR * 1.3))
    for i, t0 in enumerate([0.0, 0.32, 0.64]):
        d = 0.18
        t = t_axis(d)
        body = np.sin(2 * np.pi * (110 - 30 * t / d) * t) * np.exp(-t * 28)
        click = lowpass_fast(noise(d), 1800) * np.exp(-t * 60) * 0.6
        s0 = int(t0 * SR)
        seg = (body + click) * (1.0 - 0.1 * i)
        out[s0:s0 + len(seg)] += seg
    return normalize(out, 0.85)


def sfx_door_bell():
    d = 1.8
    tt = t_axis(d)
    x = np.zeros_like(tt)
    for off in (0.0, 0.18):
        ts = np.clip(tt - off, 0, None)
        g = (tt >= off)
        x += g * (np.sin(2 * np.pi * 2093 * ts) + 0.5 * np.sin(2 * np.pi * 2637 * ts) + 0.3 * np.sin(2 * np.pi * 4186 * ts)) * np.exp(-ts * 5)
    return normalize(x, 0.5)


def sfx_church_bell():
    d = 5.0
    tt = t_axis(d)
    partials = [(0.5, 1.0, 0.6), (1.0, 0.7, 1.0), (1.19, 0.5, 0.6), (1.5, 0.4, 0.5), (2.0, 0.35, 0.4), (2.52, 0.3, 0.25)]
    f0 = 392
    x = sum(np.sin(2 * np.pi * f0 * m * tt) * np.exp(-tt * (0.6 + k)) * g for m, k, g in partials)
    return normalize(x, 0.5)


def sfx_crowd_loop(density):
    """Murmuring crowd built from many short formant 'syllables'."""
    d = 8.0
    n = int(d * SR)
    x = np.zeros(n)
    voices = int(6 * density)
    src = noise(d)
    for v in range(voices):
        f0 = rng.uniform(95, 230)
        t = 0.0
        while t < d - 0.4:
            ln = rng.uniform(0.08, 0.25)
            st = int(t * SR)
            m = int(ln * SR)
            tt = np.arange(m) / SR
            pitch = f0 * (1 + 0.15 * np.sin(2 * np.pi * rng.uniform(1, 4) * tt))
            ph = np.cumsum(pitch) / SR
            buzz = np.sign(np.sin(2 * np.pi * ph)) * 0.3 + np.sin(2 * np.pi * ph)
            formant = rng.choice([500, 700, 900, 1200])
            syll = buzz * np.sin(np.pi * tt / ln) ** 2
            x[st:st + m] += syll * rng.uniform(0.2, 0.6) * (0.4 + 0.6 * np.sin(2 * np.pi * formant * tt / 900) ** 2)
            t += ln + (rng.uniform(0.02, 0.1) if rng.random() < 0.8 else rng.uniform(0.4, 1.2))
    x = bandpass_fast(x, 180, 2500) + bandpass_fast(src, 300, 1500) * 0.05
    return loopify(normalize(x, 0.5), 0.8)


def sfx_rain_loop():
    d = 6.0
    hiss = bandpass_fast(noise(d), 1500, 9000) * 0.35
    x = hiss.copy()
    for _ in range(900):
        st = rng.integers(0, len(x) - 400)
        ln = 300
        tt = np.arange(ln) / SR
        x[st:st + ln] += np.sin(2 * np.pi * rng.uniform(2000, 6000) * tt) * np.exp(-tt * 300) * rng.uniform(0.05, 0.3)
    return loopify(normalize(x, 0.5), 0.8)


def sfx_fire_loop():
    d = 6.0
    roar = lowpass_fast(noise(d), 250) * 3
    x = roar
    for _ in range(140):
        st = rng.integers(0, len(x) - 900)
        ln = rng.integers(100, 800)
        tt = np.arange(ln) / SR
        x[st:st + ln] += bandpass_fast(rng.uniform(-1, 1, ln), 1500, 7000) * np.exp(-tt * rng.uniform(60, 300)) * rng.uniform(.3, 1.5)
    return loopify(normalize(x, 0.5), 0.8)


def sfx_ui_click():
    d = 0.08
    tt = t_axis(d)
    return normalize(np.sin(2 * np.pi * 1200 * tt) * np.exp(-tt * 70) + noise(d) * np.exp(-tt * 400) * 0.3, 0.4)


def sfx_ui_buy():
    d = 0.6
    tt = t_axis(d)
    x = np.zeros_like(tt)
    for i, f in enumerate([784, 988, 1175, 1568]):
        st = i * 0.07
        g = tt >= st
        ts = np.clip(tt - st, 0, None)
        x += g * np.sin(2 * np.pi * f * ts) * np.exp(-ts * 9)
    return normalize(x, 0.5)


def sfx_dart_throw():
    d = 0.3
    tt = t_axis(d)
    whoosh = bandpass_fast(noise(d), 600, 3000) * np.sin(np.pi * tt / d) ** 2
    return normalize(whoosh, 0.4)


def sfx_dart_hit():
    d = 0.3
    tt = t_axis(d)
    thock = (np.sin(2 * np.pi * 220 * tt) + lowpass_fast(noise(d), 2500)) * np.exp(-tt * 45)
    return normalize(thock, 0.7)


def sfx_sip():
    d = 0.7
    tt = t_axis(d)
    slurp = bandpass_fast(noise(d), 400, 2500) * env_adsr(len(tt), 0.08, 0.2, 0.6, 0.3)
    gulp = np.sin(2 * np.pi * (180 - 80 * np.clip(tt - 0.45, 0, 1)) * tt) * np.exp(-((tt - 0.55) ** 2) / 0.002)
    return normalize(slurp * 0.6 + gulp * 0.7, 0.5)


def sfx_cheer():
    d = 2.5
    tt = t_axis(d)
    crowd = sfx_crowd_loop(3.0)[: len(tt)]
    swell = np.sin(np.pi * tt / d) ** 1.5
    hiss = bandpass_fast(noise(d), 800, 4000) * 0.4
    return normalize((crowd + hiss) * swell, 0.7)


def sfx_groan():
    d = 1.5
    tt = t_axis(d)
    crowd = sfx_crowd_loop(2.0)[: len(tt)]
    f = 220 - 70 * tt / d
    ph = np.cumsum(f) / SR
    tone = np.sin(2 * np.pi * ph) * 0.5 + np.sign(np.sin(2 * np.pi * ph)) * 0.1
    return normalize((bandpass_fast(tone, 150, 1500) + crowd * 0.5) * np.sin(np.pi * tt / d), 0.6)


def sfx_laugh():
    """A small crowd laughing: several voices of rhythmic 'ha' syllables."""
    d = 2.6
    n = int(d * SR)
    x = np.zeros(n)
    for v in range(7):
        f0 = rng.uniform(140, 300)
        t = rng.uniform(0.0, 0.3)
        k = 0
        while t < d - 0.3 and k < rng.integers(4, 9):
            ln = rng.uniform(0.09, 0.14)
            st = int(t * SR)
            m = int(ln * SR)
            tt = np.arange(m) / SR
            f = f0 * (1.0 - 0.15 * k / 8.0) * (1 + 0.1 * np.sin(2 * np.pi * 6 * tt))
            ph = np.cumsum(f) / SR
            voiced = np.sin(2 * np.pi * ph) + 0.5 * np.sin(4 * np.pi * ph) + 0.3 * np.sin(6 * np.pi * ph)
            breath = rng.uniform(-1, 1, m) * 0.5
            env = np.sin(np.pi * tt / ln) ** 1.5
            x[st:st + m] += (voiced * 0.6 + breath) * env * rng.uniform(0.3, 0.7)
            t += ln + rng.uniform(0.04, 0.09)
            k += 1
    x = bandpass_fast(x, 200, 3500)
    tt = t_axis(d)
    return normalize(x * np.clip(1.4 - tt / d, 0, 1), 0.6)


def sfx_bodhran(pitch=1.0, dur=0.5):
    tt = t_axis(dur)
    f = 85 * pitch * (1 + 0.6 * np.exp(-tt * 40))
    ph = np.cumsum(f) / SR
    body = np.sin(2 * np.pi * ph) * np.exp(-tt * 9)
    slap = lowpass_fast(noise(dur), 3000) * np.exp(-tt * 70) * 0.5
    return body + slap


def sfx_spill():
    d = 0.8
    tt = t_axis(d)
    splash = bandpass_fast(noise(d), 300, 4000) * np.exp(-tt * 6) * (1 - np.exp(-tt * 80))
    return normalize(splash, 0.5)


def sfx_keg():
    d = 1.4
    tt = t_axis(d)
    clank = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt * k) for f, k in [(310, 6), (742, 8), (1190, 10)])
    hiss = bandpass_fast(noise(d), 3000, 9000) * np.clip((tt - 0.5) * 4, 0, 1) * np.exp(-np.clip(tt - 0.5, 0, None) * 3)
    return normalize(clank * np.exp(-tt * 2) + hiss * 0.6, 0.6)


def sfx_sizzle_loop():
    d = 3.0
    x = bandpass_fast(noise(d), 2500, 9000) * (0.6 + 0.4 * np.clip(lowpass_fast(noise(d), 6) * 6, -1, 1))
    return loopify(normalize(x, 0.35))


# ---------------------------------------------------------------- music
NOTE_BASE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
KEY_D = {"F": 1, "C": 1}
KEY_G = {"F": 1}


def parse_abc(s, key):
    """Tiny ABC subset -> list of (midi or None, units)."""
    out = []
    i = 0
    while i < len(s):
        ch = s[i]
        if ch in " |:\n":
            i += 1
            continue
        acc = None
        if ch in "^_=":
            acc = {"^": 1, "_": -1, "=": 0}[ch]
            i += 1
            ch = s[i]
        if ch == "z":
            midi = None
            i += 1
        else:
            up = ch.upper()
            base = NOTE_BASE[up]
            octave = 5 if ch.islower() else 4
            i += 1
            while i < len(s) and s[i] in "',":
                octave += 1 if s[i] == "'" else -1
                i += 1
            semis = acc if acc is not None else key.get(up, 0)
            midi = 12 * (octave + 1) + base + semis  # C4 = 60
        # duration
        num = ""
        while i < len(s) and s[i].isdigit():
            num += s[i]
            i += 1
        dur = float(num) if num else 1.0
        if i < len(s) and s[i] == "/":
            dur /= 2
            i += 1
        out.append((midi, dur))
    return out


def mtof(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def inst_whistle(f, dur):
    tt = t_axis(dur)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.5 * tt) * np.clip(tt * 4, 0, 1)
    ph = np.cumsum(f * vib) / SR
    tone = np.sin(2 * np.pi * ph) + 0.12 * np.sin(4 * np.pi * ph) + 0.04 * np.sin(6 * np.pi * ph)
    breath = bandpass_fast(noise(dur), f * 0.8, f * 3) * 0.08
    return (tone + breath) * env_adsr(len(tt), 0.015, 0.05, 0.85, 0.04)


def inst_fiddle(f, dur):
    tt = t_axis(dur)
    vib = 1 + 0.008 * np.sin(2 * np.pi * 5.8 * tt) * np.clip(tt * 3 - 0.2, 0, 1)
    ph = np.cumsum(f * vib) / SR
    saw = sum(np.sin(2 * np.pi * k * ph) / k * (0.9 ** k) for k in range(1, 12))
    body = saw * (1 + 0.15 * np.sin(2 * np.pi * 2 * ph))
    scratch = bandpass_fast(noise(dur), 2000, 6000) * np.exp(-tt * 40) * 0.15
    return (body * 0.5 + scratch) * env_adsr(len(tt), 0.03, 0.06, 0.8, 0.05)


def inst_accordion(f, dur):
    tt = t_axis(dur)
    out = 0
    for det in (1.0, 1.004, 0.997):
        ph = f * det * tt
        sq = sum(np.sin(2 * np.pi * k * ph) / k for k in (1, 3, 5, 7))
        out = out + sq
    return out * 0.25 * env_adsr(len(tt), 0.03, 0.05, 0.9, 0.05)


def karplus(f, dur, decay=0.996):
    """Karplus-Strong plucked string, processed one period at a time."""
    n = int(dur * SR)
    p = max(2, int(SR / f))
    out = np.zeros(n + p + 1)
    out[:p + 1] = rng.uniform(-1, 1, p + 1)
    i = p + 1
    while i < len(out):
        j = min(i + p, len(out))
        out[i:j] = decay * 0.5 * (out[i - p:j - p] + out[i - p - 1:j - p - 1])
        i = j
    return out[:n]


def inst_guitar_chord(root_midi, minor, dur):
    ints = [0, 7, 12, 15 if minor else 16, 19]
    out = np.zeros(int(dur * SR))
    for j, iv in enumerate(ints):
        st = int(j * 0.012 * SR)
        s = karplus(mtof(root_midi + iv - 12), dur - j * 0.012, decay=0.998)
        out[st:st + len(s)] += s * 0.35
    return out


def inst_banjo(f, dur):
    s = karplus(f, dur, decay=0.99)
    return bandpass_fast(s, 300, 6000)


CHORDS = {"D": (62, False), "G": (67, False), "A": (69, False), "Em": (64, True), "Bm": (71, True), "C": (60, False), "E": (64, False)}


def render_melody(abc, key, unit, inst, gain=1.0, swing=0.0, octave=0):
    notes = parse_abc(abc, key)
    total = sum(d for _, d in notes) * unit + 1.0
    out = np.zeros(int(total * SR))
    t = 0.0
    idx = 0
    for m, d in notes:
        dur = d * unit
        # jig/reel lilt: lengthen on-beat eighths slightly
        if swing and d == 1:
            dur = unit * (1 + swing if idx % 2 == 0 else 1 - swing)
        if m is not None:
            s = inst(mtof(m + 12 * octave), dur * 0.97 + 0.03)
            st = int(t * SR)
            out[st:st + len(s)] += s[: len(out) - st] * gain
        t += dur
        idx += 1 if d == 1 else 0
    return out[: int(t * SR) + int(0.5 * SR)], t


def render_chords(chords, bar_len, beats_per_bar, total_len, strum=True):
    out = np.zeros(int((total_len + 2) * SR))
    for b, ch in enumerate(chords):
        root, minor = CHORDS[ch]
        for beat in range(beats_per_bar):
            t = b * bar_len + beat * bar_len / beats_per_bar
            s = inst_guitar_chord(root, minor, bar_len / beats_per_bar * 1.2)
            st = int(t * SR)
            s = s[: max(0, len(out) - st)]
            out[st:st + len(s)] += s * (1.0 if beat == 0 else 0.6)
    return out


def render_bodhran(bars, bar_len, pattern, total_len):
    out = np.zeros(int((total_len + 2) * SR))
    for b in range(bars):
        for pos, pitch, g in pattern:
            t = b * bar_len + pos * bar_len
            s = sfx_bodhran(pitch, 0.45) * g
            st = int(t * SR)
            s = s[: max(0, len(out) - st)]
            out[st:st + len(s)] += s
    return out


def mix(*tracks):
    n = max(len(t) for t, _ in tracks)
    out = np.zeros(n)
    for t, g in tracks:
        out[: len(t)] += t * g
    return out


# Original tunes (composed for this game).
JIG_A = "dfa afd|gbg fdf|ecA Ace|gfe fdB|dfa afd|gbg fdB|AFA Bcd|e3 d3|"
JIG_B = "faf gbg|faf ecA|dcd ede|fdB AFD|faf gbg|afd ecA|BAB cBc|d3 d3|"
JIG_CH_A = ["D", "G", "A", "Em", "D", "G", "D", "A"]
JIG_CH_B = ["D", "G", "D", "Bm", "D", "D", "G", "D"]

REEL_A = "FAAB AFED|FAAB d2fe|dBAF ABde|fedB A2FE|FAAB AFED|FAAB d2fe|dBAF ABde|fdec d4|"
REEL_B = "faaf gfed|faaf b2af|gfed BdAF|GBAG FEDE|faaf gfed|faaf b2af|gfed BdAF|EFGE D4|"
REEL_CH_A = ["D", "D", "G", "A", "D", "D", "G", "D"]
REEL_CH_B = ["D", "Bm", "G", "Em", "D", "Bm", "G", "D"]

AIR = "D2F2A2|B3AF2|A2d2cB|A4F2|G2B2d2|e3dB2|A2F2ED|D6|d2c2B2|A3FD2|E2F2G2|A4Bc|d2A2F2|G3FE2|D2F2E2|D6|"
AIR_CH = ["D", "G", "D", "D", "G", "Em", "A", "D", "Bm", "D", "A", "A", "D", "G", "A", "D"]

POLKA_A = "A2FA|d2dB|AFEF|D2D2|A2FA|d2dc|Bdce|d2d2|"
POLKA_B = "f2fe|dBAF|G2GB|A2A2|f2fe|dBAF|EFGE|D4|"
POLKA_CH_A = ["D", "G", "D", "D", "D", "G", "A", "D"]
POLKA_CH_B = ["D", "D", "G", "A", "D", "D", "A", "D"]

HORNPIPE = "D2FA dAFA|B2GB dBGB|A2FA dAFA|EFGA BAGF|D2FA dAFA|B2GB dBGB|ABcd efge|d2f2 d2|"
HP_CH = ["D", "G", "D", "A", "D", "G", "A", "D"]


def music_trad_circle():
    unit = 60 / (112 * 3)
    form = JIG_A + JIG_A + JIG_B + JIG_B
    form = form * 2
    chords = (JIG_CH_A * 2 + JIG_CH_B * 2) * 2
    whistle, L = render_melody(form, KEY_D, unit, inst_whistle, 0.6, swing=0.12, octave=1)
    fiddle, _ = render_melody(form, KEY_D, unit, inst_fiddle, 0.5, swing=0.12)
    bar = unit * 6
    bod = render_bodhran(len(chords), bar, [(0, 1.0, 1.0), (1 / 3, 1.3, 0.4), (0.5, 1.0, 0.7), (5 / 6, 1.3, 0.4)], L)
    return normalize(mix((whistle, 1), (fiddle, 0.8), (bod, 0.5)), 0.8)


def music_folk_band():
    unit = 60 / (104 * 2) / 2 * 2  # eighth at 104 bpm half-note feel
    unit = 0.142
    form = (REEL_A * 2 + REEL_B * 2) * 2
    chords = (REEL_CH_A * 2 + REEL_CH_B * 2) * 2
    fiddle, L = render_melody(form, KEY_D, unit, inst_fiddle, 0.5, swing=0.08)
    acc, _ = render_melody(form, KEY_D, unit, inst_accordion, 0.35, swing=0.08)
    banjo, _ = render_melody(form, KEY_D, unit, inst_banjo, 0.3, swing=0.08)
    bar = unit * 8
    gtr = render_chords(chords, bar, 4, L)
    bod = render_bodhran(len(chords), bar, [(0, 1.0, 1), (0.25, 1.3, .5), (0.5, 1.0, .8), (0.75, 1.3, .5), (0.875, 1.5, .3)], L)
    return normalize(mix((fiddle, 1), (acc, 0.8), (banjo, 0.6), (gtr, 0.5), (bod, 0.5)), 0.8)


def music_solo_session():
    unit = 0.42
    form = AIR + AIR
    fiddle, L = render_melody(form, KEY_D, unit, inst_fiddle, 0.6)
    bar = unit * 6
    gtr = render_chords(AIR_CH * 2, bar, 1, L)
    return normalize(mix((fiddle, 1), (gtr, 0.35)), 0.75)


def music_singalong():
    unit = 0.19
    form = (POLKA_A * 2 + POLKA_B * 2) * 2
    chords = (POLKA_CH_A * 2 + POLKA_CH_B * 2) * 2
    acc, L = render_melody(form, KEY_D, unit, inst_accordion, 0.5)
    whistle, _ = render_melody(form, KEY_D, unit, inst_whistle, 0.4, octave=1)
    bar = unit * 4
    gtr = render_chords(chords, bar, 2, L)
    bod = render_bodhran(len(chords), bar, [(0, 1.0, 1), (0.5, 1.3, .7)], L)
    # crowd 'humming' along an octave down, soft
    hum, _ = render_melody(form, KEY_D, unit, lambda f, d: inst_accordion(f, d) * 0.5, 0.25, octave=-1)
    hum = lowpass_fast(hum, 900)
    return normalize(mix((acc, 1), (whistle, 0.6), (gtr, 0.6), (bod, 0.5), (hum, 0.5)), 0.8)


def music_jukebox_hornpipe():
    unit = 0.16
    form = HORNPIPE * 4
    gtr_ch = HP_CH * 4
    acc, L = render_melody(form, KEY_D, unit, inst_accordion, 0.5, swing=0.2)
    bar = unit * 8
    gtr = render_chords(gtr_ch, bar, 2, L)
    return normalize(mix((acc, 1), (gtr, 0.5)), 0.75)


def bodhran_hit():
    return normalize(sfx_bodhran(1.0, 0.5), 0.8)


def main():
    save("pour_loop", sfx_pour_loop())
    save("bubbles_loop", sfx_bubbles_loop())
    save("tap_clunk", sfx_tap_clunk())
    save("glass_place", sfx_glass_place())
    save("clink", sfx_clink())
    save("coins", sfx_coins())
    save("till", sfx_till())
    save("wash_loop", sfx_wash_loop())
    save("squeak", sfx_squeak())
    for i in range(3):
        save(f"step{i}", sfx_step(40 + i))
    save("door_bell", sfx_door_bell())
    save("knock", sfx_knock())
    save("church_bell", sfx_church_bell())
    save("crowd_loop", sfx_crowd_loop(1.6))
    save("rain_loop", sfx_rain_loop())
    save("fire_loop", sfx_fire_loop())
    save("ui_click", sfx_ui_click())
    save("ui_buy", sfx_ui_buy())
    save("dart_throw", sfx_dart_throw())
    save("dart_hit", sfx_dart_hit())
    save("sip", sfx_sip())
    save("cheer", sfx_cheer())
    save("groan", sfx_groan())
    save("bodhran", bodhran_hit())
    save("spill", sfx_spill())
    save("keg", sfx_keg())
    save("sizzle_loop", sfx_sizzle_loop())
    save("laugh", sfx_laugh())


if __name__ == "__main__":
    main()
