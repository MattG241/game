"""Measures the tempo and first beat of every soundtrack song, for the session rhythm game.
  python3 tools/beat_track.py           -> data/beats.json  {"t07": {"bpm": 112.0, "offset": 0.43}, ...}

Decodes each MP3 with ffmpeg, builds an onset-strength envelope (positive spectral flux),
picks the tempo from its autocorrelation (70-190 BPM, favouring the usual 90-140 range) and the
beat phase that lines up best with the onsets. Only numpy is needed.
"""
import json
import os
import subprocess

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
SR = 11025
HOP = 256


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "quiet", "-i", path, "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32)


def onset_env(x):
    n = 1024
    win = np.hanning(n).astype(np.float32)
    frames = 1 + (len(x) - n) // HOP
    idx = np.arange(n)[None, :] + HOP * np.arange(frames)[:, None]
    mag = np.abs(np.fft.rfft(x[idx] * win, axis=1))
    mag = np.log1p(mag * 10.0)
    flux = np.maximum(0.0, np.diff(mag, axis=0)).sum(axis=1)
    flux -= np.convolve(flux, np.ones(16) / 16, mode="same")   # take away the slow swell
    return np.maximum(flux, 0.0)


def tempo(env):
    fps = SR / HOP
    env = env - env.mean()
    ac = np.correlate(env, env, mode="full")[len(env) - 1:]
    best, best_bpm = -1e9, 120.0
    for bpm in np.arange(70.0, 190.0, 0.25):
        lag = fps * 60.0 / bpm
        i = int(round(lag))
        if i + 1 >= len(ac):
            continue
        score = ac[i] + 0.5 * ac[min(len(ac) - 1, int(round(lag * 2)))]
        score *= np.exp(-0.5 * (np.log2(bpm / 115.0) / 0.9) ** 2)    # prefer a walking-pace beat
        if score > best:
            best, best_bpm = score, bpm
    return float(best_bpm)


def phase(env, bpm):
    fps = SR / HOP
    period = fps * 60.0 / bpm
    best, best_off = -1.0, 0.0
    for off in np.arange(0.0, period, 0.5):
        pos = np.arange(off, len(env) - 1, period).astype(int)
        s = env[pos].sum()
        if s > best:
            best, best_off = s, off
    return float(best_off / fps)


def refine(env, bpm):
    """Fine-tunes tempo and phase together over the whole song, so beats don't drift by the end."""
    fps = SR / HOP
    best = (-1.0, bpm, 0.0)
    for b in np.arange(bpm - 0.6, bpm + 0.6, 0.02):
        period = fps * 60.0 / b
        for off in np.arange(0.0, period, 0.5):
            pos = np.arange(off, len(env) - 1, period)
            s = np.interp(pos, np.arange(len(env)), env).sum()
            if s > best[0]:
                best = (s, b, off)
    return float(best[1]), float(best[2] / fps)


def main():
    with open(os.path.join(ROOT, "data", "music.json")) as f:
        tracks = json.load(f)["tracks"]
    out = {}
    for t in tracks:
        path = os.path.join(ROOT, t["file"].replace("res://", ""))
        env = onset_env(decode(path))
        bpm, off = refine(env, tempo(env))
        out[t["id"]] = {"bpm": round(bpm, 3), "offset": round(off, 3)}
        print(t["id"], out[t["id"]])
    with open(os.path.join(ROOT, "data", "beats.json"), "w") as f:
        json.dump(out, f, indent=1)


main()
