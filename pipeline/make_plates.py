"""Supplementary plates 7.4.1 (trucks) and 7.4.3 (cars) in the style of the
other 7.x plates: the frame of 7.2.1 with a black side-view pictogram.
The car is the one printed on 7.6.4; the truck is drawn here.
Run from the repo root: python3 pipeline/make_plates.py"""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SIGNS = ROOT / "game" / "assets" / "signs"
INK = (19, 19, 19, 255)


def blank():
    im = Image.open(SIGNS / "7.2.1.png").convert("RGBA")
    ImageDraw.Draw(im).rectangle((9, 9, im.width - 10, im.height - 10), fill=(255, 255, 255, 255))
    return im


def car_mask():
    """The car of 7.6.4 (body and wheels, without the kerb step), as an alpha mask."""
    import cv2
    a = np.array(Image.open(SIGNS / "7.6.4.png").convert("L"))
    m = (a < 110).astype(np.uint8)
    m[:14, :] = 0
    m[:, :14] = 0
    m[:, 200:] = 0
    n, lab, st, _ = cv2.connectedComponentsWithStats(m, 8)
    # The body and the two tyres are the three biggest blobs left of the step.
    blobs = sorted(range(1, n), key=lambda i: -st[i, cv2.CC_STAT_AREA])
    keep = [i for i in blobs if st[i, cv2.CC_STAT_LEFT] + st[i, cv2.CC_STAT_WIDTH] < 175][:3]
    m = np.isin(lab, keep)
    ys, xs = np.nonzero(m)
    return Image.fromarray((m[ys.min():ys.max() + 1, xs.min():xs.max() + 1] * 255).astype(np.uint8))


def paste_centred(im, mask, height):
    k = height / mask.height
    mask = mask.resize((round(mask.width * k), round(height)), Image.LANCZOS)
    ink = Image.new("RGBA", mask.size, INK)
    im.paste(ink, ((im.width - mask.width) // 2, (im.height - mask.height) // 2 + 2), mask)


def truck_mask(w=200, h=80):
    """A lorry in profile, cab on the left: box body, cab with its window, two axles."""
    s = 4
    m = Image.new("L", (w * s, h * s), 0)
    d = ImageDraw.Draw(m)
    S = lambda *v: [c * s for c in v]
    d.rounded_rectangle(S(62, 2, 198, 58), radius=3 * s, fill=255)          # cargo box
    d.polygon(S(4, 58, 4, 30, 16, 12, 56, 12, 56, 58), fill=255)            # cab
    d.polygon(S(14, 30, 22, 18, 46, 18, 46, 30), fill=0)                    # cab window
    d.rectangle(S(4, 56, 198, 64), fill=255)                                # chassis
    for cx in (30, 150, 176):
        d.ellipse(S(cx - 14, 52, cx + 14, 80), fill=255)                   # tyres
        d.ellipse(S(cx - 6, 60, cx + 6, 72), fill=0)                       # hubs
        d.ellipse(S(cx - 3, 63, cx + 3, 69), fill=255)
    return m.resize((w, h), Image.LANCZOS)


TITLES = {
    "7.4.1": ("7.4.1 Transport vositasi turi (yuk avtomobillari)", "7.4.1 Транспорт воситаси тури (юк автомобиллари)",
              "7.4.1 Вид транспортного средства (грузовые автомобили)"),
    "7.4.3": ("7.4.3 Transport vositasi turi (yengil avtomobillar)", "7.4.3 Транспорт воситаси тури (енгил автомобиллар)",
              "7.4.3 Вид транспортного средства (легковые автомобили)"),
}

if __name__ == "__main__":
    meta = json.loads((SIGNS / "signs.json").read_text(encoding="utf-8"))
    for code, mask, height in (("7.4.1", truck_mask(), 78), ("7.4.3", car_mask(), 70)):
        im = blank()
        paste_centred(im, mask, height)
        im.save(SIGNS / f"{code}.png", optimize=True)
        uz, cy, ru = TITLES[code]
        meta[code] = {"file": f"{code}.png", "w": im.width, "h": im.height,
                      "title": {"uz_lat": uz, "uz_cyr": cy, "ru": ru}}
        print("wrote", code, im.size)
    (SIGNS / "signs.json").write_text(json.dumps(meta, ensure_ascii=False, indent=1), encoding="utf-8")
