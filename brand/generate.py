#!/usr/bin/env python3
"""AvtoDrom logo paketini yaratadi (SVG + PNG + Android/Play Store + Windows).

AvtoSmart belgisining o'zi (rul + asfalt yo'l shaklidagi S) — faqat palitra
yashil: ko'k → yashil, akvamarin → laym. Belgi yo'llari _src/avtosmart-icon*.svg
dan olinadi.

    python brand/generate.py

Kerak: fontTools, resvg-py, Pillow. Shrift: _src/Montserrat-600/800.ttf
(Google Fonts Montserrat[wght] dan instance qilingan, OFL).
"""
import re
import shutil
from pathlib import Path

import resvg_py
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont
from PIL import Image

ROOT = Path(__file__).resolve().parent
SRC = ROOT / "_src"
AVTOSMART_ICON = SRC / "avtosmart-icon.svg"

# ── Palitra ──────────────────────────────────────────────────────────────
INK = "#131A45"          # AvtoSmart bilan umumiy: "Avto", monoxrom
GREEN_700 = "#15803D"    # "Drom"
GREEN_500 = "#22C55E"    # disk gradienti boshi
FOREST = "#0B3B2A"       # disk gradienti oxiri
LIME = "#A3E635"         # urg'u — tezlik yoyi
SLATE = "#7C87AE"        # tagline (AvtoSmart bilan umumiy)
ASPHALT = ("#262C43", "#141928")
APP_BG = ("#14532D", "#052E1B")
DARK_DROM = "#4ADE80"
DARK_TAG = "#BBF7D0"

TAGLINE = "IMTIHON SIMULYATORI"

# ── Belgi geometriyasi: AvtoSmart belgisining o'zi (200×200, markaz 100,100, disk r=94) ──
C, DISK_R = 100.0, 94.0


def _paths(name):
    return re.findall(r' d="([^"]+)"', (SRC / name).read_text(encoding="utf-8"))


_COLOR, _WHITE = _paths("avtosmart-icon.svg"), _paths("avtosmart-icon-white.svg")
D = {
    "disk": _COLOR[0],      # disk (halqa va S konturi — teshik)
    "road": _COLOR[1],      # asfalt S
    "marks": _COLOR[2],     # uzuq oq chiziq
    "arc": _COLOR[3],       # tezlik yoyi
    "disk_cut": _WHITE[0],  # oq/mono: disk
    "road_cut": _WHITE[1],  # oq/mono: yo'l (chiziqlar teshik)
}


# ── Belgi variantlari (xom geometriya 0..200, disk r=94) ────────────────
def grad(gid, c0, c1, x1, y1, x2, y2):
    return (f'<linearGradient id="{gid}" gradientUnits="userSpaceOnUse" x1="{x1}" y1="{y1}" '
            f'x2="{x2}" y2="{y2}"><stop offset="0" stop-color="{c0}"/>'
            f'<stop offset="1" stop-color="{c1}"/></linearGradient>')


def mark(kind, p):
    """(defs, body). kind: color | simple | white | mono. p — id prefiksi."""
    if kind in ("color", "simple"):
        defs = (grad(p + "g", GREEN_500, FOREST, 22, 14, 178, 186)
                + grad(p + "a", *ASPHALT, 58, 38, 148, 168))
        body = (f'<path fill="url(#{p}g)" fill-rule="evenodd" d="{D["disk"]}"/>'
                f'<path fill="url(#{p}a)" fill-rule="evenodd" d="{D["road"]}"/>')
        if kind == "color":
            body += f'<path fill="#FFFFFF" d="{D["marks"]}"/>'
        body += f'<path fill="{LIME}" d="{D["arc"]}"/>'
        return defs, body
    col = "#FFFFFF" if kind == "white" else INK
    return "", (f'<path fill="{col}" fill-rule="evenodd" d="{D["disk_cut"]}"/>'
                f'<path fill="{col}" fill-rule="evenodd" d="{D["road_cut"]}"/>')


def svg(w, h, inner, defs="", px=None, label="AvtoDrom"):
    pw, ph = px or (w, h)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w:.2f} {h:.2f}" '
            f'width="{pw:.0f}" height="{ph:.0f}" role="img" aria-label="{label}">'
            f'<defs>{defs}</defs>{inner}</svg>')


