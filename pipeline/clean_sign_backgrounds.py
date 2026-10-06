"""
Makes the white background around a sign face transparent: the near-white
pixels connected to the image border (outside the sign's red rim), plus the
light anti-aliasing fringe next to them, which would show as a white halo.
The white field inside the rim is not connected to the border and stays.

    python pipeline/clean_sign_backgrounds.py 1.13 1.14 1.1
    python pipeline/make_sign_atlas.py
"""
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image

SIGNS = Path(__file__).resolve().parent.parent / "game" / "assets" / "signs"
WHITE = 215  # every channel above this counts as background white
FRINGE = 175  # light edge pixels next to the cleared area


def clean(code: str) -> None:
    path = SIGNS / f"{code}.png"
    a = np.array(Image.open(path).convert("RGBA"))
    h, w = a.shape[:2]
    light = (a[..., :3].min(axis=2) > WHITE) | (a[..., 3] < 40)
    bg = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        q.extend([(0, x), (h - 1, x)])
    for y in range(h):
        q.extend([(y, 0), (y, w - 1)])
    while q:
        y, x = q.popleft()
        if not (0 <= y < h and 0 <= x < w) or bg[y, x] or not light[y, x]:
            continue
        bg[y, x] = True
        q.extend([(y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)])
    # The fringe: light pixels touching the background.
    near = np.zeros_like(bg)
    near[1:, :] |= bg[:-1, :]
    near[:-1, :] |= bg[1:, :]
    near[:, 1:] |= bg[:, :-1]
    near[:, :-1] |= bg[:, 1:]
    fringe = near & ~bg & (a[..., :3].min(axis=2) > FRINGE)
    a[bg, 3] = 0
    a[bg, :3] = 0
    # Fringe pixels keep their colour with the white share taken out as alpha.
    m = a[fringe, :3].min(axis=1).astype(np.float32)
    alpha = np.clip((255.0 - m) / (255.0 - FRINGE), 0.0, 1.0)
    a[fringe, 3] = (alpha * 255).astype(np.uint8)
    Image.fromarray(a).save(path, optimize=True)
    print(f"{code}: {int(bg.sum())} background px cleared, {int(fringe.sum())} fringe px softened")


if __name__ == "__main__":
    for c in sys.argv[1:]:
        clean(c)
