#!/usr/bin/env python3
"""Draws the original GALAGERS Irish Stout brand artwork and writes assets/brand/*.png + data/brand.json.

Everything is drawn here from scratch: an ornate fiddle inside a Celtic interlace ring, the
GALAGERS wordmark set in Cinzel (SIL OFL) with custom gold edging, burgundy rules and a triquetra.
The exact centre of the wordmark's first letter G on the glass print is measured and saved so the
Split the G mini-game can score against it.
"""
import json
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
OUT = os.path.join(ROOT, "assets", "brand")
FONT = os.path.join(ROOT, "assets", "fonts", "Cinzel.ttf")
os.makedirs(OUT, exist_ok=True)

IVORY = (240, 230, 208, 255)
GOLD = (204, 164, 82, 255)
GOLD_LIGHT = (240, 210, 140, 255)
GOLD_DARK = (122, 88, 38, 255)
COPPER = (168, 96, 52, 255)
BURGUNDY = (122, 30, 38, 255)
BLACK = (14, 11, 10, 255)


def font(size, weight=700):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def catmull(points, n=12, closed=True):
    out = []
    pts = points + points[:3] if closed else [points[0]] + points + [points[-1]]
    rng = len(points) if closed else len(points) - 1
    for i in range(rng):
        p0, p1, p2, p3 = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
        for k in range(n):
            t = k / n
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    return out