def icon_svg(kind, p="i"):
    defs, body = mark(kind, p)
    s = 200 / (2 * DISK_R)
    return svg(200, 200, f'<g transform="translate({-(C - DISK_R) * s:.4f} {-(C - DISK_R) * s:.4f}) '
               f'scale({s:.6f})">{body}</g>', defs, (512, 512))


def app_icon_svg(p="ap", rounded=False, circle=False):
    """Kvadrat ilova ikonkasi: yashil fon + oq doira + belgi (AvtoSmart app-icon kabi)."""
    defs, body = mark("color", p)
    defs += grad(p + "bg", *APP_BG, 0, 0, 200, 200)
    s = 0.723404
    clip = ""
    if rounded or circle:
        shape = ('<circle cx="100" cy="100" r="100"/>' if circle
                 else '<rect width="200" height="200" rx="36"/>')
        defs += f'<clipPath id="{p}clip">{shape}</clipPath>'
        clip = f' clip-path="url(#{p}clip)"'
    inner = (f'<g{clip}><rect width="200" height="200" fill="url(#{p}bg)"/>'
             f'<circle cx="100" cy="100" r="67.456" fill="#FFFFFF"/>'
             f'<g transform="translate({100 - C * s:.4f} {100 - C * s:.4f}) scale({s})">{body}</g></g>')
    return svg(200, 200, inner, defs, (1024, 1024))


# ── Matn (konturga aylantirilgan Montserrat) ────────────────────────────
class Font:
    def __init__(self, path):
        f = TTFont(path)
        self.gs, self.cmap, self.hmtx = f.getGlyphSet(), f.getBestCmap(), f["hmtx"]
        self.upm = f["head"].unitsPerEm

    def run(self, text, size, tracking=0.0):
        """(path'lar, kenglik). tracking — em ulushida."""
        sc, x, parts = size / self.upm, 0.0, []
        for ch in text:
            name = self.cmap[ord(ch)]
            pen = SVGPathPen(self.gs)
            self.gs[name].draw(pen)
            d = pen.getCommands()
            if d:
                parts.append(f'<path transform="translate({x:.3f} 0) scale({sc:.6f} {-sc:.6f})" d="{d}"/>')
            x += self.hmtx[name][0] * sc + tracking * size
        return "".join(parts), x - tracking * size * (1 if text else 0)


SEMI, EXTRA = Font(SRC / "Montserrat-600.ttf"), Font(SRC / "Montserrat-800.ttf")
TAG_TRACK = 0.4375


def wordmark(size, c_avto, c_drom):
    a, wa = SEMI.run("Avto", size)
    d, wd = EXTRA.run("Drom", size)
    return (f'<g fill="{c_avto}">{a}</g><g fill="{c_drom}" transform="translate({wa:.3f} 0)">{d}</g>',
            wa + wd)


def logo_horizontal(scheme, tag=True, p="h"):
    kind, ca, cd, ct = {
        "color": ("color", INK, GREEN_700, SLATE),
        "white": ("white", "#FFFFFF", DARK_DROM, DARK_TAG),
        "mono": ("mono", INK, INK, INK),
    }[scheme]
    defs, body = mark(kind, p)
    wm, ww = wordmark(70, ca, cd)
    s = 132 / (2 * DISK_R)
    inner = f'<g transform="translate({-(C - DISK_R) * s:.4f} {-(C - DISK_R) * s:.4f}) scale({s:.6f})">{body}</g>'
    width = 162 + ww
    if tag:
        tg, tw = SEMI.run(TAGLINE, 17.5, TAG_TRACK)
        width = max(width, 162 + tw)
        inner += f'<g transform="translate(162 73.5)">{wm}</g><g transform="translate(162 107.5)" fill="{ct}">{tg}</g>'
    else:
        inner += f'<g transform="translate(162 90.5)">{wm}</g>'
    width += 2
    return svg(width, 132, inner, defs, (900, 900 * 132 / width))


def logo_vertical(p="v"):
    defs, body = mark("color", p)
    wm, ww = wordmark(62, INK, GREEN_700)
    tg, tw = SEMI.run(TAGLINE, 15.5, TAG_TRACK)
    W = max(ww, tw) + 2
    s = 168 / (2 * DISK_R)
    inner = (f'<g transform="translate({W / 2 - C * s:.4f} {-(C - DISK_R) * s:.4f}) scale({s:.6f})">{body}</g>'
             f'<g transform="translate({(W - ww) / 2:.3f} 245.4)">{wm}</g>'
             f'<g transform="translate({(W - tw) / 2:.3f} 275.4)" fill="{SLATE}">{tg}</g>')
    return svg(W, 275.4, inner, defs, (620, 620 * 275.4 / W))


