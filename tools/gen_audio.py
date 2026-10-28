"""Procedurally generates every sound effect and the music loop for Lunar Cleanup.
All audio is original (synthesised from noise/oscillators) - no third-party samples.
Usage: python3 tools/gen_audio.py godot/assets/audio
"""
import sys, os, wave
import numpy as np

SR = 22050
rng = np.random.default_rng(1969)
OUT = sys.argv[1] if len(sys.argv) > 1 else "godot/assets/audio"
os.makedirs(OUT, exist_ok=True)

def t(sec):
    return np.arange(int(SR * sec)) / SR

def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1 - a) * x[i] + a * acc
        y[i] = acc
    return y

def fft_filter(x, lo, hi):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    mask = np.clip((f - lo) / max(lo * 0.3, 1), 0, 1) * np.clip((hi - f) / (hi * 0.3), 0, 1)
    return np.fft.irfft(X * mask, len(x))

def noise(sec):
    return rng.standard_normal(int(SR * sec))

def env(n, a=0.01, r=0.1, sustain=True):
    e = np.ones(n)
    na = max(1, int(a * SR)); nr = max(1, int(r * SR))
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr)
    return e

def norm(x, peak=0.8):
    m = np.max(np.abs(x)) or 1
    return x / m * peak

def loopify(x, fade=0.05):
    """Crossfade the tail into the head so the loop is seamless."""
    n = int(fade * SR)
    head = x[:n].copy(); tail = x[-n:].copy()
    w = np.linspace(0, 1, n)
    x = x[:-n].copy()
    x[:n] = head * w + tail * (1 - w)
    return x

def save(name, x, peak=0.8):
    x = norm(x, peak)
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name, len(data) / SR, "s")

# --- Brushing: bristle scrape noise with a rhythmic back-and-forth scrub ---
def brush(sec, lo, hi, rate, grit):
    n = noise(sec)
    b = fft_filter(n, lo, hi)
    tt = t(sec)[: len(b)]
    stroke = 0.55 + 0.45 * np.abs(np.sin(np.pi * rate * tt)) ** 0.7
    clicks = (rng.random(len(b)) < grit) * rng.standard_normal(len(b)) * 4
    clicks = fft_filter(clicks, 2000, 9000)
    return loopify((b * stroke + clicks * stroke) * 1.0)

save("brush_small", brush(2.0, 2500, 9000, 3.0, 0.004), 0.55)
save("brush_large", brush(2.0, 900, 6000, 2.0, 0.006), 0.6)

# --- Electric scrubber / rotary: motor hum + whirring bristles ---
def motor(sec, f0, wob, noise_amt, lo, hi):
    tt = t(sec)
    ph = 2 * np.pi * f0 * tt + wob * np.sin(2 * np.pi * 4 * tt)
    m = np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.25 * np.sin(3 * ph) + 0.12 * np.sin(5 * ph)
    nz = fft_filter(noise(sec), lo, hi)[: len(tt)]
    return loopify(m * 0.4 + nz * noise_amt)

save("scrubber_loop", motor(2.0, 110, 0.6, 1.2, 1200, 7000), 0.55)
save("rotary_loop", motor(2.0, 70, 1.5, 1.6, 400, 5000), 0.6)

# --- Vacuum: rushing air + turbine whine ---
def vacuum(sec, whine, air_lo, air_hi):
    tt = t(sec)
    air = fft_filter(noise(sec), air_lo, air_hi)[: len(tt)] * 1.6
    w = np.sin(2 * np.pi * whine * tt + 0.3 * np.sin(2 * np.pi * 0.7 * tt)) * 0.25
    w += np.sin(2 * np.pi * whine * 2.01 * tt) * 0.1
    rumble = fft_filter(noise(sec), 40, 200)[: len(tt)] * 0.8
    return loopify(air + w + rumble)

save("vacuum_loop", vacuum(2.0, 820, 300, 6000), 0.6)
save("industrial_vacuum_loop", vacuum(2.0, 460, 120, 3500), 0.65)

