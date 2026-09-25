"""
Avtodrom sxemasidan (reference/scheme_landscape.jpg) geometriyani ajratib oladi.

Chiqish: game/data/layout_auto.json — metrlardagi poligonlar:
  * islands  — o't orollari (bordyur tashqi cheti bilan)
  * pads     — beton mashq maydonchalari (ilon izi, 90 gradus, boks, parallel)
  * fence    — maydon chegarasi

Koordinatalar: dunyo X = o'ngga (rasm x), dunyo Z = pastga (rasm y),
markaz — to'siq to'rtburchagining markazi. Masshtab: 12 px = 1 m (yo'l bo'laklari ~3.2–3.7 m,
mashq maydonchalari real o'lchamlarga yaqin).

Ishlatish:  python pipeline/extract_layout.py [--debug]
"""
import json
import sys
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "reference" / "scheme_landscape.jpg"
OUT = ROOT / "game" / "data" / "layout_auto.json"

PX_PER_M = 12.0
# To'siq (oq chegara chizig'i) — rasmdagi piksel koordinatalari.
FENCE_PX = (51.0, 89.0, 2095.0, 1137.0)  # x0, y0, x1, y1
CX = (FENCE_PX[0] + FENCE_PX[2]) / 2.0
CY = (FENCE_PX[1] + FENCE_PX[3]) / 2.0

CURB_PX = 4  # bordyur kengligi rasmda (~0.35 m)


def to_world(pts):
    return [[round((float(x) - CX) / PX_PER_M, 3), round((float(y) - CY) / PX_PER_M, 3)] for x, y in pts]


def remove_icons(img):
    """Sxemadagi yo'l belgisi/svetofor ikonkalarini atrofdagi fon bilan to'ldiradi.

    Ikonkalar orol chetida turadi va o't niqobida "chuqurcha" qoldiradi.
    """
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV).astype(np.int32)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    sign_blue = (h >= 90) & (h <= 135) & (s > 110) & (v > 90)
    sign_red = ((h < 12) | (h > 165)) & (s > 110) & (v > 90)
    lamp_yellow = (h >= 15) & (h <= 32) & (s > 170) & (v > 170)
    icon = (sign_blue | sign_red | lamp_yellow).astype(np.uint8)
    icon = cv2.morphologyEx(icon, cv2.MORPH_OPEN, np.ones((2, 2), np.uint8))
    icon = cv2.dilate(icon, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (15, 15)))
    return cv2.inpaint(img, icon * 255, 7, cv2.INPAINT_TELEA)


def classify(img):
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV).astype(np.int32)
    h, s, v = hsv[..., 0], hsv[..., 1], hsv[..., 2]
    grass = (h >= 25) & (h <= 55) & (s >= 70)
    light = (s < 45) & (v >= 150)
    return grass, light


def inside_fence_mask(shape, inset):
    m = np.zeros(shape[:2], np.uint8)
    x0, y0, x1, y1 = FENCE_PX
    cv2.rectangle(m, (int(x0 + inset), int(y0 + inset)), (int(x1 - inset), int(y1 - inset)), 1, -1)
    return m.astype(bool)


def contours_of(mask, min_area_px, eps_px):
    m = mask.astype(np.uint8) * 255
    cnts, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    polys = []
    for c in cnts:
        if cv2.contourArea(c) < min_area_px:
            continue
        # Chiziq shovqinini kamaytirish uchun konturni silliqlaymiz (davriy o'rtacha).
        pts = c[:, 0, :].astype(np.float64)
        k = 5
        kernel = np.ones(k) / k
        xs = np.convolve(np.concatenate([pts[-k:, 0], pts[:, 0], pts[:k, 0]]), kernel, "same")[k:-k]
        ys = np.convolve(np.concatenate([pts[-k:, 1], pts[:, 1], pts[:k, 1]]), kernel, "same")[k:-k]
        sm = np.stack([xs, ys], 1).astype(np.float32).reshape(-1, 1, 2)
        ap = cv2.approxPolyDP(sm, eps_px, True)[:, 0, :]
        if len(ap) >= 3:
            polys.append(ap)
    return polys