def feature_graphic():
    """Google Play feature graphic 1024×500."""
    p = "fg"
    defs = grad(p + "bg", "#0F3D27", "#04170F", 0, 0, 1024, 500)
    deco = "".join(
        f'<path fill="#FFFFFF" fill-opacity="0.05" transform="translate({x} {y}) scale({s})" fill-rule="evenodd" d="{D["disk"]}"/>'
        for x, y, s in [(700, -160, 4.2)])
    logo = logo_horizontal("white", p="fgl")
    inner_logo = logo[logo.index("<defs>"):logo.rindex("</svg>")]
    lw = float(logo.split('viewBox="0 0 ')[1].split()[0])
    scale = 640 / lw
    body = (f'<rect width="1024" height="500" fill="url(#{p}bg)"/>{deco}'
            f'<g transform="translate({(1024 - 640) / 2:.2f} {250 - 66 * scale:.2f}) scale({scale:.5f})">{inner_logo}</g>')
    return svg(1024, 500, body, defs, (1024, 500))


def adaptive_fg(p="af"):
    """108dp qatlam: oq doira + belgi, diametr 72dp ko'rinadigan maydonning 68%."""
    defs, body = mark("color", p)
    s = 0.68 * 72 / 108 * 200 / (2 * DISK_R)
    r_white = 67.456 / 0.723404 * s
    return svg(200, 200, f'<circle cx="100" cy="100" r="{r_white:.3f}" fill="#FFFFFF"/>'
               f'<g transform="translate({100 - C * s:.4f} {100 - C * s:.4f}) scale({s:.6f})">{body}</g>', defs)


def adaptive_mono():
    _, body = mark("white", "am")
    s = 0.68 * 72 / 108 * 200 / (2 * DISK_R)
    return svg(200, 200, f'<g transform="translate({100 - C * s:.4f} {100 - C * s:.4f}) scale({s:.6f})">{body}</g>')


def adaptive_bg():
    return svg(200, 200, '<rect width="200" height="200" fill="url(#abg)"/>', grad("abg", *APP_BG, 0, 0, 200, 200))


def embed(svg_text, x, y, w, h):
    vb = svg_text.split('viewBox="')[1].split('"')[0]
    return f'<svg x="{x}" y="{y}" width="{w}" height="{h}" viewBox="{vb}"' + svg_text[svg_text.index(">"):]


def label(text, x, y, size, color, font=None, track=0.12):
    paths, w = (font or SEMI).run(text, size, track)
    return f'<g transform="translate({x} {y})" fill="{color}">{paths}</g>', w