# --- Cleaning beam: shimmering sci-fi hum ---
tt = t(3.0)
beam = sum(np.sin(2 * np.pi * f * tt + i) * a for i, (f, a) in enumerate([(220, 0.5), (221.7, 0.5), (330, 0.3), (441, 0.2), (660.5, 0.12)]))
beam *= 0.7 + 0.3 * np.sin(2 * np.pi * 6 * tt)
beam += fft_filter(noise(3.0), 3000, 10000)[: len(tt)] * 0.25
save("beam_loop", loopify(beam), 0.5)

# --- Footsteps: soft regolith crunch ---
for i in range(3):
    n = noise(0.22)
    c = fft_filter(n, 300 + i * 120, 4000) * np.exp(-t(0.22)[: len(n)] * (22 + i * 3))
    th = np.sin(2 * np.pi * (70 + i * 8) * t(0.22)) * np.exp(-t(0.22) * 30) * 1.5
    save("step_%d" % (i + 1), c + th[: len(c)], 0.5)

# --- Jump / land ---
n = noise(0.35)
save("jump", fft_filter(n, 200, 2500) * np.exp(-t(0.35)[: len(n)] * 10) + np.sin(2 * np.pi * np.linspace(180, 360, len(n)) * t(0.35)[: len(n)]) * 0.3 * np.exp(-t(0.35)[: len(n)] * 8), 0.5)
n = noise(0.4)
save("land", fft_filter(n, 80, 1800) * np.exp(-t(0.4)[: len(n)] * 9) * 1.5 + np.sin(2 * np.pi * 55 * t(0.4)[: len(n)]) * np.exp(-t(0.4)[: len(n)] * 12), 0.6)

# --- Tonal UI / reward sounds ---
def tone(freq, sec, decay=6.0, harm=(1, 0.5, 0.25), shape="sine"):
    tt = t(sec)
    x = np.zeros_like(tt)
    for k, a in enumerate(harm):
        x += a * np.sin(2 * np.pi * freq * (k + 1) * tt)
    return x * np.exp(-tt * decay) * env(len(tt), 0.003, 0.02)

def seq(notes, gap, sec, decay=6, harm=(1, 0.4, 0.2)):
    total = int(SR * (gap * len(notes) + sec))
    out = np.zeros(total)
    for i, f in enumerate(notes):
        s = int(i * gap * SR)
        tn = tone(f, sec, decay, harm)
        out[s : s + len(tn)] += tn
    return out

save("coin", seq([1318.5, 1975.5], 0.07, 0.35, 9, (1, 0.3, 0.1)), 0.5)
save("sell", seq([1046.5, 1318.5, 1568, 2093, 1568, 2093, 2637], 0.06, 0.4, 8, (1, 0.35, 0.15)), 0.55)
save("purchase", seq([523.25, 659.25, 783.99, 1046.5], 0.08, 0.6, 5, (1, 0.5, 0.25, 0.1)), 0.6)
save("upgrade", seq([392, 523.25, 659.25, 783.99, 1046.5, 1318.5], 0.07, 0.7, 4, (1, 0.6, 0.3, 0.15)) , 0.6)
save("mission", seq([523.25, 659.25, 783.99, 1046.5, 783.99, 1046.5, 1318.5], 0.11, 0.9, 3.5, (1, 0.5, 0.3, 0.2)), 0.6)
save("ui_click", tone(1400, 0.06, 60, (1, 0.2)), 0.4)
save("ui_back", tone(700, 0.08, 45, (1, 0.3)), 0.4)
save("ui_open", seq([880, 1320], 0.04, 0.12, 30, (1, 0.2)), 0.4)
save("error", seq([220, 185], 0.12, 0.25, 10, (1, 0.6, 0.4, 0.3)), 0.5)
save("tank_full", seq([988, 0.001, 988, 0.001, 988], 0.09, 0.08, 25, (1, 0.3)), 0.45)
save("pickup", seq([660, 990, 1320], 0.05, 0.3, 10, (1, 0.4)), 0.5)
save("place", tone(160, 0.35, 12, (1, 0.8, 0.5, 0.3)) + fft_filter(noise(0.35), 100, 2000)[: int(0.35 * SR)] * np.exp(-t(0.35) * 15) * 0.6, 0.6)

