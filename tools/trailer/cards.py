from PIL import Image, ImageDraw, ImageFont, ImageFilter
W, H = 1920, 1080
F = "/home/user/game/godot/assets/fonts/"
big = ImageFont.truetype(F + "Rajdhani-Bold.ttf", 120)
mid = ImageFont.truetype(F + "Rajdhani-Bold.ttf", 64)
small = ImageFont.truetype(F + "Exo2.ttf", 40)
ORANGE = (255, 158, 28, 255)
WHITE = (255, 255, 255, 255)

def shadowed(img, draw_fn):
    sh = Image.new("RGBA", img.size, (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(sh), (0, 0, 0, 200))
    sh = sh.filter(ImageFilter.GaussianBlur(10))
    img.alpha_composite(sh)
    draw_fn(ImageDraw.Draw(img), None)

def caption(name, line1, line2=None):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    x, y = 120, H - 300
    def draw(d, col):
        d.rectangle([x, y + 18, x + 12, y + 118 + (70 if line2 else 0)], fill=col or ORANGE)
        d.text((x + 40, y), line1, font=big, fill=col or WHITE)
        if line2:
            d.text((x + 44, y + 128), line2, font=mid, fill=col or ORANGE)
    shadowed(img, draw)
    img.save(f"/tmp/claude-0/trailer/cards/{name}.png")

caption("c1", "ONE TOOTHBRUSH.")
caption("c2", "ONE MOON.")
caption("c3", "ZERO BUDGET.")
caption("c4", "UPGRADE EVERYTHING", "Scrubbers. Vacuums. Trucks. A flying saucer.")
caption("c5", "BUILD A CLEANING EMPIRE", "Stations, drones and collectors that never sleep")
caption("c6", "362 HEXAGONS", "Not one speck left behind")
caption("c7", "THEN FLY HOME", "A hero")

# Logo card (transparent, centred) and end line
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
logo = ImageFont.truetype(F + "Rajdhani-Bold.ttf", 230)
def draw_logo(d, col):
    tw1 = d.textlength("LUNAR ", font=logo); tw2 = d.textlength("CLEANUP", font=logo)
    x0 = (W - tw1 - tw2) / 2; y0 = 330
    d.text((x0, y0), "LUNAR ", font=logo, fill=col or ORANGE)
    d.text((x0 + tw1, y0), "CLEANUP", font=logo, fill=col or WHITE)
    t = "One toothbrush. One Moon. Zero budget."
    d.text(((W - d.textlength(t, font=small)) / 2, y0 + 270), t, font=small, fill=col or (225, 230, 240, 255))
shadowed(img, draw_logo)
img.save("/tmp/claude-0/trailer/cards/logo.png")
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
def draw_end(d, col):
    t = "FREE ON ANDROID   ·   PLAYS OFFLINE   ·   NO PAY-TO-WIN"
    d.text(((W - d.textlength(t, font=mid)) / 2, 820), t, font=mid, fill=col or ORANGE)
shadowed(img, draw_end)
img.save("/tmp/claude-0/trailer/cards/end.png")
print("ok")
