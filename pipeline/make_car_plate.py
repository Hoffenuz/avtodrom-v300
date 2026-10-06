"""
Number plate for the cars on the avtodrom (the candidate's car and the
"other participants"): the Uzbek plate layout — region code in its own box on
the left, the flag and "UZ" on the right — carrying the brand name instead of
a registration number.

    python pipeline/make_car_plate.py  ->  game/assets/cars/plate_avtosmart.png

520 x 112 mm plate, drawn at 8 px/mm and saved at 1024 x 224 (power-of-two
width for the VRAM compressor, the height keeps the proportions).
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "assets" / "cars" / "plate_avtosmart.png"
FONT = ROOT / "brand" / "_src" / "Montserrat-800.ttf"
TEXT = "AVTOSMART"
REGION = "01"

S = 8  # px per mm while drawing
W, H = 520 * S, 112 * S
INK = (18, 20, 24, 255)
PAPER = (246, 247, 248, 255)
FLAG_BLUE = (30, 150, 205, 255)
FLAG_GREEN = (30, 160, 70, 255)
FLAG_RED = (206, 17, 38, 255)


def fit_font(text, max_w, max_h):
    size = max_h
    while size > 10:
        f = ImageFont.truetype(str(FONT), size)
        l, t, r, b = f.getbbox(text)
        if r - l <= max_w and b - t <= max_h:
            return f
        size -= 4
    return ImageFont.truetype(str(FONT), size)


def centred(d, box, text, f, fill, squeeze=1.0):
    """Draws `text` centred in `box`, optionally narrowed horizontally."""
    l, t, r, b = f.getbbox(text)
    tw, th = r - l, b - t
    layer = Image.new("RGBA", (tw + 8, th + 8), (0, 0, 0, 0))
    ImageDraw.Draw(layer).text((4 - l, 4 - t), text, font=f, fill=fill)
    if squeeze != 1.0:
        layer = layer.resize((int(layer.width * squeeze), layer.height), Image.LANCZOS)
    x0, y0, x1, y1 = box
    return layer, (int((x0 + x1 - layer.width) / 2), int((y0 + y1 - layer.height) / 2))


def main():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = 6 * S
    d.rounded_rectangle((0, 0, W - 1, H - 1), radius=r, fill=INK)
    d.rounded_rectangle((3 * S, 3 * S, W - 3 * S, H - 3 * S), radius=r - 2 * S, fill=PAPER)
    d.rounded_rectangle((6 * S, 6 * S, W - 6 * S, H - 6 * S), radius=r - 3 * S, outline=INK, width=int(1.6 * S))
    # Region box.
    sep = 104 * S
    d.line((sep, 10 * S, sep, H - 10 * S), fill=INK, width=int(2 * S))
    f_reg = fit_font(REGION, 70 * S, 64 * S)
    layer, pos = centred(d, (6 * S, 6 * S, sep, H - 6 * S), REGION, f_reg, INK)
    img.alpha_composite(layer, pos)
    # Flag and UZ on the right.
    fx0, fx1 = W - 70 * S, W - 18 * S
    fy0 = 22 * S
    band = 9 * S
    for k, c in enumerate([FLAG_BLUE, PAPER, FLAG_GREEN]):
        d.rectangle((fx0, fy0 + k * (band + S), fx1, fy0 + k * (band + S) + band), fill=c)
    d.rectangle((fx0, fy0 + band, fx1, fy0 + band + S), fill=FLAG_RED)
    d.rectangle((fx0, fy0 + 2 * band + S, fx1, fy0 + 2 * band + 2 * S), fill=FLAG_RED)
    d.rectangle((fx0, fy0, fx1, fy0 + 3 * band + 2 * S), outline=INK, width=S // 2)
    f_uz = fit_font("UZ", 40 * S, 22 * S)
    layer, pos = centred(d, (fx0, fy0 + 3 * band + 5 * S, fx1, H - 12 * S), "UZ", f_uz, INK)
    img.alpha_composite(layer, pos)
    # The brand in place of the number: bold, a little condensed.
    area = (sep + 8 * S, 12 * S, fx0 - 10 * S, H - 12 * S)
    f_txt = fit_font(TEXT, int((area[2] - area[0]) / 0.86), area[3] - area[1])
    layer, pos = centred(d, area, TEXT, f_txt, INK, squeeze=0.86)
    img.alpha_composite(layer, pos)
    img = img.resize((1024, 224), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, optimize=True)
    print("->", OUT)


if __name__ == "__main__":
    main()
