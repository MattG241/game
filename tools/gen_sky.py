"""Paints the Milky Way and nebulae for the Lunar Cleanup sky (equirectangular).
RGB = glowing clouds (sRGB), A = how dense the star field is there (the sky shader
adds extra stars where A is high). Stars themselves are drawn by the shader.
Usage: python3 tools/gen_sky.py godot/assets/textures
"""
import sys, os
import numpy as np
from PIL import Image

W, H = 2048, 1024
OUT = sys.argv[1] if len(sys.argv) > 1 else "godot/assets/textures"
rng = np.random.default_rng(11)
PERM = rng.permutation(4096)


def lattice(ix, iy, iz):
    h = PERM[(ix * 73856093 ^ iy * 19349663 ^ iz * 83492791) & 4095]
    return h / 4095.0


def vnoise(p):
    """Smooth 3D value noise, p: (..., 3)."""
    f = np.floor(p)
    t = p - f
    t = t * t * (3 - 2 * t)
    i = f.astype(np.int64)
    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (t[..., 0] if dx else 1 - t[..., 0]) * (t[..., 1] if dy else 1 - t[..., 1]) * (t[..., 2] if dz else 1 - t[..., 2])
                out = out + w * lattice(i[..., 0] + dx, i[..., 1] + dy, i[..., 2] + dz)
    return out


def fbm(p, octaves=6, lac=2.03, gain=0.5):
    s, a, norm = 0.0, 1.0, 0.0
    for o in range(octaves):
        s = s + a * vnoise(p + o * 17.31)
        norm += a
        a *= gain
        p = p * lac
    return s / norm


def unit(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


# Direction of every pixel (matches the shader's atan(d.x, d.z) / acos(d.y) lookup)
u = (np.arange(W) + 0.5) / W
v = (np.arange(H) + 0.5) / H
phi = (u - 0.5) * 2 * np.pi
theta = v * np.pi
PH, TH = np.meshgrid(phi, theta)
D = np.stack([np.sin(TH) * np.sin(PH), np.cos(TH), np.sin(TH) * np.cos(PH)], -1)

# --- Milky Way: a band round the sky with a bright core and dark dust lanes
nb = unit([0.3, 0.8, 0.5])                      # band normal (same as the old shader)
gc = unit(np.cross(nb, [0.0, 0.0, 1.0]))        # galactic centre, in the band
dist = D @ nb
warp = fbm(D * 4.0, 5)
width = 0.06 + 0.07 * warp
core = np.exp(-np.sum((D - gc) ** 2, -1) / 0.25)
width = width * (1.0 + 1.6 * core)
edge = fbm(D * 14.0 + 7.0, 5)                    # ragged edges
band = np.exp(-(np.abs(dist) / (width * (0.7 + 0.6 * edge))) ** 1.6)
clouds = fbm(D * 7.0 + 3.0, 7)
ridged = (1.0 - np.abs(2.0 * fbm(D * 16.0 + 5.0, 5) - 1.0)) ** 4
glow = band * (0.08 + 2.2 * np.clip(clouds - 0.25, 0, 1) ** 1.8 + 0.5 * ridged * clouds) * (0.5 + 2.0 * core)
lane = np.clip((fbm(D * 13.0 + 11.0, 6) - 0.45) * 4.0, 0, 1) * np.exp(-(dist / (width * 0.5)) ** 2)
glow = glow * (1.0 - 0.92 * lane)
warm = np.array([1.0, 0.8, 0.58])
cool = np.array([0.5, 0.62, 1.0])
mixk = np.clip(core * 1.6 + (clouds - 0.55), 0, 1)[..., None]
col = glow[..., None] * (cool * (1 - mixk) + warm * mixk) * 0.33

# --- Nebulae: soft coloured clouds
def nebula(centre, colour, size, strength, seed):
    c = unit(centre)
    r2 = np.sum((D - c) ** 2, -1)
    shape = np.exp(-r2 / size)
    n = fbm(D * 9.0 + seed, 7)
    r = (1.0 - np.abs(2.0 * fbm(D * 20.0 + seed, 4) - 1.0)) ** 3
    wisps = np.clip((n - 0.3) * 1.7, 0, 1) ** 1.8 * (0.6 + 0.8 * r)
    return (shape * wisps * strength)[..., None] * np.array(colour)

col += nebula([-0.6, 0.45, 0.35], [1.0, 0.28, 0.55], 0.06, 0.55, 5.0)    # pink emission cloud
col += nebula([-0.55, 0.5, 0.42], [0.25, 0.85, 0.95], 0.025, 0.35, 9.0)  # teal heart inside it
col += nebula([0.7, -0.2, -0.55], [0.55, 0.35, 1.0], 0.08, 0.45, 13.0)   # violet cloud
col += nebula([0.1, 0.35, -0.95], [1.0, 0.55, 0.25], 0.03, 0.35, 21.0)   # small orange one
# A faint zodiacal haze so the sky isn't flat black
col += 0.0015 * np.array([0.35, 0.4, 0.65])[None, None, :] * (0.6 + 0.4 * fbm(D * 2.0 + 40.0, 3))[..., None]

rgb = np.clip(col, 0, 1) ** (1 / 2.2)           # linear -> sRGB
alpha = np.clip(band * (0.4 + 0.8 * clouds) * (1.0 - 0.7 * lane) + core * 0.3, 0, 1)
img = np.concatenate([rgb, alpha[..., None]], -1)
os.makedirs(OUT, exist_ok=True)
Image.fromarray((img * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "sky_milkyway.png"), optimize=True)
print("sky_milkyway.png", W, H)