def main(debug=False):
    img = cv2.imread(str(SRC))
    if img is None:
        sys.exit(f"Rasm topilmadi: {SRC}")
    grass, light = classify(remove_icons(img))
    inside = inside_fence_mask(img.shape, 6)
    white = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)[..., 2] >= 205

    # --- O't orollari ---------------------------------------------------------
    g = (grass & inside).astype(np.uint8)
    g = cv2.morphologyEx(g, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
    g = cv2.morphologyEx(g, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5)))
    # Belgilar va soyalar qoldirgan teshiklarni yopamiz.
    cnts, _ = cv2.findContours(g * 255, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    filled = np.zeros_like(g)
    cv2.drawContours(filled, cnts, -1, 1, -1)
    # Bordyur halqasini qo'shamiz (orol = o't + bordyur).
    island_mask = cv2.dilate(filled, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * CURB_PX + 1, 2 * CURB_PX + 1)))
    islands = contours_of(island_mask, 400, 1.2)

    # --- Beton maydonchalar ---------------------------------------------------
    lt = (light & inside).astype(np.uint8)
    lt = cv2.morphologyEx(lt, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_RECT, (7, 7)))
    lt = cv2.morphologyEx(lt, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_RECT, (7, 7)))
    pads = []
    for p in contours_of(lt, 1500, 1.5):
        # Zebra (piyodalar o'tish joyi) chiziqlari ham "och" sinfga tushadi —
        # ichidagi oq bo'yoq ulushi katta bo'lsa, bu maydoncha emas.
        m = np.zeros(lt.shape, np.uint8)
        cv2.fillPoly(m, [p.astype(np.int32)], 1)
        white_ratio = float(white[m.astype(bool)].mean())
        if white_ratio > 0.25:
            continue
        pads.append(p)

    data = {
        "source": "reference/scheme_landscape.jpg",
        "px_per_m": PX_PER_M,
        "fence": to_world([(FENCE_PX[0], FENCE_PX[1]), (FENCE_PX[2], FENCE_PX[1]), (FENCE_PX[2], FENCE_PX[3]), (FENCE_PX[0], FENCE_PX[3])]),
        "islands": [to_world(p) for p in islands],
        "pads": [to_world(p) for p in pads],
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, indent=1), encoding="utf-8")
    print(f"islands={len(islands)} pads={len(pads)} -> {OUT}")
    for i, p in enumerate(islands):
        x, y, w, h = cv2.boundingRect(p.astype(np.int32))
        print(f"  island {i}: {len(p)} pts, bbox px ({x},{y},{w},{h})")
    for i, p in enumerate(pads):
        x, y, w, h = cv2.boundingRect(p.astype(np.int32))
        print(f"  pad {i}: {len(p)} pts, bbox px ({x},{y},{w},{h})")

    if debug:
        vis = img.copy()
        for i, p in enumerate(islands):
            cv2.polylines(vis, [p.astype(np.int32)], True, (0, 0, 255), 2)
            x, y, w, h = cv2.boundingRect(p.astype(np.int32))
            cv2.putText(vis, f"I{i}", (x + 5, y + 20), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 0, 255), 2)
        for i, p in enumerate(pads):
            cv2.polylines(vis, [p.astype(np.int32)], True, (255, 0, 255), 2)
            x, y, w, h = cv2.boundingRect(p.astype(np.int32))
            cv2.putText(vis, f"P{i}", (x + 5, y + 20), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 0, 255), 2)
        dbg = ROOT / "reference" / "debug_layout.png"
        cv2.imwrite(str(dbg), cv2.resize(vis, (1600, 900), interpolation=cv2.INTER_AREA))
        print("debug ->", dbg)


if __name__ == "__main__":
    main("--debug" in sys.argv)
