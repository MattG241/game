#!/usr/bin/env python3
"""Packs every sound in the game into a few long audio files ("sprites") for Roblox.

Roblox limits audio uploads (10 a month without ID verification, up to 7 minutes each), and the
game has 20 songs, 113 voice lines and 50 effects. They are bin-packed (two songs per file, the
short clips in the space left over) into about ten files under 7 minutes; the game plays each
clip as a region of its file. Writes build/audio/sprite_NN.ogg and build/audio_map.json:

  {"sprites": [{"file", "sha256", "duration"}],
   "clips": {"music/t01": {"sprite": 0, "start": 12.3, "len": 173.6}, "voice/<id>": ..., "sfx/<name>": ...}}

Needs ffmpeg. Deterministic: the same inputs give the same files (and the same sha256, which is
how already-uploaded files are recognised and never uploaded twice).
"""
import hashlib
import json
import os
import subprocess
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GAME = os.path.join(ROOT, "..", "pubsim")
OUT = os.path.join(ROOT, "build", "audio")
RATE = 44100
CAP = 417.0          # seconds per sprite (Roblox allows 420)
GAP = 0.15           # silence between clips


def decode(path):
    """PCM (16-bit stereo 44.1 kHz) bytes for a file."""
    return subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-ac", "2", "-ar", str(RATE), "-"],
                          check=True, capture_output=True).stdout


def clips():
    out = []
    music = json.load(open(os.path.join(GAME, "data", "music.json")))
    for t in music["tracks"]:
        f = os.path.join(GAME, t["file"].replace("res://", ""))
        out.append(("music/" + t["id"], f))
    for d, prefix in (("assets/voice", "voice/"), ("assets/sfx_el", "sfx/"), ("assets/audio", "sfx/")):
        for name in sorted(os.listdir(os.path.join(GAME, d))):
            if name.endswith((".ogg", ".mp3", ".wav")):
                out.append((prefix + os.path.splitext(name)[0], os.path.join(GAME, d, name)))
    return out


def _fit(order):
    """Best-fit: each clip into the fullest file it still fits in."""
    bins = []
    for it in order:
        best = None
        for b in bins:
            if b["used"] + it[2] + GAP <= CAP and (best is None or b["used"] > best["used"]):
                best = b
        if best is None:
            bins.append({"items": [it], "used": it[2] + GAP})
        else:
            best["items"].append(it)
            best["used"] += it[2] + GAP
    return bins


def pack(items):
    """As few files as possible: best-fit decreasing, then a seeded shuffle of the long songs
    (deterministic) to find a tighter arrangement; every upload saved counts against the limit."""
    import random
    items = sorted(items, key=lambda it: (-it[2], it[0]))
    best = _fit(items)
    rng = random.Random(1234)
    big = [it for it in items if it[2] > 60.0]
    small = [it for it in items if it[2] <= 60.0]
    for _ in range(4000):
        order = big[:]
        rng.shuffle(order)
        cand = _fit(order + small)
        if len(cand) < len(best):
            best = cand
    for b in best:
        b["items"].sort(key=lambda it: it[0])
    return best


def main():
    os.makedirs(OUT, exist_ok=True)
    items = []
    seen = set()
    for key, path in clips():
        if key in seen:
            continue        # the same effect in two folders: the first one wins
        seen.add(key)
        pcm = decode(path)
        src_sha = hashlib.sha256(open(path, "rb").read()).hexdigest()
        items.append((key, pcm, len(pcm) / (RATE * 4), src_sha))
    bins = pack(items)
    sprites = []
    amap = {}
    gap = b"\x00" * (int(GAP * RATE) * 4)
    for i, b in enumerate(bins):
        pcm = bytearray()
        for key, data, dur, _h in b["items"]:
            amap[key] = {"sprite": i, "start": round(len(pcm) / (RATE * 4), 4), "len": round(dur, 4)}
            pcm += data + gap
        wav_path = os.path.join(OUT, f"sprite_{i:02d}.wav")
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(bytes(pcm))
        ogg_path = os.path.join(OUT, f"sprite_{i:02d}.ogg")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "5",
                        "-map_metadata", "-1", "-fflags", "+bitexact", ogg_path], check=True)
        os.remove(wav_path)
        # fingerprinted by what's in it (clip names and source files), not the encoded bytes, so
        # an unchanged file is recognised as already uploaded however the encoder behaves
        sha = hashlib.sha256("|".join(f"{k}:{h}:{GAP}" for k, _d, _l, h in b["items"]).encode()).hexdigest()
        sprites.append({"file": os.path.basename(ogg_path), "sha256": sha, "duration": round(len(pcm) / (RATE * 4), 3)})
        print(f"sprite {i:02d}: {len(b['items'])} clips, {len(pcm) / (RATE * 4):.1f} s, {os.path.getsize(ogg_path) // 1024} KB")
    json.dump({"sprites": sprites, "clips": amap}, open(os.path.join(ROOT, "build", "audio_map.json"), "w"), indent=1)
    print(f"{len(sprites)} sprites, {len(amap)} clips")


if __name__ == "__main__":
    main()