# ------------------------------------------------------------------ the fiddle emblem
def draw_fiddle(size):
    """An upright fiddle (violin) in gold, drawn at `size` px square on transparency."""
    S = size
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cx = S * 0.5
    # body outline: half-widths along the body (top -> bottom), mirrored
    top, bot = S * 0.42, S * 0.92
    L = bot - top
    half = [(0.0, 0.05), (0.04, 0.2), (0.14, 0.31), (0.26, 0.3), (0.33, 0.24), (0.38, 0.19),
            (0.44, 0.18), (0.52, 0.21), (0.58, 0.29), (0.7, 0.36), (0.84, 0.35), (0.95, 0.26), (1.0, 0.12)]
    right = [(cx + w * L, top + t * L) for t, w in half]
    left = [(cx - w * L, top + t * L) for t, w in reversed(half)]
    outline = catmull(right + left, 10)
    d.polygon(outline, fill=GOLD_DARK)
    inner = [(cx + (x - cx) * 0.93, top + (y - top) * 0.97 + L * 0.015) for x, y in outline]
    d.polygon(inner, fill=GOLD)
    # varnish highlight on the lower bout
    hl = Image.new("L", (S, S), 0)
    ImageDraw.Draw(hl).ellipse([cx - L * 0.22, top + L * 0.6, cx + L * 0.05, top + L * 0.86], fill=120)
    hl = hl.filter(ImageFilter.GaussianBlur(S * 0.02))
    light = Image.new("RGBA", (S, S), GOLD_LIGHT)
    im.paste(light, (0, 0), ImageChops.multiply(hl, Image.new("L", (S, S), 255)))
    d = ImageDraw.Draw(im)
    # purfling: a fine dark line just inside the edge
    purf = [(cx + (x - cx) * 0.86, top + (y - top) * 0.94 + L * 0.03) for x, y in outline]
    d.line(purf + [purf[0]], fill=GOLD_DARK, width=max(1, S // 220))
    # f-holes
    for side in (-1, 1):
        fx = cx + side * L * 0.12
        pts = [(fx + side * L * 0.03, top + L * 0.36), (fx - side * L * 0.01, top + L * 0.45),
               (fx + side * L * 0.01, top + L * 0.55), (fx - side * L * 0.03, top + L * 0.64)]
        d.line(catmull(pts, 8, closed=False), fill=BLACK, width=max(2, S // 110))
        for (px, py) in (pts[0], pts[-1]):
            r = S * 0.008
            d.ellipse([px - r, py - r, px + r, py + r], fill=BLACK)
    # fingerboard, tailpiece, bridge
    fb_w = L * 0.05
    d.polygon([(cx - fb_w, top + L * 0.42), (cx + fb_w, top + L * 0.42), (cx + fb_w * 0.7, S * 0.15), (cx - fb_w * 0.7, S * 0.15)], fill=BLACK)
    d.polygon([(cx - L * 0.055, top + L * 0.72), (cx + L * 0.055, top + L * 0.72), (cx + L * 0.03, top + L * 0.97), (cx - L * 0.03, top + L * 0.97)], fill=BLACK)
    d.rectangle([cx - L * 0.09, top + L * 0.58, cx + L * 0.09, top + L * 0.6], fill=GOLD_LIGHT)
    # strings
    for i in range(4):
        sx = cx + (i - 1.5) * fb_w * 0.42
        d.line([(sx, S * 0.15), (sx, top + L * 0.74)], fill=IVORY, width=max(1, S // 400))
    # neck, pegbox and scroll
    d.polygon([(cx - fb_w * 0.75, S * 0.17), (cx + fb_w * 0.75, S * 0.17), (cx + fb_w * 0.6, S * 0.08), (cx - fb_w * 0.6, S * 0.08)], fill=GOLD_DARK)
    sc = (cx + S * 0.005, S * 0.055)
    spiral = []
    for k in range(80):
        a = k / 80 * math.pi * 3.2
        r = S * 0.042 * (1 - k / 95)
        spiral.append((sc[0] + math.cos(a) * r, sc[1] + math.sin(a) * r))
    d.line(spiral, fill=GOLD, width=max(2, S // 70))
    d.line(spiral, fill=GOLD_DARK, width=max(1, S // 300))
    for side in (-1, 1):
        for j in range(2):
            py = S * (0.1 + j * 0.035)
            d.ellipse([cx + side * fb_w * 1.2 - S * 0.012, py - S * 0.01, cx + side * fb_w * 1.2 + S * 0.012, py + S * 0.01], fill=GOLD_DARK)
    return im


def celtic_ring(size, r_out, r_in, color=GOLD, dark=GOLD_DARK):
    """A ring band filled with a simple over-under interlace."""
    S = size
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = S / 2
    w = max(2, int(S * 0.006))
    d.ellipse([c - r_out, c - r_out, c + r_out, c + r_out], outline=color, width=w * 2)
    d.ellipse([c - r_in, c - r_in, c + r_in, c + r_in], outline=color, width=w * 2)
    mid = (r_out + r_in) / 2
    amp = (r_out - r_in) * 0.33
    n = 18
    # two sinusoidal strands crossing; alternate which one is drawn on top
    for strand in (0, 1):
        pts = []
        for k in range(721):
            a = k / 720 * math.tau
            rr = mid + amp * math.sin(a * n + strand * math.pi)
            pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr))
        d.line(pts, fill=dark, width=w * 3)
        d.line(pts, fill=color, width=w * 2)
    # over-under breaks at alternate crossings
    for k in range(2 * n):
        if k % 2:
            continue
        a = (k + 0.5) / (2 * n) * math.tau
        x, y = c + math.cos(a) * mid, c + math.sin(a) * mid
        r = w * 2.2
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)
    return im


def triquetra(size, color=GOLD):
    S = size
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = S / 2
    R = S * 0.26
    w = max(2, S // 16)
    for k in range(3):
        a = -math.pi / 2 + k * math.tau / 3
        x, y = c + math.cos(a) * R * 0.62, c + math.sin(a) * R * 0.62
        d.ellipse([x - R, y - R, x + R, y + R], outline=color, width=w)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).ellipse([c - R * 1.55, c - R * 1.55, c + R * 1.55, c + R * 1.55], fill=255)
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    out.paste(im, (0, 0), ImageChops.multiply(im.split()[3], mask))
    return out


def emblem(size, ring=True):
    S = size
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    if ring:
        im.alpha_composite(celtic_ring(S, S * 0.46, S * 0.38))
    fid = draw_fiddle(int(S * 0.86))
    fid = fid.rotate(-24, resample=Image.BICUBIC, center=(fid.width / 2, fid.height / 2))
    im.alpha_composite(fid, (int(S * 0.07), int(S * 0.04)))
    return im


def wordmark(width, height, word="GALAGERS", sub="IRISH STOUT", ivory=IVORY, edge=GOLD_DARK, rules=True):
    """Returns (image, g_box) where g_box is the pixel bbox of the first letter."""
    im = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    size = int(height * 0.5)
    f = font(size, 700)
    while d.textlength(word, font=f) > width * 0.94 and size > 10:
        size -= 2
        f = font(size, 700)
    tw = d.textlength(word, font=f)
    x0 = (width - tw) / 2
    y0 = height * 0.08
    # gold edge, then ivory face
    for dx in range(-3, 4):
        for dy in range(-3, 4):
            if dx * dx + dy * dy <= 9:
                d.text((x0 + dx, y0 + dy), word, font=f, fill=edge)
    d.text((x0, y0), word, font=f, fill=ivory)
    g_box = d.textbbox((x0, y0), word[0], font=f)
    word_box = d.textbbox((x0, y0), word, font=f)
    sf = font(int(size * 0.34), 600)
    spaced = "  ".join(sub.split(" "))
    spaced = " ".join(list(spaced))
    sw = d.textlength(spaced, font=sf)
    sy = word_box[3] + height * 0.1
    if rules:
        ry1 = word_box[3] + height * 0.045
        d.line([(width * 0.08, ry1), (width * 0.92, ry1)], fill=BURGUNDY, width=max(2, height // 60))
        ry2 = sy + sf.size * 1.25
        d.line([(width * 0.18, ry2), (width * 0.82, ry2)], fill=BURGUNDY, width=max(2, height // 70))
        for x in (width * 0.08, width * 0.92):
            r = height * 0.018
            d.polygon([(x, ry1 - r), (x + r, ry1), (x, ry1 + r), (x - r, ry1)], fill=GOLD)
    d.text(((width - sw) / 2, sy), spaced, font=sf, fill=GOLD)
    return im, g_box


# ------------------------------------------------------------------ outputs
def glass_print():
    """Print for the pint glass, mapped round the glass. Layout matches data/brand.json."""
    W, H = 1024, 1152
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    em = emblem(520)
    im.alpha_composite(em, ((W - 520) // 2, 0))
    # small flourishes either side of the emblem, as on a printed glass
    d = ImageDraw.Draw(im)
    for side in (-1, 1):
        pts = [(W / 2 + side * 230, 380), (W / 2 + side * 310, 350), (W / 2 + side * 380, 395), (W / 2 + side * 440, 360)]
        d.line(catmull(pts, 10, closed=False), fill=GOLD, width=7)
    wm, g_box = wordmark(W, 420)
    wy = 520
    im.alpha_composite(wm, (0, wy))
    tq = triquetra(110)
    im.alpha_composite(tq, ((W - 110) // 2, wy + 330))
    g_center = ((g_box[0] + g_box[2]) / 2 / W, (g_box[1] + g_box[3]) / 2 / H + wy / H)
    g_top = (g_box[1] + wy) / H
    g_bot = (g_box[3] + wy) / H
    im.save(os.path.join(OUT, "galagers_glass.png"))
    return g_center, g_top, g_bot


def badge(size=512, light_bg=False):
    S = size
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([0, 0, S - 1, S - 1], fill=GOLD_DARK)
    d.ellipse([S * 0.025, S * 0.025, S * 0.975, S * 0.975], fill=GOLD)
    d.ellipse([S * 0.06, S * 0.06, S * 0.94, S * 0.94], fill=IVORY if light_bg else BLACK)
    ring = celtic_ring(S, S * 0.44, S * 0.4, GOLD, GOLD_DARK)
    im.alpha_composite(ring)
    em = emblem(int(S * 0.5), ring=False)
    im.alpha_composite(em, (int(S * 0.25), int(S * 0.1)))
    wm, _ = wordmark(int(S * 0.72), int(S * 0.3), ivory=BLACK if light_bg else IVORY, edge=GOLD)
    im.alpha_composite(wm, (int(S * 0.14), int(S * 0.56)))
    return im


def sign():
    W, H = 1024, 512
    im = Image.new("RGBA", (W, H), BLACK)
    d = ImageDraw.Draw(im)
    d.rectangle([10, 10, W - 11, H - 11], outline=GOLD, width=8)
    d.rectangle([28, 28, W - 29, H - 29], outline=GOLD_DARK, width=3)
    em = emblem(400)
    im.alpha_composite(em, (40, 56))
    wm, _ = wordmark(560, 300)
    im.alpha_composite(wm, (430, 110))
    return im


def poster(variant):
    W, H = 512, 768
    bg = (236, 222, 190, 255) if variant == 0 else (30, 46, 36, 255)
    im = Image.new("RGBA", (W, H), bg)
    d = ImageDraw.Draw(im)
    ink = BLACK if variant == 0 else IVORY
    d.rectangle([14, 14, W - 15, H - 15], outline=BURGUNDY if variant == 0 else GOLD, width=6)
    d.rectangle([26, 26, W - 27, H - 27], outline=GOLD_DARK, width=2)
    if variant == 0:
        # a pint of Galagers, drawn
        gx, gy, gw, gh = W / 2, 150, 150, 330
        body = [(gx - gw * 0.38, gy + gh), (gx + gw * 0.38, gy + gh), (gx + gw * 0.5, gy + gh * 0.25), (gx + gw * 0.47, gy), (gx - gw * 0.47, gy), (gx - gw * 0.5, gy + gh * 0.25)]
        d.polygon(body, fill=(30, 12, 10, 255))
        d.rectangle([gx - gw * 0.47, gy, gx + gw * 0.47, gy + gh * 0.13], fill=IVORY)
        d.ellipse([gx - gw * 0.47, gy - 14, gx + gw * 0.47, gy + 14], fill=(250, 244, 226, 255))
        em = emblem(110, ring=False)
        im.alpha_composite(em, (int(gx - 55), int(gy + gh * 0.32)))
        f = font(46, 700)
        t = "Worth the Wait"
        d.text(((W - d.textlength(t, font=f)) / 2, 520), t, font=f, fill=BURGUNDY)
        wm, _ = wordmark(380, 170, ivory=BLACK, edge=GOLD)
        im.alpha_composite(wm, ((W - 380) // 2, 580))
    else:
        em = emblem(300)
        im.alpha_composite(em, ((W - 300) // 2, 70))
        f = font(40, 700)
        for i, t in enumerate(["A Tune in", "Every Glass"]):
            d.text(((W - d.textlength(t, font=f)) / 2, 400 + i * 52), t, font=f, fill=GOLD_LIGHT)
        wm, _ = wordmark(400, 180)
        im.alpha_composite(wm, ((W - 400) // 2, 540))
    return im


def mirror_lettering():
    W, H = 1024, 384
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    wm, _ = wordmark(760, 300, ivory=GOLD_LIGHT, edge=GOLD_DARK)
    im.alpha_composite(wm, ((W - 760) // 2, 40))
    for side in (-1, 1):
        pts = [(W / 2 + side * 390, 80), (W / 2 + side * 470, 120), (W / 2 + side * 430, 200), (W / 2 + side * 490, 250)]
        d.line(catmull(pts, 10, closed=False), fill=GOLD, width=6)
    return im


def keg_label():
    W, H = 512, 256
    im = Image.new("RGBA", (W, H), BLACK)
    d = ImageDraw.Draw(im)
    d.rectangle([6, 6, W - 7, H - 7], outline=GOLD, width=6)
    em = emblem(200, ring=False)
    im.alpha_composite(em, (16, 28))
    wm, _ = wordmark(300, 170)
    im.alpha_composite(wm, (200, 40))
    return im


def main():
    g_center, g_top, g_bot = glass_print()
    badge().save(os.path.join(OUT, "galagers_badge.png"))
    badge(512, light_bg=True).save(os.path.join(OUT, "galagers_coaster.png"))
    sign().save(os.path.join(OUT, "galagers_sign.png"))
    poster(0).save(os.path.join(OUT, "galagers_poster_pint.png"))
    poster(1).save(os.path.join(OUT, "galagers_poster_tune.png"))
    mirror_lettering().save(os.path.join(OUT, "galagers_mirror.png"))
    keg_label().save(os.path.join(OUT, "galagers_keg.png"))
    emblem(512).save(os.path.join(OUT, "galagers_emblem.png"))
    # The print covers this part of the glass (metres from the glass base, radians round it).
    print_y0, print_y1 = 0.050, 0.140
    half_angle = 0.95
    g_y = print_y1 - g_center[1] * (print_y1 - print_y0)
    brand = {
        "name": "GALAGERS", "subtitle": "IRISH STOUT", "drink": "Galagers Irish Stout",
        "glass_texture": "res://assets/brand/galagers_glass.png",
        "print_y0": print_y0, "print_y1": print_y1, "print_half_angle": half_angle,
        "g_center_uv": [round(g_center[0], 4), round(g_center[1], 4)],
        "g_center_y": round(g_y, 5),
        "g_top_y": round(print_y1 - g_top * (print_y1 - print_y0), 5),
        "g_bottom_y": round(print_y1 - g_bot * (print_y1 - print_y0), 5),
        "g_center_angle": round((g_center[0] * 2.0 - 1.0) * half_angle, 4),
        "note": "Swap the texture and these numbers to rebrand; the Split the G challenge reads g_center_y.",
    }
    with open(os.path.join(ROOT, "data", "brand.json"), "w") as f:
        json.dump(brand, f, indent=1)
    print(json.dumps(brand, indent=1))


if __name__ == "__main__":
    main()
