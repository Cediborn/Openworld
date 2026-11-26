#!/usr/bin/env python3
"""Generates Openworld's UI art (original, CC0): panel frame, parchment page,
wax seal, ornamental divider and the icon set. Deterministic (fixed seeds).

    python3 game/tools/make_ui_art.py      # writes game/assets/ui/
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "ui")
GOLD = (201, 163, 92, 255)
GOLD_DIM = (150, 118, 64, 255)
INK = (58, 40, 24)


def noise(w, h, seed, blur):
    rng = np.random.default_rng(seed)
    n = Image.fromarray((rng.random((h, w)) * 255).astype(np.uint8))
    return np.asarray(n.filter(ImageFilter.GaussianBlur(blur)), dtype=np.float32) / 255.0


def ornament(d, cx, cy, sx, sy, col):
    """A small corner flourish: diamond, two scrolls and a dot, mirrored by (sx, sy)."""
    def p(x, y):
        return (cx + x * sx, cy + y * sy)
    d.polygon([p(0, -7), p(7, 0), p(0, 7), p(-7, 0)], fill=col)
    d.polygon([p(0, -3), p(3, 0), p(0, 3), p(-3, 0)], fill=(30, 22, 15, 255))
    d.line([p(9, 0), p(26, 0)], fill=col, width=2)
    d.line([p(0, 9), p(0, 26)], fill=col, width=2)
    d.ellipse([p(28, 0)[0] - 2.5, p(28, 0)[1] - 2.5, p(28, 0)[0] + 2.5, p(28, 0)[1] + 2.5], fill=col)
    d.ellipse([p(0, 28)[0] - 2.5, p(0, 28)[1] - 2.5, p(0, 28)[0] + 2.5, p(0, 28)[1] + 2.5], fill=col)


def frame():
    """Dark panel with a double antique-gold border and corner ornaments (9-patch, margin 30)."""
    s = 160
    base = np.zeros((s, s, 4), np.float32)
    n = noise(s, s, 3, 1.2) * 0.6 + noise(s, s, 4, 6) * 0.4
    for i, c in enumerate((22, 17, 13)):
        base[..., i] = c + n * 9
    base[..., 3] = 240
    img = Image.fromarray(base.astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)
    d.rectangle([5, 5, s - 6, s - 6], outline=GOLD, width=2)
    d.rectangle([10, 10, s - 11, s - 11], outline=GOLD_DIM, width=1)
    for (cx, sx) in ((14, 1), (s - 15, -1)):
        for (cy, sy) in ((14, 1), (s - 15, -1)):
            ornament(d, cx, cy, sx, sy, GOLD)
    img.save(os.path.join(OUT, "frame.png"))


def parchment():
    """A warm parchment page with fibres, stains and darkened edges (9-patch, margin 40)."""
    w = h = 512
    fib = noise(w, h, 11, 0.6)
    cloud = noise(w, h, 12, 18)
    stain = noise(w, h, 13, 40)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    wob = (noise(w, h, 14, 6) - 0.5) * 18.0   # ragged, uneven ageing
    ex = np.clip((np.minimum(xx, w - 1 - xx) + wob) / 34.0, 0, 1)
    ey = np.clip((np.minimum(yy, h - 1 - yy) + wob) / 34.0, 0, 1)
    edge = (ex * ey) ** 0.7
    shade = 0.84 + cloud * 0.14 + fib * 0.06 - np.clip(stain - 0.58, 0, 1) * 0.6
    paper = np.stack([238 * shade, 222 * shade, 184 * shade], -1)
    burnt = np.array([122, 82, 44], np.float32)
    t = (1.0 - edge)[..., None] * 0.75   # edges age to a warm brown, not grey
    rgb = paper * (1 - t) + burnt * t
    rgb = np.concatenate([rgb, np.full_like(shade, 255)[..., None]], -1)
    img = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGBA")
    d = ImageDraw.Draw(img)
    d.rectangle([22, 22, w - 23, h - 23], outline=(150, 112, 62, 140), width=2)
    img.save(os.path.join(OUT, "parchment.png"))


def seal():
    """Red wax seal with an embossed star, for completed quests."""
    s = 96
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rng = np.random.default_rng(5)
    pts = []
    for i in range(36):
        a = i / 36 * math.tau
        r = 42 + rng.uniform(-3, 3)
        pts.append((48 + r * math.cos(a), 48 + r * math.sin(a)))
    d.polygon(pts, fill=(128, 22, 20, 255))
    d.ellipse([16, 16, 80, 80], fill=(150, 30, 26, 255), outline=(98, 14, 12, 255), width=3)
    star = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 22 if i % 2 == 0 else 9
        star.append((48 + r * math.cos(a), 48 + r * math.sin(a)))
    d.polygon(star, fill=(186, 58, 48, 255), outline=(96, 14, 12, 255))
    img = img.filter(ImageFilter.SMOOTH)
    img.save(os.path.join(OUT, "seal.png"))


def divider():
    """Ornamental rule for under headings."""
    w, h = 512, 24
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for x in range(w):
        a = int(255 * min(1.0, min(x, w - x) / 140.0))
        d.point((x, 12), fill=GOLD[:3] + (a,))
        d.point((x, 13), fill=GOLD_DIM[:3] + (a // 2,))
    c = w // 2
    d.polygon([(c, 3), (c + 9, 12), (c, 21), (c - 9, 12)], fill=GOLD)
    d.polygon([(c, 7), (c + 5, 12), (c, 17), (c - 5, 12)], fill=(40, 30, 20, 255))
    for sx in (-1, 1):
        d.ellipse([c + sx * 18 - 3, 9, c + sx * 18 + 3, 15], fill=GOLD)
    img.save(os.path.join(OUT, "divider.png"))


# ---------- Icons (white, tinted in game) ----------

ICONS = {
    # weapons and kit
    "sword": '<path d="M46 6l12 0 0 12-26 26-6-6z"/><path d="M14 40l10 10-4 4-3-3-6 6-4-4 6-6-3-3z"/><rect x="18" y="36" width="16" height="5" transform="rotate(45 26 38)"/>',
    "armor": '<path d="M32 6l22 8v14c0 14-9 24-22 30C19 52 10 42 10 28V14z"/><path d="M32 14l14 5v9c0 9-6 16-14 20z" fill="#000" fill-opacity=".35"/>',
    "potion": '<rect x="26" y="6" width="12" height="8" rx="2"/><path d="M27 14h10v10c8 3 13 10 13 18 0 10-8 17-18 17S14 52 14 42c0-8 5-15 13-18z"/><path d="M17 42h30c0 8-7 13-15 13s-15-5-15-13z" fill="#000" fill-opacity=".3"/>',
    "key": '<circle cx="20" cy="20" r="12"/><circle cx="20" cy="20" r="5" fill="#000" fill-opacity=".6"/><path d="M27 27l26 26-5 5-4-4-4 4-4-4 4-4-17-17z"/>',
    "quest": '<path d="M14 8h30c4 0 8 4 8 8v36c0 2-2 4-4 4H20c-4 0-8-4-8-8V12c0-2 1-4 2-4z"/><path d="M20 20h24M20 28h24M20 36h16" stroke="#000" stroke-opacity=".45" stroke-width="3"/>',
    "material": '<path d="M12 40l12-22 16-4 14 14-6 20-22 4z"/><path d="M24 18l6 16 24-6M30 34l-6 20" stroke="#000" stroke-opacity=".35" stroke-width="2.5" fill="none"/>',
    "collectible": '<path d="M32 4l10 14-10 42L22 18z"/><path d="M12 22l10-4 10 42zM52 22l-10-4-10 42z" fill-opacity=".7"/>',
    "trophy": '<path d="M16 8c4 20 4 34-4 50 16-6 26-20 30-36l10-4c-8-2-14-2-20 2C28 14 22 10 16 8z"/>',
    "coin": '<circle cx="32" cy="32" r="24"/><circle cx="32" cy="32" r="17" fill="#000" fill-opacity=".3"/><path d="M32 20l4 8 9 1-7 6 2 9-8-5-8 5 2-9-7-6 9-1z"/>',
    "heart": '<path d="M32 56C14 42 6 32 6 21 6 12 13 6 21 6c5 0 9 3 11 7 2-4 6-7 11-7 8 0 15 6 15 15 0 11-8 21-26 35z"/>',
    "person": '<circle cx="32" cy="18" r="11"/><path d="M10 58c0-14 10-24 22-24s22 10 22 24z"/>',
    "map": '<path d="M6 14l16-6 20 6 16-6v42l-16 6-20-6-16 6z"/><path d="M22 8v42M42 14v42" stroke="#000" stroke-opacity=".4" stroke-width="2"/>',
    "book": '<path d="M6 12c10-4 18-4 26 2v42c-8-6-16-6-26-2z"/><path d="M58 12c-10-4-18-4-26 2v42c8-6 16-6 26-2z" fill-opacity=".8"/>',
    "gear": '<path d="M28 4h8l2 8 6 3 7-4 6 6-4 7 3 6 8 2v8l-8 2-3 6 4 7-6 6-7-4-6 3-2 8h-8l-2-8-6-3-7 4-6-6 4-7-3-6-8-2v-8l8-2 3-6-4-7 6-6 7 4 6-3z"/><circle cx="32" cy="32" r="9" fill="#000" fill-opacity=".6"/>',
    "compass": '<circle cx="32" cy="32" r="26" fill="none" stroke="#fff" stroke-width="4"/><path d="M32 10l6 22-6 22-6-22z"/><path d="M32 32l6 0-6 22-6-22z" fill="#000" fill-opacity=".35"/>',
    "town": '<path d="M6 56V30l10-10 10 10v26zM30 56V22l12-14 12 14v34z"/><rect x="38" y="36" width="8" height="20" fill="#000" fill-opacity=".45"/><rect x="12" y="40" width="8" height="16" fill="#000" fill-opacity=".45"/>',
    "cave": '<path d="M4 56c4-18 14-38 28-40 14 2 24 22 28 40z"/><path d="M20 56c2-12 6-22 12-22s10 10 12 22z" fill="#000" fill-opacity=".75"/>',
    "landmark": '<path d="M24 58l4-46h8l4 46z"/><path d="M20 12h24l-4-6H24z"/><rect x="29" y="22" width="6" height="8" fill="#000" fill-opacity=".45"/>',
    "shrine": '<path d="M8 22h48l-4-8H12zM12 22h6v32h-6zM46 22h6v32h-6zM24 22h16v6H24z"/><rect x="6" y="54" width="52" height="5"/>',
    "treasure": '<path d="M8 28c0-10 10-16 24-16s24 6 24 16z"/><rect x="8" y="28" width="48" height="26" rx="2"/><rect x="28" y="26" width="8" height="12" fill="#000" fill-opacity=".5"/>',
    "boss": '<path d="M32 6C18 6 10 16 10 28c0 8 4 13 8 16v10h28V44c4-3 8-8 8-16C54 16 46 6 32 6z"/><circle cx="23" cy="29" r="6" fill="#000" fill-opacity=".75"/><circle cx="41" cy="29" r="6" fill="#000" fill-opacity=".75"/><path d="M26 46v8M32 46v8M38 46v8" stroke="#000" stroke-opacity=".5" stroke-width="3"/>',
    "discovery": '<path d="M32 4l7 20h21L43 37l7 21-18-13-18 13 7-21L4 24h21z"/>',
    "horse": '<path d="M14 58l4-18c-4-6-4-14 2-20l8-10 4 6 10 2c6 2 10 8 12 14l-6 4-6-4-4 6v20h-6V44h-8l-2 14z"/>',
    "lore": '<path d="M10 10h36l8 8v38H10z"/><path d="M46 10v8h8" fill="#000" fill-opacity=".4"/><path d="M18 26h28M18 34h28M18 42h20" stroke="#000" stroke-opacity=".45" stroke-width="3"/>',
    "note": '<path d="M12 6h40v40L38 58H12z"/><path d="M38 58V46h14" fill="#000" fill-opacity=".4"/><path d="M20 20h24M20 28h24M20 36h14" stroke="#000" stroke-opacity=".45" stroke-width="3"/>',
    "pin": '<path d="M32 60C22 44 14 34 14 24a18 18 0 0 1 36 0c0 10-8 20-18 36z"/><circle cx="32" cy="24" r="7" fill="#000" fill-opacity=".55"/>',
    "pistol": '<path d="M6 20h40l12-4v10l-12 2-6 4-6 2-4 18H16l6-18-16 0z"/>',
    "continue": '<path d="M18 8l34 24-34 24z"/>',
    "quit": '<path d="M24 8h26v48H24v-8h18V16H24z"/><path d="M6 32l14-12v8h16v8H20v8z"/>',
    "save": '<path d="M8 8h40l8 8v40H8z"/><rect x="18" y="8" width="24" height="16" fill="#000" fill-opacity=".45"/><rect x="16" y="34" width="32" height="18" fill="#000" fill-opacity=".3"/>',
    "display": '<rect x="6" y="10" width="52" height="34" rx="2"/><rect x="11" y="15" width="42" height="24" fill="#000" fill-opacity=".45"/><path d="M24 52h16l-3-8H27z"/>',
    "audio": '<path d="M8 24h12l14-12v40L20 40H8z"/><path d="M42 22c4 6 4 14 0 20M48 16c8 9 8 23 0 32" stroke="#fff" stroke-width="4" fill="none"/>',
    "controls": '<rect x="4" y="18" width="56" height="30" rx="14"/><path d="M18 26v14M11 33h14" stroke="#000" stroke-opacity=".55" stroke-width="4"/><circle cx="44" cy="29" r="3.5" fill="#000" fill-opacity=".55"/><circle cx="50" cy="37" r="3.5" fill="#000" fill-opacity=".55"/>',
    "access": '<circle cx="32" cy="10" r="6"/><path d="M10 20l22 4 22-4 2 6-16 4v10l6 20h-7l-7-18-7 18h-7l6-20V30L8 26z"/>',
    "graphics": '<path d="M6 54l16-26 12 16 8-10 16 20z"/><circle cx="46" cy="16" r="7"/>',
    "play": '<path d="M12 50l12-28 10 14 8-10 12 24z"/><path d="M10 10h44v44H10z" fill="none" stroke="#fff" stroke-width="4"/>',
    "clock": '<circle cx="32" cy="32" r="26"/><path d="M32 14v18l12 8" stroke="#000" stroke-opacity=".6" stroke-width="5" fill="none"/>',
}


def icons():
    os.makedirs(os.path.join(OUT, "icons"), exist_ok=True)
    for name, body in ICONS.items():
        svg = '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" fill="#fff">%s</svg>\n' % body
        with open(os.path.join(OUT, "icons", name + ".svg"), "w") as f:
            f.write(svg)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    frame()
    parchment()
    seal()
    divider()
    icons()
    print("UI art written to", os.path.normpath(OUT))
