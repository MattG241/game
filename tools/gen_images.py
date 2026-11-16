"""Generates the launcher icon and splash screen (original artwork, drawn procedurally)."""
import sys, math, random
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "godot"
random.seed(7)

def moon_scene(size, with_text=False, font_path=None):
    W, H = size
    img = Image.new("RGB", (W, H), (4, 5, 11))
    d = ImageDraw.Draw(img)
    for _ in range(int(W * H / 900)):
        x, y = random.random() * W, random.random() * H
        b = random.randint(120, 255)
        r = random.choice([0.6, 0.8, 1.0, 1.4])
        d.ellipse([x - r, y - r, x + r, y + r], fill=(b, b, min(255, b + 15)))
    return img, d

def icon(px):
    img, d = moon_scene((px, px))
    s = px / 512
    # Earth
    ex, ey, er = 360 * s, 120 * s, 70 * s
    d.ellipse([ex - er, ey - er, ex + er, ey + er], fill=(40, 110, 220))
    d.pieslice([ex - er, ey - er, ex + er, ey + er], 200, 330, fill=(60, 160, 90))
    d.ellipse([ex - er * 0.5, ey - er * 0.2, ex + er * 0.2, ey + er * 0.5], fill=(240, 245, 255))
    d.chord([ex - er, ey - er, ex + er, ey + er], 100, 260, fill=(10, 20, 45))
    # Moon surface
    d.ellipse([-200 * s, 300 * s, 712 * s, 1100 * s], fill=(176, 172, 164))
    for cx, cy, cr in [(120, 400, 50), (330, 380, 30), (420, 470, 40), (220, 470, 22)]:
        d.ellipse([(cx - cr) * s, (cy - cr * 0.45) * s, (cx + cr) * s, (cy + cr * 0.45) * s], fill=(120, 118, 114))
    # Clean trail (dark polished strip)
    d.polygon([(40 * s, 512 * s), (170 * s, 512 * s), (300 * s, 330 * s), (255 * s, 330 * s)], fill=(40, 42, 48))
    # Giant toothbrush
    d.line([(150 * s, 470 * s), (330 * s, 210 * s)], fill=(79, 195, 247), width=int(34 * s))
    d.line([(170 * s, 440 * s), (215 * s, 375 * s)], fill=(250, 250, 250), width=int(36 * s))
    d.rounded_rectangle([300 * s, 130 * s, 380 * s, 230 * s], radius=int(14 * s), fill=(79, 195, 247))
    for i in range(5):
        x = 300 * s + i * 16 * s
        d.rectangle([x + 2 * s, 230 * s, x + 12 * s, 262 * s], fill=(255, 255, 255))
    # Sparkle
    for (x, y, r) in [(110, 330, 16), (420, 300, 10)]:
        x, y, r = x * s, y * s, r * s
        d.polygon([(x, y - r * 2), (x + r * 0.4, y), (x, y + r * 2), (x - r * 0.4, y)], fill=(255, 220, 120))
        d.polygon([(x - r * 2, y), (x, y + r * 0.4), (x + r * 2, y), (x, y - r * 0.4)], fill=(255, 220, 120))
    return img

icon(512).resize((192, 192), Image.LANCZOS).save(f"{OUT}/icon.png")
if len(sys.argv) > 2:
    # Optional: 512x512 store icon (Google Play) and 1024x1024 (App Store, no alpha).
    icon(1024).resize((512, 512), Image.LANCZOS).save(f"{sys.argv[2]}/icon_512.png")
    icon(1024).convert("RGB").save(f"{sys.argv[2]}/icon_1024.png")
fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
ic = icon(512).resize((300, 300), Image.LANCZOS).convert("RGBA")
mask = Image.new("L", (300, 300), 0)
ImageDraw.Draw(mask).ellipse([0, 0, 300, 300], fill=255)
fg.paste(ic, (66, 66), mask)
fg.save(f"{OUT}/assets/textures/icon_fg.png")
Image.new("RGB", (432, 432), (4, 5, 11)).save(f"{OUT}/assets/textures/icon_bg.png")

# Splash
W, H = 1280, 720
img, d = moon_scene((W, H))
d.ellipse([-300, 520, W + 300, 1500], fill=(150, 147, 140))
try:
    font = ImageFont.truetype(f"{OUT}/assets/fonts/Rajdhani-Bold.ttf", 120)
    small = ImageFont.truetype(f"{OUT}/assets/fonts/Rajdhani-Bold.ttf", 36)
except Exception:
    font = small = None
t = "LUNAR CLEANUP"
tw = d.textlength(t, font=font)
d.text(((W - tw) / 2, 230), t, font=font, fill=(255, 158, 28))
t2 = "One toothbrush. One Moon."
tw = d.textlength(t2, font=small)
d.text(((W - tw) / 2, 370), t2, font=small, fill=(200, 215, 235))
img.save(f"{OUT}/assets/textures/splash.png")
print("images ok")