def preview():
    W, H = 1600, 1360
    out = [f'<rect width="{W}" height="{H}" fill="#F4F6FA"/>']
    card = lambda x, y, w, h, c="#FFFFFF": out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="16" fill="{c}"/>')
    cap = lambda t, x, y, c=SLATE: out.append(label(t, x, y, 14, c, track=0.14)[0])

    out.append(label("AVTODROM — LOGO SISTEMASI", 70, 80, 28, INK, track=0.06)[0])
    out.append(label("AvtoSmart belgisi · yashil + laym palitra", 70, 108, 16, SLATE, track=0.02)[0])

    card(60, 150, 740, 230); cap("ASOSIY / LIGHT", 105, 185)
    hl = logo_horizontal("color", p="pa")
    out.append(embed(hl, 105, 205, 150 * float(hl.split('viewBox="0 0 ')[1].split()[0]) / 132, 150))
    card(820, 150, 720, 230, "#0E3527"); cap("TO'Q FONDA / DARK", 862, 185, DARK_TAG)
    wl = logo_horizontal("white", p="pb")
    out.append(embed(wl, 862, 205, 150 * float(wl.split('viewBox="0 0 ')[1].split()[0]) / 132, 150))

    card(60, 410, 360, 420); cap("VERTIKAL", 110, 445)
    vl = logo_vertical(p="pc")
    vw, vh = [float(v) for v in vl.split('viewBox="0 0 ')[1].split('"')[0].split()]
    out.append(embed(vl, 240 - 130, 480, 260, 260 * vh / vw))
    card(440, 410, 360, 420); cap("MONOXROM", 470, 445)
    out.append(embed(icon_svg("mono", "pd"), 545, 490, 150, 150))
    ml = logo_horizontal("mono", p="pe")
    out.append(embed(ml, 470, 700, 72 * float(ml.split('viewBox="0 0 ')[1].split()[0]) / 132, 72))

    card(820, 410, 720, 200); cap("IKONKA  128 · 64 · 48 · 32 · 16", 862, 445)
    x = 862
    for i, s in enumerate((128, 64, 48, 32, 16)):
        kind = "simple" if s <= 32 else "color"
        out.append(embed(icon_svg(kind, f"pf{i}"), x, 462 + (128 - s) / 2, s, s))
        x += s + 38
    card(820, 640, 720, 190); cap("PLAY STORE / ANDROID", 862, 675)
    x = 862
    for i, s in enumerate((120, 100, 80)):
        out.append(embed(app_icon_svg(f"pg{i}", rounded=True), x, 690 + (120 - s) / 2, s, s))
        x += s + 30
    out.append(embed(app_icon_svg("ph", circle=True), x + 10, 700, 100, 100))

    card(60, 860, 1480, 230); cap("OILA: AVTOSMART  ·  AVTODROM", 105, 895)
    if AVTOSMART_ICON.exists():
        orig = AVTOSMART_ICON.read_text(encoding="utf-8").replace('"i1', '"os').replace("#i1", "#os")
        out.append(embed(orig, 105, 920, 140, 140))
        out.append(label("AvtoSmart", 138, 1080, 13, SLATE, track=0.04)[0])
        out.append(embed(icon_svg("color", "pi"), 275, 920, 140, 140))
        out.append(label("AvtoDrom", 312, 1080, 13, INK, track=0.04)[0])
    out.append(label("Belgi bir xil: rul, asfalt yo'l shaklidagi S,", 520, 965, 18, INK, track=0.01)[0])
    out.append(label("halqalar, tezlik yoyi, Montserrat shrifti.", 520, 993, 18, INK, track=0.01)[0])
    out.append(label("Farqi faqat rangda: ko'k → yashil, akvamarin → laym.", 520, 1035, 18, SLATE, track=0.01)[0])

    out.append(label("RANG PALITRASI", 70, 1140, 18, INK, track=0.08)[0])
    pal = [("Ink 900", INK, "Avto / monoxrom"), ("Green 700", GREEN_700, "Drom"),
           ("Green 500", GREEN_500, "gradient boshi"), ("Forest", FOREST, "gradient oxiri"),
           ("Lime 400", LIME, "urg'u yoyi"), ("Slate", SLATE, "tagline")]
    for i, (n, c, u) in enumerate(pal):
        x = 70 + 250 * i
        out.append(f'<rect x="{x}" y="1165" width="220" height="90" rx="8" fill="{c}"/>')
        out.append(label(n, x, 1282, 15, INK, track=0.03)[0])
        out.append(label(c, x, 1304, 13, SLATE, track=0.05)[0])
        out.append(label(u, x, 1326, 12, "#9AA3C0", track=0.03)[0])
    return svg(W, H, "".join(out), px=(W, H))


# ── Yozish / render ─────────────────────────────────────────────────────
def write(rel, text):
    f = ROOT / rel
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(text, encoding="utf-8")


def png(svg_text, rel, w, h=None, rgb=False):
    f = ROOT / rel
    f.parent.mkdir(parents=True, exist_ok=True)
    data = bytes(resvg_py.svg_to_bytes(svg_string=svg_text, width=w, height=h or w))
    f.write_bytes(data)
    if rgb:
        Image.open(f).convert("RGB").save(f)
    return f


