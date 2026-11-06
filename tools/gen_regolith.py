"""Tileable lunar regolith detail textures for the terrain and rock shaders.
regolith_detail.png: R = brightness variation, G = height, B = cavity (dark in pits and
gaps), A = pebble mask.  regolith_normal.png: tangent-space normal map of the same height.
One tile is meant to cover about 4 m of ground (the shaders also sample it larger).
Usage: python3 tools/gen_regolith.py godot/assets/textures
"""
import sys, os
import numpy as np
from PIL import Image

S = 1024
OUT = sys.argv[1] if len(sys.argv) > 1 else "godot/assets/textures"
rng = np.random.default_rng(42)
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)


def spectral(beta, lo=1.0, hi=None):
    """Tileable noise with a 1/f^beta spectrum (FFT => wraps seamlessly)."""
    f = np.fft.fftfreq(S) * S
    fx, fy = np.meshgrid(f, f)
    r = np.sqrt(fx * fx + fy * fy)
    r[0, 0] = 1.0
    amp = r ** (-beta)
    amp[r < lo] = 0.0
    if hi:
        amp *= np.exp(-(r / hi) ** 2)
    ph = rng.uniform(0, 2 * np.pi, (S, S))
    n = np.real(np.fft.ifft2(amp * np.exp(1j * ph)))
    n -= n.mean()
    return n / (np.abs(n).max() + 1e-9)


def wrap_d(a, b):
    d = np.abs(a - b)
    return np.minimum(d, S - d)


def stamp_all(n, rmin, rmax, fn):
    """Adds n features at random places (wrapping round the tile edges)."""
    out = np.zeros((S, S), np.float32)
    for _ in range(n):
        cx, cy = rng.uniform(0, S, 2)
        r = rng.uniform(rmin, rmax) * (rng.random() ** 1.5 * 0.7 + 0.3)
        x0, x1 = int(cx - r * 2.2), int(cx + r * 2.2) + 1
        y0, y1 = int(cy - r * 2.2), int(cy + r * 2.2) + 1
        xs = np.arange(x0, x1) % S
        ys = np.arange(y0, y1) % S
        X, Y = np.meshgrid(np.arange(x0, x1), np.arange(y0, y1))
        d = np.sqrt((X - cx) ** 2 + (Y - cy) ** 2) / r
        out[np.ix_(ys, xs)] += fn(d, X - cx, Y - cy, r)
    return out


# Rolling ground and grain
mid = spectral(1.6, 2, 160)
grain = spectral(0.4, 60)
fine = spectral(1.0, 20, 400)

# Micro craters: a raised rim, a dish inside
def crater(d, dx, dy, r):
    rim = np.exp(-((d - 1.0) / 0.35) ** 2) * 0.25
    dish = -np.clip(1.0 - d * d, 0, 1) ** 1.5 * 0.7
    return (rim + dish) * (r / 40.0)

craters = stamp_all(28, 6, 70, crater)

# Pebbles: lumpy domes; their mask lets the shader tint them
pebble_mask = np.zeros((S, S), np.float32)
def pebble(d, dx, dy, r):
    ang = np.arctan2(dy, dx)
    lump = 1.0 + 0.25 * np.sin(ang * 3 + r) + 0.15 * np.sin(ang * 5 + 2 * r)
    dd = d / lump
    return np.clip(1.0 - dd * dd, 0, 1) ** 0.6 * (r / 14.0)

pebbles = stamp_all(900, 2.0, 14.0, pebble)
pebble_mask = np.clip(pebbles * 6.0, 0, 1)

height = mid * 0.6 + craters * 0.5 + pebbles * 1.1 + fine * 0.12 + grain * 0.05
height = (height - height.min()) / (height.max() - height.min())

# Cavity: dark where the ground dips below its surroundings (gaps, pits, crater floors)
def blur(a, k):
    f = np.fft.fftfreq(S)
    fx, fy = np.meshgrid(f, f)
    g = np.exp(-(fx * fx + fy * fy) * (k * k) * 2 * np.pi ** 2)
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))

cav = np.clip((blur(height, 6.0) - height) * 9.0 + 0.5, 0, 1)
bright = 0.5 + mid * 0.18 + grain * 0.18 + fine * 0.1
bright += pebble_mask * (0.1 + fine * 0.25)      # pebbles a little lighter, varied
bright -= np.clip(-craters, 0, None) * 0.08
bright = np.clip(bright, 0, 1)

detail = np.stack([bright, height, cav, pebble_mask], -1)
Image.fromarray((detail * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, "regolith_detail.png"), optimize=True)

# Normal map from height (wrapping central differences)
k = 6.0
gx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * 0.5 * k * S / 256.0
gy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * 0.5 * k * S / 256.0
n = np.stack([-gx, gy, np.ones_like(gx)], -1)          # OpenGL-style (green = up)
n /= np.linalg.norm(n, axis=-1, keepdims=True)
nm = n * 0.5 + 0.5
Image.fromarray((nm * 255).astype(np.uint8), "RGB").save(os.path.join(OUT, "regolith_normal.png"), optimize=True)
print("regolith textures", S)
