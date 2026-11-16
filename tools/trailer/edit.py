"""Cuts the recorded gameplay clips into the trailer, timed to the game's ending theme."""
import subprocess, sys

D = "/tmp/claude-0/trailer/hd/"
C = "/tmp/claude-0/trailer/cards/"
MUSIC = "/home/user/game/godot/assets/audio/ending_theme.wav"
OUT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/claude-0/trailer/LunarCleanup_trailer.mp4"

# (clip, clip start s, length s, game-audio volume)
SEGS = [
    ("base",     0.3, 4.4, 0.0),
    ("brush",    0.8, 3.6, 0.6),
    ("third",    0.9, 1.6, 0.5),
    ("nugget",   1.5, 1.6, 0.6),
    ("beam",     1.0, 1.4, 0.5),
    ("gleam",    0.6, 1.4, 0.4),
    ("saucer",   0.9, 5.5, 0.5),
    ("truck",    1.0, 4.0, 0.5),
    ("machines", 0.8, 4.5, 0.4),
    ("hex",      0.7, 4.4, 0.4),
    ("map",      0.6, 2.2, 0.0),
    ("finale",   0.4, 10.6, 0.0),
    ("sky",      0.4, 5.4, 0.0),
]
# (card, start, end) on the trailer timeline
CARDS = [("c1", 5.0, 7.9), ("c2", 8.15, 9.5), ("c3", 9.75, 11.2), ("c4", 14.6, 18.8),
         ("c5", 24.0, 27.8), ("c6", 29.3, 32.6), ("c7", 41.6, 45.2), ("logo", 47.0, 60.0), ("end", 49.5, 60.0)]
TAIL = 5.6      # black under the logo at the end

inputs, fc = [], []
for i, (n, ss, du, vol) in enumerate(SEGS):
    inputs += ["-ss", str(ss), "-t", str(du), "-i", D + n + ".avi"]
    fc.append(f"[{i}:v]scale=1920:1080:flags=lanczos,fps=30,setsar=1,format=yuv420p,setpts=PTS-STARTPTS[v{i}]")
    fc.append(f"[{i}:a]aresample=48000,aformat=channel_layouts=stereo,volume={vol},asetpts=PTS-STARTPTS[a{i}]")
n = len(SEGS)
fc.append("color=c=black:s=1920x1080:r=30:d=%s,format=yuv420p[vt]" % TAIL)
fc.append("anullsrc=r=48000:cl=stereo,atrim=0:%s[at]" % TAIL)
fc.append("".join(f"[v{i}][a{i}]" for i in range(n)) + f"[vt][at]concat=n={n + 1}:v=1:a=1[cv][ca]")
total = sum(s[2] for s in SEGS) + TAIL
# Grade: a touch of contrast, saturation and a vignette; fade from and to black.
fc.append(f"[cv]eq=contrast=1.06:saturation=1.12:gamma=0.98,vignette=PI/5,unsharp=5:5:0.4,fade=in:st=0:d=1.2,fade=out:st={total - 1.5}:d=1.5[g0]")
k = len(SEGS)
last = "g0"
for j, (card, a, b) in enumerate(CARDS):
    idx = k + j
    inputs += ["-loop", "1", "-t", str(b - a), "-framerate", "30", "-i", C + card + ".png"]
    fc.append(f"[{idx}:v]format=rgba,fade=in:st=0:d=0.35:alpha=1,fade=out:st={b - a - 0.35}:d=0.35:alpha=1,setpts=PTS+{a}/TB[c{j}]")
    fc.append(f"[{last}][c{j}]overlay=0:0:eof_action=pass[g{j + 1}]")
    last = f"g{j + 1}"
mi = k + len(CARDS)
inputs += ["-i", MUSIC]
fc.append(f"[{mi}:a]aresample=48000,aformat=channel_layouts=stereo,atrim=0:{total},afade=t=out:st={total - 4}:d=4,volume=1.0[mus]")
fc.append("[ca]volume=0.55[sfx]")
fc.append("[mus][sfx]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.95[aout]")
cmd = ["ffmpeg", "-y", "-loglevel", "error"] + inputs + ["-filter_complex", ";".join(fc),
       "-map", f"[{last}]", "-map", "[aout]", "-c:v", "libx264", "-preset", "slow", "-crf", "18",
       "-profile:v", "high", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
       "-c:a", "aac", "-b:a", "192k", "-t", str(total), OUT]
print("total", total)
r = subprocess.run(cmd)
sys.exit(r.returncode)
