#!/usr/bin/env python3
"""Draws the original app icon (a creamy-headed stout with the Kilbrack Knot) and splash."""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "icons")
FONT = os.path.join(HERE, "..", "assets", "fonts", "UncialAntiqua-Regular.ttf")
os.makedirs(OUT, exist_ok=True)


def background(size, rounded=True):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    grad = Image.new("RGBA", (size, size))
    gd = ImageDraw.Draw(grad)
    for r in range(size, 0, -2):
        t = r / size
        c = (int(18 + 30 * (1 - t)), int(70 + 60 * (1 - t)), int(40 + 30 * (1 - t)), 255)
        gd.ellipse([size / 2 - r * 0.75, size / 2 - r * 0.75, size / 2 + r * 0.75, size / 2 + r * 0.75], fill=c)
    mask = Image.new("L", (size, size), 0)
    md = ImageDraw.Draw(mask)
    if rounded:
        md.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.22), fill=255)
    else:
        md.rectangle([0, 0, size, size], fill=255)
    img.paste(grad, (0, 0), mask)
    return img


def pint(size, scale=1.0):
    """Tulip pint glass, centred, drawn at 4x then downsampled for smooth edges."""
    S = size * 4
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = S / 2
    h = S * 0.66 * scale
    top = S / 2 - h / 2
    bot = S / 2 + h / 2
    prof = [(0.0, 0.30), (0.12, 0.31), (0.45, 0.35), (0.72, 0.42), (0.88, 0.425), (1.0, 0.40)]
    w = S * 0.5 * scale

    def outline(inset=0.0):
        left, right = [], []
        for t, r in prof:
            y = bot - t * h
            rr = r * w - inset
            left.append((cx - rr, y))
            right.append((cx + rr, y))
        return left + right[::-1]

    # glass rim glow
    d.polygon(outline(-S * 0.012), fill=(235, 230, 215, 120))
    # body
    d.polygon(outline(), fill=(22, 9, 6, 255))
    # head
    head_h = h * 0.15
    head_poly = []
    for t, r in prof:
        if t >= 0.85:
            pass
    d.rectangle([cx - 0.425 * w + 2, bot - h * 1.0, cx + 0.425 * w - 2, bot - h + head_h], fill=(240, 226, 196, 255))
    d.ellipse([cx - 0.40 * w, bot - h - head_h * 0.35, cx + 0.40 * w, bot - h + head_h * 0.35], fill=(248, 238, 214, 255))
    # clip head to the glass silhouette
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).polygon(outline(-S * 0.002), fill=255)
    top_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(top_mask).rectangle([0, 0, S, bot - h + head_h * 0.1], fill=255)
    ImageDraw.Draw(mask).ellipse([cx - 0.40 * w, bot - h - head_h * 0.35, cx + 0.40 * w, bot - h + head_h * 0.35], fill=255)
    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(img, (0, 0), mask)
    img = clipped
    d = ImageDraw.Draw(img)
    # the Kilbrack Knot emblem: ring split by a bar with a diamond
    ey = bot - h * 0.6
    er = w * 0.12
    gold = (240, 200, 110, 255)
    lw = int(S * 0.012)
    d.ellipse([cx - er, ey - er, cx + er, ey + er], outline=gold, width=lw)
    d.line([(cx - er * 1.6, ey), (cx + er * 1.6, ey)], fill=gold, width=int(lw * 0.8))
    dd = er * 0.32
    d.polygon([(cx, ey - dd), (cx + dd, ey), (cx, ey + dd), (cx - dd, ey)], fill=gold)
    return img.resize((size, size), Image.LANCZOS)


def icon(size, rounded=True):
    bg = background(size, rounded)
    p = pint(size)
    shadow = p.split()[3].filter(ImageFilter.GaussianBlur(size * 0.02))
    sh = Image.new("RGBA", (size, size), (0, 0, 0, 140))
    bg.paste(sh, (int(size * 0.015), int(size * 0.025)), shadow)
    bg.alpha_composite(p)
    return bg


icon(512).save(os.path.join(OUT, "icon.png"))
icon(192).save(os.path.join(OUT, "icon_192.png"))
# adaptive icon: foreground glass on transparent (safe zone = inner 66%), background green
fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
fg.alpha_composite(pint(432, 0.62))
fg.save(os.path.join(OUT, "icon_fg_432.png"))
background(432, False).save(os.path.join(OUT, "icon_bg_432.png"))
# splash
W, H = 1280, 720
sp = Image.new("RGBA", (W, H), (18, 12, 9, 255))
logo = icon(300)
sp.alpha_composite(logo, (W // 2 - 150, 120))
try:
    f1 = ImageFont.truetype(FONT, 64)
    f2 = ImageFont.truetype(FONT, 30)
    d = ImageDraw.Draw(sp)
    t = "The Irish Pub Simulator"
    tw = d.textlength(t, font=f1)
    d.text(((W - tw) / 2, 460), t, font=f1, fill=(242, 196, 92))
    t2 = "The Crooked Shamrock"
    tw2 = d.textlength(t2, font=f2)
    d.text(((W - tw2) / 2, 550), t2, font=f2, fill=(230, 220, 195))
except Exception as e:
    print("font error", e)
sp.save(os.path.join(OUT, "splash.png"))
print("icons written")