# --- Vehicle electric motor (pitch-shifted at runtime) ---
tt = t(2.0)
eng = np.sin(2 * np.pi * 140 * tt) * 0.5 + np.sin(2 * np.pi * 280 * tt) * 0.3 + np.sin(2 * np.pi * 420.5 * tt) * 0.15
eng += fft_filter(noise(2.0), 500, 3000)[: len(tt)] * 0.25
eng *= 0.85 + 0.15 * np.sin(2 * np.pi * 9 * tt)
save("engine_loop", loopify(eng), 0.5)

# --- Machine hum for automation ---
tt = t(2.0)
mh = np.sin(2 * np.pi * 90 * tt) * 0.5 + np.sin(2 * np.pi * 180.3 * tt) * 0.25 + fft_filter(noise(2.0), 600, 2500)[: len(tt)] * 0.3
mh *= 0.8 + 0.2 * np.sign(np.sin(2 * np.pi * 2 * tt))
save("machine_loop", loopify(lowpass(mh, 3000)), 0.45)

# --- Drone propeller buzz ---
tt = t(1.5)
dr = np.sign(np.sin(2 * np.pi * 190 * tt)) * 0.2 + np.sin(2 * np.pi * 380 * tt) * 0.2
dr = lowpass(dr, 1800) + fft_filter(noise(1.5), 1500, 5000)[: len(tt)] * 0.2
save("drone_loop", loopify(dr), 0.4)

# --- Rocket launch (shipping depot) ---
sec = 3.0
n = noise(sec)
r = fft_filter(n, 40, 2500)
tt = t(sec)[: len(r)]
r *= np.minimum(tt * 4, 1) * np.exp(-np.maximum(tt - 1.0, 0) * 1.6)
save("rocket", r, 0.7)

# --- Ambient base hum (loop) ---
sec = 8.0
tt = t(sec)
amb = np.sin(2 * np.pi * 60 * tt) * 0.3 + np.sin(2 * np.pi * 120.4 * tt) * 0.15
amb += fft_filter(noise(sec), 100, 900)[: len(tt)] * 0.5
for k in range(3):
    s = int((1.5 + k * 2.6) * SR)
    b = tone(1760 + k * 220, 0.15, 20, (1, 0.1)) * 0.2
    amb[s : s + len(b)] += b
save("ambient_base", loopify(amb, 0.3), 0.35)

# --- Music: slow ambient synth pad progression with gentle arpeggio ---
bpm = 72
beat = 60 / bpm
bars = 16
sec = bars * 4 * beat
tt = t(sec)
music = np.zeros_like(tt)
def midi(m):
    return 440 * 2 ** ((m - 69) / 12)
prog = [[45, 52, 57, 60, 64], [41, 48, 53, 57, 60], [43, 50, 55, 59, 62], [40, 47, 52, 55, 59]]
for bar in range(bars):
    chord = prog[(bar // 2) % 4]
    s = int(bar * 4 * beat * SR)
    length = int(4 * beat * SR * 1.15)
    seg = np.arange(length) / SR
    e = np.minimum(seg / 1.2, 1) * np.exp(-np.maximum(seg - 3.2, 0) * 1.5)
    pad = np.zeros(length)
    for m in chord:
        f = midi(m)
        pad += np.sin(2 * np.pi * f * seg) + 0.6 * np.sin(2 * np.pi * f * 1.003 * seg + 1) + 0.25 * np.sin(2 * np.pi * f * 2 * seg)
    pad *= e * 0.12
    end = min(s + length, len(music))
    music[s:end] += pad[: end - s]
    # arpeggio
    for step in range(8):
        m = chord[[0, 2, 3, 4, 3, 2, 4, 1][step]] + 12
        ns = s + int(step * beat / 2 * SR)
        nt = tone(midi(m), 1.2, 3.0, (1, 0.25, 0.08)) * 0.18
        end = min(ns + len(nt), len(music))
        music[ns:end] += nt[: end - ns]
# soft bass pulse
for b in range(bars * 4):
    chord = prog[(b // 8) % 4]
    ns = int(b * beat * SR)
    nt = tone(midi(chord[0] - 12), beat * 0.9, 4, (1, 0.3)) * 0.35
    end = min(ns + len(nt), len(music))
    music[ns:end] += nt[: end - ns]
# simple echo
d = int(beat * 0.75 * SR)
echo = np.zeros_like(music); echo[d:] = music[:-d] * 0.35
music = lowpass(music + echo, 6000)
save("music_ambient", loopify(music, 1.0), 0.6)
