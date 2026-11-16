"""Extra sound effects added later (so the originals in gen_audio.py stay byte-identical):
gold nugget chime, hologram on/off blip.
Usage: python3 tools/gen_audio_extra.py godot/assets/audio
"""
import sys, os, wave
import numpy as np

SR = 22050
OUT = sys.argv[1] if len(sys.argv) > 1 else "godot/assets/audio"
rng = np.random.default_rng(77)


def save(name, x, peak=0.7):
    x = x / (np.abs(x).max() + 1e-9) * peak
    data = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name, len(data) / SR, "s")


def bell(f, sec, decay):
    tt = np.arange(int(SR * sec)) / SR
    x = np.sin(2 * np.pi * f * tt) + 0.45 * np.sin(2 * np.pi * f * 2.76 * tt) + 0.2 * np.sin(2 * np.pi * f * 5.4 * tt)
    return x * np.exp(-tt * decay) * np.minimum(1, tt / 0.003)


# Gold nugget: a bright rising arpeggio with a shimmering tail
total = int(SR * 1.6)
x = np.zeros(total)
for i, f in enumerate([1318.5, 1661.2, 1975.5, 2637.0, 3322.4]):
    s = int(i * 0.065 * SR)
    b = bell(f, 1.2, 4.5 - i * 0.4)
    x[s:s + len(b)] += b[: total - s] * (0.9 - i * 0.08)
tt = np.arange(total) / SR
shimmer = rng.standard_normal(total) * np.exp(-tt * 3) * 0.08
shimmer = np.convolve(shimmer, np.ones(3) / 3, mode="same") * (0.5 + 0.5 * np.sin(2 * np.pi * 30 * tt))
save("nugget", x + shimmer, 0.65)

# Hologram blip: a quick upward sweep with a digital warble
sec = 0.45
tt = np.arange(int(SR * sec)) / SR
f = 420 + 1500 * (tt / sec) ** 1.5
ph = 2 * np.pi * np.cumsum(f) / SR
x = np.sin(ph) * (0.6 + 0.4 * np.sign(np.sin(2 * np.pi * 38 * tt)))
x += 0.3 * np.sin(ph * 2.01)
x *= np.minimum(1, tt / 0.01) * np.exp(-tt * 5)
save("holo", x, 0.5)
