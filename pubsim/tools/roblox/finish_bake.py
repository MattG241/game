"""Finish a baked texture: grow each painted island outwards (so filtering and mipmaps never pull
in the empty background at the seams), then downsample the supersampled bake.

finish_bake.py in.png out.png size
"""
import sys
import numpy as np
from PIL import Image

src, dst, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
# the viewport image is upside down relative to the bake layout
im = np.asarray(Image.open(src).convert("RGBA").transpose(Image.FLIP_TOP_BOTTOM)).astype(np.float32)
rgb, a = im[..., :3], im[..., 3] > 8
if not a.any():
    Image.new("RGB", (size, size), (128, 128, 128)).save(dst)
    sys.exit(0)
filled = a.copy()
col = np.where(a[..., None], rgb, 0.0)
for _ in range(24):  # dilate: each empty pixel takes the mean of its painted neighbours
    if filled.all():
        break
    acc = np.zeros_like(col)
    cnt = np.zeros(a.shape, np.float32)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)):
        sh_c = np.roll(np.roll(col, dy, 0), dx, 1)
        sh_f = np.roll(np.roll(filled, dy, 0), dx, 1)
        acc += sh_c * sh_f[..., None]
        cnt += sh_f
    grow = (~filled) & (cnt > 0)
    col[grow] = acc[grow] / cnt[grow][:, None]
    filled |= grow
col[~filled] = rgb[a].mean(axis=0)
out = Image.fromarray(np.clip(col, 0, 255).astype(np.uint8), "RGB").resize((size, size), Image.LANCZOS)
out.save(dst, optimize=True)
