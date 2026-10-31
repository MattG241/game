#!/usr/bin/env python3
"""Turns the six cube faces from bake_reflections.gd into an equirectangular panorama.

Usage: cube_to_panorama.py <faces_dir> <out.png>
The faces follow Godot's camera convention (looking down -Z, +Y up), as saved by the bake."""
import sys

import numpy as np
from PIL import Image, ImageFilter

src, dst = sys.argv[1], sys.argv[2]
faces = {k: np.asarray(Image.open(f"{src}/face_{k}.png").convert("RGB"), dtype=np.float32) for k in
         ["px", "nx", "py", "ny", "pz", "nz"]}
S = faces["px"].shape[0]
W, H = 1024, 512
u = (np.arange(W) + 0.5) / W
v = (np.arange(H) + 0.5) / H
lon = (u - 0.5) * 2 * np.pi          # Godot panorama: centre column looks down -Z
lat = (0.5 - v) * np.pi
lon, lat = np.meshgrid(lon, lat)
# direction for each pixel (Godot: -Z forward at lon 0, +X to the right at lon +90)
x = np.cos(lat) * np.sin(lon)
y = np.sin(lat)
z = -np.cos(lat) * np.cos(lon)
out = np.zeros((H, W, 3), np.float32)
ax, ay, az = np.abs(x), np.abs(y), np.abs(z)


def sample(face, a, b, mask):
    # a, b in [-1, 1] -> image coords (a to the right, b up)
    px = ((a + 1) * 0.5 * (S - 1)).clip(0, S - 1).astype(int)
    py = ((1 - (b + 1) * 0.5) * (S - 1)).clip(0, S - 1).astype(int)
    out[mask] = faces[face][py[mask], px[mask]]


# camera looking along a face direction with the bake's up vectors; right = forward x up
m = (ax >= ay) & (ax >= az) & (x > 0)
sample("px", z / ax, y / ax, m)          # looking +X: right is +Z
m = (ax >= ay) & (ax >= az) & (x <= 0)
sample("nx", -z / ax, y / ax, m)         # looking -X: right is -Z
m = (az >= ax) & (az >= ay) & (z > 0)
sample("pz", -x / az, y / az, m)         # looking +Z: right is -X
m = (az >= ax) & (az >= ay) & (z <= 0)
sample("nz", x / az, y / az, m)          # looking -Z: right is +X
m = (ay > ax) & (ay > az) & (y > 0)
sample("py", x / ay, z / ay, m)          # looking up (up vector -Z): right +X, image-up -Z
m = (ay > ax) & (ay > az) & (y <= 0)
sample("ny", x / ay, -z / ay, m)         # looking down (up vector +Z): right +X, image-up +Z
img = Image.fromarray(out.clip(0, 255).astype(np.uint8))
# a soft blur: reflections in brass and glass are never razor sharp
img = img.filter(ImageFilter.GaussianBlur(1.2))
img.save(dst)
print("saved", dst, img.size)
