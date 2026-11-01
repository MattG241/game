#!/usr/bin/env python3
"""UI textures in the pub's own materials: dark timber with a brass rim for panels, ivory card
for order tickets. Used as 9-patch StyleBoxTextures (corners stay sharp at any size)."""
import os

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "ui")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(1887)


def noise(h, w, scale):
    small = rng.random((max(2, h // scale), max(2, w // scale)))
    return np.asarray(Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), np.float32) / 255


def streaks(h, w, sy, sx):
    small = rng.random((max(2, h // sy), max(2, w // sx)))
    return np.asarray(Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC), np.float32) / 255


def rounded_mask(h, w, r):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32) + 0.5
    cx = np.clip(x, r, w - r)
    cy = np.clip(y, r, h - r)
    d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
    return np.clip(r - d + 0.5, 0, 1), d, (x, y)


def framed(fill, size=192, radius=22, rim=7, rim_col=(196, 150, 72), alpha=0.95):
    h = w = size
    mask, d, (x, y) = rounded_mask(h, w, radius)
    # distance from the outer edge (approximate, good enough for a bevel)
    edge = np.minimum.reduce([x, y, w - x, h - y])
    edge = np.where(d > 0, np.minimum(edge, radius - d + 0.0), edge)
    img = fill.copy()
    rim_t = np.clip((rim - edge) / rim, 0, 1)[..., None]
    bevel = np.clip(1.0 - np.abs(edge - rim * 0.45) / (rim * 0.55), 0, 1)[..., None]
    brass = np.array(rim_col, np.float32) * (0.75 + 0.45 * bevel)
    img = img * (1 - rim_t) + brass * rim_t
    # thin dark line inside the rim and a soft inner shadow
    inner = np.clip(1 - np.abs(edge - rim - 1.0), 0, 1)[..., None]
    img = img * (1 - inner * 0.6)
    shade = np.clip(1 - (edge - rim) / 14.0, 0, 1)[..., None] * (edge > rim)[..., None]
    img = img * (1 - shade * 0.35)
    a = (mask * alpha * 255)[..., None]
    return Image.fromarray(np.concatenate([img.clip(0, 255), a], axis=2).astype(np.uint8), "RGBA")


def timber(size=192):
    h = w = size
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    warp = streaks(h, w, 12, 96)
    fine = streaks(h, w, 2, 48)
    rings = np.sin(y * 0.55 + warp * 7.0)
    g = (rings * 0.5 + 0.5) * 0.45 + fine * 0.35 + warp * 0.2
    dark = np.array([32, 19, 11], np.float32)
    light = np.array([70, 43, 24], np.float32)
    col = dark + (light - dark) * g[..., None]
    return col


def ivory(size=192):
    n = noise(size, size, 8) * 0.5 + noise(size, size, 2) * 0.5
    base = np.array([242, 232, 206], np.float32)
    return base * (0.94 + 0.08 * n[..., None])


def lacquer_green(size=192):
    y = np.linspace(0, 1, size)[:, None]
    n = noise(size, size, 16)
    base = np.array([18, 70, 40], np.float32)
    col = base * (1.15 - 0.35 * y)[..., None] * (0.95 + 0.1 * n[..., None])
    return np.broadcast_to(col, (size, size, 3)).copy()


framed(timber()).save(os.path.join(OUT, "panel_timber.png"))
framed(ivory(), rim=4, radius=14, rim_col=(176, 128, 58), alpha=0.97).save(os.path.join(OUT, "ticket_ivory.png"))
framed(lacquer_green(), rim=5, radius=18).save(os.path.join(OUT, "button_green.png"))
framed(timber() * 1.25, rim=5, radius=18).save(os.path.join(OUT, "button_timber.png"))
print("ok")
