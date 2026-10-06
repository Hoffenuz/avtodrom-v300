"""
Pictures of the Windows installer (scripts/installer.iss), in the brand's
greens with the AvtoSmart mark:

    python pipeline/make_installer_art.py
      -> brand/installer/wizard.bmp        328 x 628 (the wizard's side panel, 2x)
      -> brand/installer/wizard_small.bmp  110 x 110 (the page header, 2x)
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "brand" / "installer"
MARK = ROOT / "game" / "assets" / "ui" / "brand_mark.png"
FONT = ROOT / "game" / "assets" / "fonts" / "Montserrat-ExtraBold.ttf"
TOP, BOTTOM = (20, 83, 45), (5, 46, 27)


def gradient(w, h):
    img = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(h - 1, 1)
        d.line((0, y, w, y), fill=tuple(int(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return img


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    w, h = 328, 628
    img = gradient(w, h)
    mark = Image.open(MARK).convert("RGBA").resize((200, 200), Image.LANCZOS)
    img.paste(mark, ((w - 200) // 2, 150), mark)
    d = ImageDraw.Draw(img)
    for text, size, y, col in (("AvtoSmart", 42, 390, (255, 255, 255)), ("AVTODROM", 26, 442, (74, 222, 128))):
        f = ImageFont.truetype(str(FONT), size)
        tw = d.textlength(text, font=f)
        d.text(((w - tw) / 2, y), text, font=f, fill=col)
    f = ImageFont.truetype(str(FONT), 15)
    t = "avtotestu.uz"
    d.text(((w - d.textlength(t, font=f)) / 2, 590), t, font=f, fill=(187, 247, 208))
    img.save(OUT / "wizard.bmp")
    s = 110
    small = gradient(s, s)
    m = Image.open(MARK).convert("RGBA").resize((92, 92), Image.LANCZOS)
    small.paste(m, (9, 9), m)
    small.save(OUT / "wizard_small.bmp")
    print("->", OUT)


if __name__ == "__main__":
    main()
