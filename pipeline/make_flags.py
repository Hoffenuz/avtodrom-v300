"""
Flags on the poles in front of the exam centre (Surroundings):

    python pipeline/make_flags.py
      -> game/assets/ui/flag_uz.png         the national flag, 2:1
      -> game/assets/ui/flag_avtosmart.png  the brand's green flag with its mark
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "game" / "assets" / "ui"
W, H = 512, 256


def star(d, cx, cy, r, fill):
    pts = []
    for k in range(10):
        a = -math.pi / 2 + k * math.pi / 5
        rr = r if k % 2 == 0 else r * 0.4
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=fill)


def flag_uz():
    s = 4  # supersample
    img = Image.new("RGB", (W * s, H * s), (255, 255, 255))
    d = ImageDraw.Draw(img)
    blue, green, red = (0, 153, 181), (30, 181, 58), (206, 17, 38)
    band = H * s / 3
    red_h = H * s / 50
    d.rectangle((0, 0, W * s, band - red_h), fill=blue)
    d.rectangle((0, band * 2 + red_h, W * s, H * s), fill=green)
    d.rectangle((0, band - red_h, W * s, band), fill=red)
    d.rectangle((0, band * 2, W * s, band * 2 + red_h), fill=red)
    # Crescent and twelve stars (3 + 4 + 5) in the blue band.
    cx, cy, r = 0.105 * W * s, 0.165 * H * s, 0.115 * H * s
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255))
    o = r * 0.28
    d.ellipse((cx - r + o, cy - r - 0.02 * r, cx + r + o, cy + r - 0.02 * r), fill=blue)
    sr = 0.028 * H * s
    for row, n in enumerate([3, 4, 5]):
        for k in range(n):
            # Rows of 3, 4 and 5 stars, aligned on the right.
            x = (0.215 + (k + (5 - n)) * 0.047) * W * s
            y = (0.075 + row * 0.09) * H * s
            star(d, x, y, sr, (255, 255, 255))
    img = img.resize((W, H), Image.LANCZOS)
    img.save(UI / "flag_uz.png", optimize=True)


def flag_brand():
    img = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(img)
    top, bottom = (21, 128, 61), (5, 46, 27)
    for y in range(H):
        t = y / (H - 1)
        d.line((0, y, W, y), fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    mark = Image.open(UI / "brand_mark.png").convert("RGBA").resize((int(H * 0.78),) * 2, Image.LANCZOS)
    img.paste(mark, ((W - mark.width) // 2, (H - mark.height) // 2), mark)
    img.save(UI / "flag_avtosmart.png", optimize=True)


if __name__ == "__main__":
    flag_uz()
    flag_brand()
    print("-> flag_uz.png, flag_avtosmart.png")
