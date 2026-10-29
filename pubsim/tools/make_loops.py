#!/usr/bin/env python3
"""Makes the ElevenLabs ambience clips loop seamlessly (run once after generation).

The last 1.5 s of each clip is cross-faded (equal power) into its first 1.5 s and the clip is
shortened by that amount, so it can repeat with no click or jump. A marker file records that a
clip has been processed so re-running is harmless."""
import os
import subprocess
import tempfile
import wave

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SFX = os.path.join(HERE, "..", "assets", "sfx_el")
LOOPS = ["pub_quiet_loop", "pub_busy_loop", "rain_window_loop", "fire_loop"]
FADE = 1.5

for name in LOOPS:
    src = os.path.join(SFX, name + ".ogg")
    mark = os.path.join(SFX, name + ".seamless")
    if not os.path.exists(src) or os.path.exists(mark):
        continue
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "a.wav")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-ac", "1", "-ar", "44100", "-c:a", "pcm_s16le", wav], check=True)
        with wave.open(wav) as w:
            rate = w.getframerate()
            a = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float32)
        n = int(FADE * rate)
        t = np.linspace(0.0, 1.0, n, endpoint=False)
        fade_in = np.sin(t * np.pi / 2)
        fade_out = np.cos(t * np.pi / 2)
        head = a[:n] * fade_in + a[-n:] * fade_out
        out = np.concatenate([head, a[n:-n]])
        out = np.clip(out, -32768, 32767).astype(np.int16)
        wav2 = os.path.join(tmp, "b.wav")
        with wave.open(wav2, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes(out.tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav2, "-c:a", "libvorbis", "-q:a", "5", src], check=True)
    open(mark, "w").close()
    print(f"looped {name}: {len(a) / rate:.1f} s -> {len(out) / rate:.1f} s")
