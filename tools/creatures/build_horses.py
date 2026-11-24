#!/usr/bin/env python3
"""Builds the three riding horses as skinned, vertex-coloured .glb files in
game/assets/creatures/: HorseWhite, HorseBlack and HorseBrown (a bay: brown
coat, black mane, tail and lower legs).

Author: Claude (Openworld). Run from the repo root:
    python3 tools/creatures/build_horses.py [HorseWhite ...]

Same skeleton layout as the other animals (see build_creatures.py), so the
game's gait code animates them: Hips > Spine > Chest > Neck > Head,
Hips > Tail, legs F1..F4 / H1..H4 (_L / _R). Faces -Z. Each horse wears a
leather saddle on a coloured blanket and a bridle, so it reads as rideable.
The saddle seat sits at y = 1.56 m (data/horses.json "saddle_height").
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from sdf_model import Model, cone, ell, mirror, fbm  # noqa: E402
from build_creatures import legs, leg_parts, shade, OUT  # noqa: E402

HOOF = (0.10, 0.09, 0.08)
LEATHER = (0.30, 0.17, 0.08)
METAL = (0.62, 0.60, 0.56)
EYE = (0.04, 0.03, 0.03)

COATS = {
    # name: coat, mane/tail, lower leg, blanket, muzzle
    "HorseWhite": ((0.86, 0.85, 0.82), (0.93, 0.92, 0.88), (0.82, 0.81, 0.78), (0.20, 0.32, 0.62), (0.55, 0.50, 0.50)),
    "HorseBlack": ((0.075, 0.07, 0.075), (0.04, 0.04, 0.045), (0.06, 0.06, 0.065), (0.62, 0.12, 0.10), (0.10, 0.09, 0.09)),
    "HorseBrown": ((0.25, 0.13, 0.06), (0.05, 0.04, 0.035), (0.07, 0.05, 0.04), (0.20, 0.45, 0.22), (0.14, 0.09, 0.06)),
}


def horse(name):
    coat, mane, low, blanket, muzzle = COATS[name]
    front = [(0.16, 1.22, -0.60), (0.16, 0.92, -0.62), (0.16, 0.50, -0.60), (0.16, 0.15, -0.62)]
    hind = [(0.18, 1.24, 0.60), (0.18, 0.92, 0.50), (0.18, 0.55, 0.74), (0.18, 0.15, 0.70)]
    bones = [("Hips", None, (0, 1.30, 0.55)), ("Spine", "Hips", (0, 1.30, 0.0)),
             ("Chest", "Spine", (0, 1.32, -0.55)), ("Neck", "Chest", (0, 1.45, -0.80)),
             ("Head", "Neck", (0, 1.95, -1.12)), ("Tail", "Hips", (0, 1.40, 0.86))] + legs(front, hind)
    side = []
    side += leg_parts(front, [0.085, 0.06, 0.042, 0.04], [coat, coat, low], ((0.15, 1.08, -0.58), (0.10, 0.26, 0.15)))
    side += leg_parts(hind, [0.10, 0.075, 0.045, 0.04], [coat, coat, low], ((0.16, 1.05, 0.58), (0.12, 0.30, 0.24)))
    side += [
        # Hooves and fetlock feathering.
        cone(front[3], (0.16, 0.02, -0.65), 0.05, 0.065, "F4_L", HOOF, 0.015, tag="hoof"),
        cone(hind[3], (0.18, 0.02, 0.73), 0.05, 0.065, "H4_L", HOOF, 0.015, tag="hoof"),
        # Ears, eyes.
        cone((0.055, 2.02, -1.07), (0.075, 2.18, -1.05), 0.035, 0.008, "Head", coat, 0.02),
        ell((0.098, 1.93, -1.20), (0.022, 0.024, 0.026), "Head", EYE, 0.004, tag="eye"),
        ell((0.05, 1.60, -1.48), (0.02, 0.02, 0.012), "Head", EYE, 0.004, tag="eye"),   # nostril
        # Bridle: cheek strap, noseband ring and bit ring.
        cone((0.105, 2.0, -1.10), (0.09, 1.70, -1.33), 0.012, 0.012, "Head", LEATHER, 0.003, tag="tack"),
        ell((0.085, 1.68, -1.36), (0.016, 0.016, 0.016), "Head", METAL, 0.002, tag="metal"),
        # Stirrup leathers and irons hanging from the saddle.
        cone((0.30, 1.50, -0.08), (0.36, 1.12, -0.06), 0.014, 0.014, "Spine", LEATHER, 0.002, tag="tack"),
        ell((0.36, 1.08, -0.06), (0.012, 0.045, 0.05), "Spine", METAL, 0.002, tag="metal"),
    ]
    parts = mirror(side) + [
        # Body: barrel, deep chest, round rump, withers.
        ell((0, 1.14, 0.0), (0.30, 0.34, 0.66), "Spine", coat, 0.10),
        ell((0, 1.16, -0.52), (0.28, 0.36, 0.30), "Chest", coat, 0.10),
        ell((0, 1.20, 0.55), (0.30, 0.33, 0.32), "Hips", coat, 0.10),
        ell((0, 1.42, -0.45), (0.13, 0.12, 0.24), "Chest", coat, 0.08),
        # Neck: thick at the base, crested on top.
        cone((0, 1.25, -0.66), (0, 1.86, -1.04), 0.25, 0.13, "Neck", coat, 0.08),
        ell((0, 1.62, -0.86), (0.11, 0.26, 0.16), "Neck", coat, 0.07),
        # Head: skull, long face, soft muzzle.
        ell((0, 1.94, -1.13), (0.11, 0.12, 0.14), "Head", coat, 0.05),
        cone((0, 1.88, -1.18), (0, 1.63, -1.44), 0.10, 0.072, "Head", coat, 0.05),
        ell((0, 1.60, -1.46), (0.078, 0.075, 0.07), "Head", muzzle, 0.03),
        # Mane down the crest, forelock, and a long tail.
        cone((0, 2.05, -1.07), (0, 1.50, -0.60), 0.045, 0.06, "Neck", mane, 0.03, fur=0.03, tag="mane"),
        cone((0, 2.06, -1.12), (0, 1.94, -1.24), 0.035, 0.025, "Head", mane, 0.02, fur=0.02, tag="mane"),
        cone((0, 1.40, 0.86), (0, 1.15, 1.02), 0.075, 0.085, "Tail", mane, 0.04, fur=0.025, tag="mane"),
        cone((0, 1.15, 1.02), (0, 0.62, 1.05), 0.085, 0.07, "Tail", mane, 0.04, fur=0.035, tag="mane"),
        # Saddle blanket, saddle seat with pommel and cantle, girth.
        ell((0, 1.47, -0.08), (0.33, 0.04, 0.36), "Spine", blanket, 0.01, tag="blanket"),
        ell((0, 1.52, -0.08), (0.24, 0.05, 0.27), "Spine", LEATHER, 0.02, tag="tack"),
        ell((0, 1.60, -0.30), (0.10, 0.06, 0.05), "Spine", LEATHER, 0.02, tag="tack"),
        ell((0, 1.60, 0.14), (0.15, 0.05, 0.05), "Spine", LEATHER, 0.02, tag="tack"),
    ]
    # Girth strap around the belly, just behind the front legs.
    for a in np.linspace(-1.5, 1.5, 9):
        parts.append(ell((0.315 * np.sin(a), 1.15 - 0.355 * np.cos(a), -0.22), (0.04, 0.04, 0.03), "Spine", LEATHER, 0.0, tag="tack"))
    m = Model(name, bones, parts, voxel=0.016, tris=8000, fur_freq=55)

    def col(v, n, pd, c):
        c = shade(c, v, n, belly=None, mottle=0.05, freq=6, seed=11)
        # A soft sheen along the back and dappling on the white horse.
        if name == "HorseWhite":
            dap = fbm(v, 14.0, 2, 4)
            c = c * (0.93 + 0.1 * dap)[:, None]
        hair = np.array([p.tag == "mane" for p in m.parts])
        on_hair = pd[:, hair].min(1) < 0.012
        streak = 0.85 + 0.3 * fbm(v[on_hair] * np.array([4.0, 1.0, 4.0]), 30, 2, 7)
        c[on_hair] = np.array(mane) * streak[:, None]
        for tag, rgb in (("tack", LEATHER), ("metal", METAL), ("blanket", blanket), ("hoof", HOOF), ("eye", EYE)):
            sel = np.array([p.tag == tag for p in m.parts])
            if sel.any():
                near = pd[:, sel].min(1) < (0.006 if tag != "hoof" else 0.01)
                if tag == "hoof":
                    near &= v[:, 1] < 0.12
                c[near] = np.array(rgb) * (0.9 + 0.2 * fbm(v[near], 50, 2, 3))[:, None]
        return np.clip(c, 0, 1)
    m.color_fn = col
    return m


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    only = sys.argv[1:]
    for name in COATS:
        if only and name not in only:
            continue
        m = horse(name)
        nv, nf = m.build(OUT / f"{name}.glb")
        print(f"{name}: {nv} verts, {nf} tris")


if __name__ == "__main__":
    main()
