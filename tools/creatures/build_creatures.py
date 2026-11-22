#!/usr/bin/env python3
"""Builds the green-valley animals (red deer, wild boar, grey wolf) as skinned,
vertex-coloured .glb files in game/assets/creatures/.

Author: Claude (Openworld). Run from the repo root:
    python3 tools/creatures/build_creatures.py

Every animal shares one skeleton layout so the game's gait code works for all:
Hips > Spine > Chest > Neck > Head, Hips > Tail, and four legs of four bones
(F1..F4 front, H1..H4 hind, _L / _R). Animals face -Z (Godot's forward).
Designs follow the Gemini concept sheet: dark-maned stag with big antlers,
bristly dark boar with tusks, grey wolf with cream underside.
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from sdf_model import Model, cone, ell, mirror, fbm  # noqa: E402

OUT = pathlib.Path(__file__).resolve().parents[2] / "game" / "assets" / "creatures"


def legs(front, hind):
    """Bones for four legs. front/hind: 4 (x, y, z) joint positions, left side."""
    bones = []
    for side, sx in (("_L", 1), ("_R", -1)):
        for tag, pts, parent in (("F", front, "Chest"), ("H", hind, "Hips")):
            prev = parent
            for i, (x, y, z) in enumerate(pts):
                nm = f"{tag}{i + 1}{side}"
                bones.append((nm, prev, (x * sx, y, z)))
                prev = nm
    return bones


def leg_parts(pts, radii, colors, upper):
    """Parts for one left leg along its 4 joints. upper: ellipsoid for the shoulder/thigh."""
    tag = "F" if pts[0][2] < 0 else "H"
    parts = [ell(upper[0], upper[1], f"{tag}1_L", colors[0], 0.05)]
    for i in range(3):
        parts.append(cone(pts[i], pts[i + 1], radii[i], radii[i + 1], f"{tag}{i + 1}_L" if i == 0 else f"{tag}{i + 1}_L", colors[min(i, len(colors) - 1)], 0.035))
    return parts


def shade(base, verts, norms, belly=None, belly_amt=0.0, mottle=0.12, seed=3, freq=9.0):
    """Common colour pass: mottled fur, darker back, optional lighter belly."""
    n = fbm(verts, freq, 3, seed)
    fine = fbm(verts, 70.0, 2, seed + 5)
    c = base * (1.0 - mottle + 2 * mottle * n)[:, None] * (0.9 + 0.2 * fine)[:, None]
    up = np.clip(norms[:, 1], 0, 1)[:, None]
    c = c * (1.0 - 0.12 * up)                       # sun-bleached top reads too light otherwise
    if belly is not None:
        down = np.clip(-norms[:, 1] - 0.15, 0, 1)[:, None] * belly_amt
        c = c * (1 - down) + np.asarray(belly) * down
    return c


# ---------------------------------------------------------------- red deer

def deer():
    B = (0.42, 0.30, 0.20)
    DARK = (0.26, 0.19, 0.13)
    LEG = (0.36, 0.27, 0.19)
    HOOF = (0.05, 0.04, 0.04)
    ANT = (0.42, 0.33, 0.22)
    front = [(0.12, 1.05, -0.38), (0.12, 0.80, -0.39), (0.12, 0.40, -0.38), (0.12, 0.08, -0.37)]
    hind = [(0.13, 1.02, 0.38), (0.13, 0.70, 0.32), (0.13, 0.49, 0.50), (0.13, 0.08, 0.47)]
    bones = [("Hips", None, (0, 1.05, 0.35)), ("Spine", "Hips", (0, 1.08, 0.0)),
             ("Chest", "Spine", (0, 1.1, -0.35)), ("Neck", "Chest", (0, 1.22, -0.5)),
             ("Head", "Neck", (0, 1.62, -0.72)), ("Tail", "Hips", (0, 1.12, 0.62))] + legs(front, hind)
    side = []
    side += leg_parts(front, [0.065, 0.045, 0.026, 0.024], [B, LEG, LEG], ((0.12, 0.98, -0.37), (0.07, 0.19, 0.11)))
    side += leg_parts(hind, [0.08, 0.06, 0.028, 0.024], [B, LEG, LEG], ((0.12, 0.90, 0.38), (0.09, 0.23, 0.18)))
    side += [
        cone(front[3], (0.12, 0.012, -0.41), 0.03, 0.028, "F4_L", HOOF, 0.012),
        cone(hind[3], (0.13, 0.012, 0.43), 0.03, 0.028, "H4_L", HOOF, 0.012),
        ell((0.058, 1.668, -0.79), (0.016, 0.016, 0.016), "Head", HOOF, 0.004),
        cone((0.055, 1.71, -0.69), (0.15, 1.79, -0.64), 0.032, 0.018, "Head", B, 0.02),
        # Antlers: main beam with brow, bez, trez and crown tines.
        cone((0.035, 1.73, -0.70), (0.12, 1.92, -0.66), 0.026, 0.02, "Head", ANT, 0.012, tag="antler"),
        cone((0.12, 1.92, -0.66), (0.22, 2.12, -0.62), 0.02, 0.017, "Head", ANT, 0.008, tag="antler"),
        cone((0.22, 2.12, -0.62), (0.24, 2.34, -0.68), 0.017, 0.013, "Head", ANT, 0.008, tag="antler"),
        cone((0.06, 1.79, -0.69), (0.08, 1.86, -0.90), 0.016, 0.008, "Head", ANT, 0.008, tag="antler"),
        cone((0.10, 1.87, -0.67), (0.13, 1.95, -0.86), 0.014, 0.007, "Head", ANT, 0.008, tag="antler"),
        cone((0.20, 2.08, -0.63), (0.25, 2.16, -0.82), 0.013, 0.006, "Head", ANT, 0.008, tag="antler"),
        cone((0.24, 2.30, -0.67), (0.32, 2.42, -0.72), 0.012, 0.005, "Head", ANT, 0.006, tag="antler"),
        cone((0.24, 2.30, -0.67), (0.19, 2.45, -0.78), 0.012, 0.005, "Head", ANT, 0.006, tag="antler"),
        cone((0.23, 2.24, -0.66), (0.30, 2.33, -0.55), 0.011, 0.005, "Head", ANT, 0.006, tag="antler"),
    ]
    parts = mirror(side) + [
        ell((0, 1.05, -0.02), (0.21, 0.26, 0.48), "Spine", B, 0.08),
        ell((0, 1.04, -0.34), (0.19, 0.29, 0.25), "Chest", B, 0.08),
        ell((0, 1.07, 0.36), (0.19, 0.23, 0.25), "Hips", B, 0.08),
        cone((0, 1.18, -0.42), (0, 1.58, -0.68), 0.13, 0.085, "Neck", DARK, 0.06, fur=0.010),
        ell((0, 1.30, -0.54), (0.115, 0.18, 0.13), "Neck", DARK, 0.06, fur=0.022),
        ell((0, 1.68, -0.73), (0.075, 0.07, 0.085), "Head", B, 0.03),
        cone((0, 1.65, -0.74), (0, 1.585, -0.95), 0.07, 0.04, "Head", B, 0.03),
        ell((0, 1.575, -0.965), (0.034, 0.03, 0.026), "Head", HOOF, 0.012),
        ell((0, 1.10, 0.60), (0.04, 0.08, 0.04), "Tail", DARK, 0.03),
    ]
    m = Model("RedDeer", bones, parts, voxel=0.014, tris=7000, fur_freq=60)

    def col(v, n, pd, c):
        c = shade(c, v, n, belly=(0.58, 0.47, 0.34), belly_amt=0.7)
        rump = np.clip(1 - np.hypot(v[:, 0] / 0.14, (v[:, 1] - 1.05) / 0.2), 0, 1) * (v[:, 2] > 0.5)
        c = c * (1 - rump[:, None]) + np.array([0.70, 0.58, 0.42]) * rump[:, None]
        ant = np.array([p.tag == "antler" for p in m.parts])
        on_ant = pd[:, ant].min(1) < 0.004
        tip = np.clip((v[:, 1] - 1.9) / 0.5, 0, 1)
        c[on_ant] = (np.array(ANT) * (1 - tip[on_ant, None]) + np.array([0.82, 0.77, 0.66]) * tip[on_ant, None]) * (0.85 + 0.3 * fbm(v[on_ant], 40, 2, 9))[:, None]
        return c
    m.color_fn = col
    return m


# ---------------------------------------------------------------- wild boar

def boar():
    B = (0.33, 0.27, 0.21)
    DARK = (0.19, 0.16, 0.13)
    LEG = (0.20, 0.17, 0.14)
    HOOF = (0.05, 0.04, 0.04)
    front = [(0.12, 0.62, -0.33), (0.12, 0.40, -0.34), (0.12, 0.20, -0.33), (0.12, 0.05, -0.33)]
    hind = [(0.12, 0.62, 0.36), (0.12, 0.42, 0.32), (0.12, 0.24, 0.42), (0.12, 0.05, 0.40)]
    bones = [("Hips", None, (0, 0.62, 0.32)), ("Spine", "Hips", (0, 0.64, 0.0)),
             ("Chest", "Spine", (0, 0.68, -0.3)), ("Neck", "Chest", (0, 0.68, -0.48)),
             ("Head", "Neck", (0, 0.62, -0.6)), ("Tail", "Hips", (0, 0.66, 0.62))] + legs(front, hind)
    side = []
    side += leg_parts(front, [0.07, 0.045, 0.032, 0.03], [B, LEG, LEG], ((0.12, 0.6, -0.32), (0.08, 0.16, 0.12)))
    side += leg_parts(hind, [0.08, 0.055, 0.032, 0.03], [B, LEG, LEG], ((0.12, 0.56, 0.36), (0.09, 0.18, 0.15)))
    side += [
        cone(front[3], (0.12, 0.012, -0.36), 0.034, 0.03, "F4_L", HOOF, 0.01),
        cone(hind[3], (0.12, 0.012, 0.37), 0.034, 0.03, "H4_L", HOOF, 0.01),
        cone((0.065, 0.41, -0.88), (0.11, 0.50, -0.90), 0.016, 0.005, "Head", (0.86, 0.82, 0.70), 0.004, tag="tusk"),
        ell((0.085, 0.64, -0.70), (0.013, 0.013, 0.013), "Head", HOOF, 0.004),
        cone((0.08, 0.76, -0.6), (0.14, 0.88, -0.56), 0.045, 0.012, "Head", DARK, 0.02, fur=0.01),
    ]
    parts = mirror(side) + [
        ell((0, 0.60, 0.0), (0.22, 0.26, 0.48), "Spine", B, 0.09, fur=0.016),
        ell((0, 0.66, -0.30), (0.23, 0.30, 0.27), "Chest", B, 0.09, fur=0.02),
        ell((0, 0.60, 0.32), (0.20, 0.23, 0.24), "Hips", B, 0.08, fur=0.016),
        cone((0, 0.88, -0.36), (0, 0.80, 0.25), 0.06, 0.035, "Spine", DARK, 0.07, fur=0.035),
        cone((0, 0.63, -0.52), (0, 0.43, -0.93), 0.16, 0.06, "Head", B, 0.07, fur=0.012),
        ell((0, 0.55, -0.64), (0.15, 0.14, 0.15), "Head", B, 0.06, fur=0.015),
        ell((0, 0.42, -0.965), (0.06, 0.055, 0.03), "Head", (0.20, 0.16, 0.15), 0.015),
        cone((0, 0.66, 0.6), (0, 0.48, 0.68), 0.02, 0.012, "Tail", DARK, 0.02),
    ]
    m = Model("WildBoar", bones, parts, voxel=0.013, tris=6500, fur_freq=75)

    def col(v, n, pd, c):
        c = shade(c, v, n, belly=(0.26, 0.22, 0.18), belly_amt=0.4, mottle=0.16)
        tusk = np.array([p.tag == "tusk" for p in m.parts])
        c[pd[:, tusk].min(1) < 0.004] = (0.86, 0.82, 0.70)
        return c
    m.color_fn = col
    return m


# ---------------------------------------------------------------- grey wolf

def wolf():
    G = (0.50, 0.48, 0.45)
    SADDLE = (0.30, 0.29, 0.28)
    CREAM = (0.80, 0.76, 0.68)
    TAN = (0.62, 0.56, 0.48)
    PAD = (0.08, 0.07, 0.07)
    front = [(0.08, 0.66, -0.30), (0.08, 0.45, -0.31), (0.08, 0.12, -0.30), (0.08, 0.03, -0.33)]
    hind = [(0.09, 0.66, 0.32), (0.09, 0.45, 0.27), (0.09, 0.22, 0.40), (0.09, 0.03, 0.38)]
    bones = [("Hips", None, (0, 0.68, 0.32)), ("Spine", "Hips", (0, 0.70, 0.0)),
             ("Chest", "Spine", (0, 0.69, -0.28)), ("Neck", "Chest", (0, 0.75, -0.42)),
             ("Head", "Neck", (0, 0.83, -0.58)), ("Tail", "Hips", (0, 0.72, 0.46))] + legs(front, hind)
    side = []
    side += leg_parts(front, [0.05, 0.035, 0.024, 0.026], [G, TAN, TAN], ((0.08, 0.62, -0.29), (0.055, 0.14, 0.08)))
    side += leg_parts(hind, [0.065, 0.045, 0.025, 0.026], [G, TAN, TAN], ((0.085, 0.60, 0.32), (0.07, 0.16, 0.12)))
    side += [
        ell((0.08, 0.025, -0.35), (0.03, 0.022, 0.04), "F4_L", PAD, 0.02),
        ell((0.09, 0.025, 0.36), (0.03, 0.022, 0.04), "H4_L", PAD, 0.02),
        ell((0.045, 0.865, -0.665), (0.012, 0.01, 0.01), "Head", (0.75, 0.55, 0.15), 0.003, tag="eye"),
        cone((0.05, 0.90, -0.575), (0.07, 0.99, -0.56), 0.036, 0.006, "Head", SADDLE, 0.015),
    ]
    parts = mirror(side) + [
        ell((0, 0.67, 0.0), (0.14, 0.17, 0.40), "Spine", G, 0.07, fur=0.006),
        ell((0, 0.65, -0.27), (0.15, 0.22, 0.20), "Chest", G, 0.07, fur=0.008),
        ell((0, 0.68, 0.30), (0.13, 0.15, 0.18), "Hips", G, 0.06, fur=0.006),
        ell((0, 0.80, 0.0), (0.10, 0.06, 0.32), "Spine", SADDLE, 0.06, fur=0.006),
        cone((0, 0.68, -0.33), (0, 0.82, -0.50), 0.15, 0.10, "Neck", G, 0.07, fur=0.013),
        ell((0, 0.845, -0.60), (0.09, 0.083, 0.10), "Head", G, 0.04, fur=0.004),
        cone((0, 0.815, -0.64), (0, 0.775, -0.80), 0.052, 0.028, "Head", CREAM, 0.03),
        ell((0, 0.787, -0.81), (0.02, 0.017, 0.015), "Head", PAD, 0.006),
        cone((0, 0.72, 0.44), (0, 0.48, 0.70), 0.05, 0.07, "Tail", G, 0.04, fur=0.015),
        cone((0, 0.48, 0.70), (0, 0.36, 0.74), 0.07, 0.03, "Tail", SADDLE, 0.03, fur=0.013),
    ]
    m = Model("GreyWolf", bones, parts, voxel=0.011, tris=6500, fur_freq=110)

    def col(v, n, pd, c):
        c = shade(c, v, n, belly=CREAM, belly_amt=1.0, mottle=0.08, freq=7)
        # Pale face mask and throat, as on the concept sheet.
        throat = np.clip(1 - np.hypot(v[:, 0] / 0.09, (v[:, 1] - 0.68) / 0.12), 0, 1) * (v[:, 2] < -0.33) * (n[:, 2] < 0.2)
        c = c * (1 - throat[:, None]) + np.array(CREAM) * throat[:, None]
        eye = np.array([p.tag == "eye" for p in m.parts])
        c[pd[:, eye].min(1) < 0.003] = (0.75, 0.55, 0.15)
        return c
    m.color_fn = col
    return m


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    only = sys.argv[1:]
    for fn in (deer, boar, wolf):
        m = fn()
        if only and m.name not in only:
            continue
        nv, nf = m.build(OUT / f"{m.name}.glb")
        print(f"{m.name}: {nv} verts, {nf} tris")


if __name__ == "__main__":
    main()
