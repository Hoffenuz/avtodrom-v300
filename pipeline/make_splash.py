"""Renders the engine's boot splash (shown before any script runs) so the app
opens on the same picture the loading page then animates, not a blank screen:

  game/assets/ui/boot_splash.png  1920x1080, transparent, drawn over the
  project's boot_splash/bg_color and scaled to the screen height.

The layout repeats LoadingScreen._draw_page (src/autoload/loading_screen.gd)
for unit = screen height: the AvtoSmart mark centred at 34 % of the height,
0.3 units across, "AvtoSmart", "AVTODROM" and the tagline under it. The
project's boot_splash/bg_color is the brand green of that page.

    python pipeline/make_splash.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
UI = ROOT / "game" / "assets" / "ui"
FONT = ROOT / "game" / "assets" / "fonts" / "Inter.ttf"
BRAND_FONT = ROOT / "game" / "assets" / "fonts" / "Montserrat-ExtraBold.ttf"
GREEN = (74, 222, 128, 255)
TAG = (187, 247, 208, 217)
W, H = 1920, 1080
TEXT = (242, 245, 247, 255)
TEXT_DIM = (184, 194, 204, 255)


def font(size, weight, path=FONT):
    f = ImageFont.truetype(str(path), size)
    try:
        f.set_variation_by_axes([weight])
    except (OSError, AttributeError):
        pass
    return f


def centered(draw, text, baseline, f, color):
    w = draw.textlength(text, font=f)
    draw.text((W / 2 - w / 2, baseline), text, font=f, fill=color, anchor="ls")


def main():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    unit = min(H, W * 0.6)
    wd = int(unit * 0.3)
    wc_y = H * 0.34
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for k in range(14):
        r = wd * (0.52 + k * 0.045)
        gd.ellipse((W / 2 - r, wc_y - r, W / 2 + r, wc_y + r), fill=(74, 222, 128, 4))
    img.alpha_composite(glow)
    mark = Image.open(UI / "brand_mark.png").convert("RGBA").resize((wd, wd), Image.LANCZOS)
    img.alpha_composite(mark, (int(W / 2 - wd / 2), int(wc_y - wd / 2)))
    d = ImageDraw.Draw(img)
    centered(d, "AvtoSmart", wc_y + wd * 0.5 + unit * 0.1, font(int(unit * 0.07), 800, BRAND_FONT), TEXT)
    centered(d, "AVTODROM", wc_y + wd * 0.5 + unit * 0.155, font(int(unit * 0.04), 800, BRAND_FONT), GREEN)
    centered(d, "Amaliy imtihon trenajyori", wc_y + wd * 0.5 + unit * 0.205, font(int(unit * 0.03), 500), TAG)
    out = UI / "boot_splash.png"
    img.save(out, optimize=True)
    print("->", out)


if __name__ == "__main__":
    main()
