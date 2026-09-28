"""Packs every sign face in game/assets/signs into one texture atlas so all
sign plates on the course render in a single draw call.
Writes signs/atlas.png and signs/atlas.json ({code: [u0, v0, u1, v1]}).
Run from the repo root after adding or changing a sign:
python3 pipeline/make_sign_atlas.py"""
import json
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SIGNS = ROOT / "game" / "assets" / "signs"
CELL = 256
PAD = 8  # edge-clamped gutter, keeps mip levels from bleeding between faces
COLS = 8
INNER = CELL - 2 * PAD


def main():
    codes = sorted(p.stem for p in SIGNS.glob("*.png") if p.stem != "atlas")
    rows = -(-len(codes) // COLS)
    W, H = COLS * CELL, rows * CELL
    atlas = np.zeros((H, W, 4), np.uint8)
    rects = {}
    for i, code in enumerate(codes):
        im = Image.open(SIGNS / f"{code}.png").convert("RGBA")
        k = INNER / max(im.size)
        w, h = max(1, round(im.width * k)), max(1, round(im.height * k))
        a = np.array(im.resize((w, h), Image.LANCZOS))
        a = np.pad(a, ((PAD, PAD), (PAD, PAD), (0, 0)), mode="edge")
        x0 = (i % COLS) * CELL + (INNER - w) // 2
        y0 = (i // COLS) * CELL + (INNER - h) // 2
        atlas[y0:y0 + h + 2 * PAD, x0:x0 + w + 2 * PAD] = a
        u0, v0 = x0 + PAD, y0 + PAD
        rects[code] = [u0 / W, v0 / H, (u0 + w) / W, (v0 + h) / H, w / h]
    Image.fromarray(atlas).save(SIGNS / "atlas.png", optimize=True)
    (SIGNS / "atlas.json").write_text(json.dumps(
        {"size": [W, H], "rects": rects}, indent=0, sort_keys=True) + "\n")
    print(f"{len(codes)} signs -> atlas {W}x{H}")


if __name__ == "__main__":
    main()