def main():
    for d in ("svg", "png", "webp", "favicon", "android", "play-store", "godot", "windows"):
        shutil.rmtree(ROOT / d, ignore_errors=True)

    icons = {
        "avtodrom-icon": icon_svg("color"),
        "avtodrom-icon-simple": icon_svg("simple"),
        "avtodrom-icon-white": icon_svg("white"),
        "avtodrom-icon-mono": icon_svg("mono"),
        "avtodrom-app-icon": app_icon_svg(),
    }
    logos = {
        "avtodrom-logo-horizontal": logo_horizontal("color"),
        "avtodrom-logo-horizontal-notag": logo_horizontal("color", tag=False),
        "avtodrom-logo-white": logo_horizontal("white"),
        "avtodrom-logo-mono": logo_horizontal("mono"),
        "avtodrom-logo-vertical": logo_vertical(),
    }
    for name, s in {**icons, **logos}.items():
        write(f"svg/{name}.svg", s)
    write("svg/avtodrom-adaptive-foreground.svg", adaptive_fg())
    write("svg/avtodrom-adaptive-background.svg", adaptive_bg())
    write("svg/avtodrom-adaptive-monochrome.svg", adaptive_mono())
    write("svg/avtodrom-feature-graphic.svg", feature_graphic())

    for name, s in icons.items():
        for size in (16, 32, 64, 128, 256, 512, 1024):
            png(s, f"png/{name}-{size}.png", size)
    for name, s in logos.items():
        vb = [float(v) for v in s.split('viewBox="')[1].split('"')[0].split()]
        for w in (600, 1200, 2400):
            png(s, f"png/{name}-{w}w.png", w, round(w * vb[3] / vb[2]))

    # Google Play
    png(app_icon_svg(), "play-store/app-icon-512.png", 512)
    png(feature_graphic(), "play-store/feature-graphic-1024x500.png", 1024, 500, rgb=True)

    # Android adaptive + legacy
    png(adaptive_fg(), "android/ic_launcher_foreground.png", 432)
    png(adaptive_bg(), "android/ic_launcher_background.png", 432)
    png(adaptive_mono(), "android/ic_launcher_monochrome.png", 432)
    for dpi, size in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        png(app_icon_svg("lr", rounded=True), f"android/mipmap-{dpi}_ic_launcher.png", size)
        png(app_icon_svg("lc", circle=True), f"android/mipmap-{dpi}_ic_launcher_round.png", size)

    # Favicon
    png(icons["avtodrom-icon-simple"], "favicon/favicon-16x16.png", 16)
    png(icons["avtodrom-icon-simple"], "favicon/favicon-32x32.png", 32)
    png(app_icon_svg(), "favicon/apple-touch-icon.png", 180)
    png(icons["avtodrom-icon"], "favicon/android-chrome-192x192.png", 192)
    png(icons["avtodrom-icon"], "favicon/android-chrome-512x512.png", 512)
    write("favicon/favicon.svg", icons["avtodrom-icon"])

    # Windows .ico (≤32 px — soddalashtirilgan variant)
    ico_imgs = []
    for size in (256, 128, 64, 48, 32, 24, 16):
        src = icons["avtodrom-icon-simple" if size <= 32 else "avtodrom-icon"]
        tmp = png(src, f"windows/_tmp{size}.png", size)
        ico_imgs.append(Image.open(tmp).convert("RGBA"))
    ico_imgs[0].save(ROOT / "windows/avtodrom.ico", format="ICO",
                     sizes=[im.size for im in ico_imgs], append_images=ico_imgs[1:])
    shutil.copy(ROOT / "windows/avtodrom.ico", ROOT / "favicon/favicon.ico")
    for f in (ROOT / "windows").glob("_tmp*.png"):
        f.unlink()

    # Godot loyihasi kutayotgan nomlar bilan (game/assets/ui va game/icon.png)
    png(app_icon_svg(), "godot/icon.png", 1024)
    png(app_icon_svg(), "godot/icon_1024.png", 1024)
    png(app_icon_svg(), "godot/icon_192.png", 192)
    shutil.copy(ROOT / "android/ic_launcher_foreground.png", ROOT / "godot/icon_adaptive_fg.png")
    shutil.copy(ROOT / "android/ic_launcher_background.png", ROOT / "godot/icon_adaptive_bg.png")
    shutil.copy(ROOT / "android/ic_launcher_monochrome.png", ROOT / "godot/icon_adaptive_mono.png")
    shutil.copy(ROOT / "windows/avtodrom.ico", ROOT / "godot/icon.ico")

    # WebP nusxalar
    for f in (ROOT / "png").glob("*.png"):
        out = ROOT / "webp" / (f.stem + ".webp")
        out.parent.mkdir(exist_ok=True)
        Image.open(f).save(out, lossless=True)

    png(preview(), "PREVIEW.png", 1600, 1360, rgb=True)
    print("tayyor:", ROOT)


if __name__ == "__main__":
    main()
