"""Builds app-store marketing images from raw in-game screenshots.

Raw captures come from godot/tests/store_shots.tscn (see store/README.md).
Usage: python3 tools/make_store_art.py
"""
import os, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STORE = os.path.join(ROOT, "store")
FONT = os.path.join(ROOT, "godot/assets/fonts/Rajdhani-Bold.ttf")
BODY = os.path.join(ROOT, "godot/assets/fonts/Exo2.ttf")
ACCENT = (255, 158, 28)
TEXT = (236, 242, 250)
MUTED = (170, 186, 210)

CAPTIONS = {
    "01_title": ("CLEAN THE MOON.", "One toothbrush at a time."),
    "02_toothbrush": ("EVERY SCRUB COUNTS", "Real, persistent dust you can watch disappear"),
    "03_vacuum": ("UPGRADE YOUR GEAR", "12 tools: brushes, vacuums, scrubbers and beams"),
    "04_buggy": ("HIT THE ROAD", "Cleaning vehicles built for low gravity"),
    "05_automation": ("AUTOMATE EVERYTHING", "Collectors, drones, conveyors and rocket depots"),
    "06_beam": ("EXPLORE 5 REGIONS", "Each one dustier - and more valuable - than the last"),
    "07_shop": ("NO ADS. NO PAYWALLS.", "Every upgrade is earned in-game. Plays fully offline."),
}


def space_bg(w, h, seed=3):
    rnd = random.Random(seed)
    bg = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(bg)
    for y in range(h):
        t = y / h
        d.line([(0, y), (w, y)], fill=(int(6 + 10 * t), int(8 + 12 * t), int(18 + 26 * t)))
    for _ in range(w * h // 2500):
        x, y = rnd.random() * w, rnd.random() * h
        b = rnd.randint(90, 230)
        r = rnd.choice([0.6, 0.9, 1.3]) * w / 1920
        d.ellipse([x - r, y - r, x + r, y + r], fill=(b, b, min(255, b + 20)))
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse([w * 0.15, h * 0.55, w * 0.85, h * 1.6], fill=(40, 60, 110))
    return Image.blend(bg, glow.filter(ImageFilter.GaussianBlur(w // 12)), 0.35)


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.size[0] - 1, img.size[1] - 1], radius=radius, fill=255)
    out = Image.new("RGBA", img.size)
    out.paste(img, (0, 0), mask)
    return out


def compose(raw_path, out_path, size, caption):
    W, H = size
    k = W / 1920
    canvas = space_bg(W, H).convert("RGBA")
    head_font = ImageFont.truetype(FONT, int(96 * k))
    sub_font = ImageFont.truetype(BODY, int(40 * k))
    try:
        sub_font.set_variation_by_axes([600])
    except Exception:
        pass
    d = ImageDraw.Draw(canvas)
    head, sub = caption
    top = int(28 * k)
    hw = d.textlength(head, font=head_font)
    d.text(((W - hw) / 2, top), head, font=head_font, fill=ACCENT)
    sw = d.textlength(sub, font=sub_font)
    d.text(((W - sw) / 2, top + int(104 * k)), sub, font=sub_font, fill=TEXT)
    cap_h = top + int(170 * k)
    shot = Image.open(raw_path).convert("RGB")
    avail_h = H - cap_h - int(36 * k)
    avail_w = W - int(110 * k)
    s = min(avail_h / shot.height, avail_w / shot.width)
    shot = shot.resize((int(shot.width * s), int(shot.height * s)), Image.LANCZOS)
    x = (W - shot.width) // 2
    y = cap_h + (avail_h - shot.height) // 2
    r = int(30 * k)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x - 6, y + 10, x + shot.width + 6, y + shot.height + 22], radius=r, fill=(0, 0, 0, 170))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(int(18 * k))))
    border = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle([x - 4, y - 4, x + shot.width + 3, y + shot.height + 3], radius=r + 4, fill=(255, 158, 28, 210))
    canvas = Image.alpha_composite(canvas, border)
    canvas.alpha_composite(rounded(shot, r), (x, y))
    canvas.convert("RGB").save(out_path, optimize=True)


def feature_graphic(raw_path, out_path):
    W, H = 1024, 500
    shot = Image.open(raw_path).convert("RGB")
    s = max(W / shot.width, H / shot.height)
    shot = shot.resize((int(shot.width * s) + 1, int(shot.height * s) + 1), Image.LANCZOS)
    left = (shot.width - W) // 2
    img = shot.crop((left, (shot.height - H) // 2, left + W, (shot.height - H) // 2 + H)).convert("RGBA")
    shade = Image.new("RGBA", (W, H))
    sd = ImageDraw.Draw(shade)
    for x in range(W):
        a = int(235 * max(0.0, 1.0 - x / (W * 0.62)))
        sd.line([(x, 0), (x, H)], fill=(4, 6, 14, a))
    img = Image.alpha_composite(img, shade)
    d = ImageDraw.Draw(img)
    f1 = ImageFont.truetype(FONT, 104)
    f2 = ImageFont.truetype(BODY, 30)
    d.text((48, 120), "LUNAR", font=f1, fill=ACCENT)
    d.text((48, 210), "CLEANUP", font=f1, fill=TEXT)
    d.text((52, 330), "One toothbrush. One Moon.", font=f2, fill=MUTED)
    d.text((52, 372), "No ads - no purchases - offline", font=f2, fill=MUTED)
    img.convert("RGB").save(out_path, optimize=True)


def main():
    sets = [
        ("raw/play_1920x1080", "google_play/phone_1920x1080", (1920, 1080)),
        ("raw/apple_6.9in_2868x1320", "apple/iphone_6.9in_2868x1320", (2868, 1320)),
    ]
    for raw_dir, out_dir, size in sets:
        src = os.path.join(STORE, raw_dir)
        dst = os.path.join(STORE, out_dir)
        os.makedirs(dst, exist_ok=True)
        for name, cap in CAPTIONS.items():
            p = os.path.join(src, name + ".png")
            if os.path.exists(p):
                compose(p, os.path.join(dst, name + ".png"), size, cap)
                print("made", out_dir, name)
    fg = os.path.join(STORE, "raw/feature_clean.png")
    if os.path.exists(fg):
        feature_graphic(fg, os.path.join(STORE, "google_play/feature_graphic_1024x500.png"))
        print("made feature graphic")


if __name__ == "__main__":
    main()
