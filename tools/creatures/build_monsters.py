#!/usr/bin/env python3
"""Builds the biome monsters from the Gemini concept sheet as skinned .glb files
in game/assets/creatures/:

* IceTroll      - Frost Peaks: hulking pale-blue troll with ice crystals.
* FrostSpirit   - Frost Peaks: gaunt floating wraith that trails into mist.
* LavaGolem     - Ember Wastes: basalt boulders held together by glowing cracks.
* FireSalamander- Ember Wastes: small black lizard with molten spots.
* MushroomBeetle- Glow Hollow: rhino beetle with glowing spots and mushrooms on its back.

Author: Claude (Openworld). Run from the repo root:
    python3 tools/creatures/build_monsters.py [Name ...]

Skeleton conventions (all face -Z):
* Bipeds: Hips > Spine > Chest > Neck > Head; legs L1..L3 under Hips;
  arms A1..A3 under Chest (_L / _R).
* Quadrupeds and the six-legged beetle reuse build_creatures.legs():
  F1..F4 front, M1..M4 middle (beetle only), H1..H4 hind.
Glow (vertex alpha) drives emission in the game's creature shader.
"""
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).parent))
from sdf_model import Model, cone, ell, mirror, fbm  # noqa: E402
from build_creatures import legs, OUT  # noqa: E402


def spine(hips, sp, chest, neck, head):
    return [("Hips", None, hips), ("Spine", "Hips", sp), ("Chest", "Spine", chest),
            ("Neck", "Chest", neck), ("Head", "Neck", head)]


def limbs(arm, leg):
    """Biped arm/leg bones from left-side joint lists (3 joints each)."""
    bones = []
    for side, sx in (("_L", 1), ("_R", -1)):
        prev = "Chest"
        for i, (x, y, z) in enumerate(arm):
            bones.append((f"A{i + 1}{side}", prev, (x * sx, y, z)))
            prev = f"A{i + 1}{side}"
        prev = "Hips"
        for i, (x, y, z) in enumerate(leg):
            bones.append((f"L{i + 1}{side}", prev, (x * sx, y, z)))
            prev = f"L{i + 1}{side}"
    return bones


def mottle(c, v, amt, freq, seed):
    return c * (1 - amt + 2 * amt * fbm(v, freq, 3, seed))[:, None]


# ---------------------------------------------------------------- ice troll

def ice_troll():
    SKIN = (0.50, 0.53, 0.57)
    DARK = (0.31, 0.34, 0.39)
    ICE = (0.70, 0.90, 1.00)
    CLOTH = (0.40, 0.31, 0.22)
    arm = [(0.44, 1.95, 0.02), (0.64, 1.45, 0.02), (0.72, 0.95, -0.10)]
    leg = [(0.22, 1.10, 0.0), (0.26, 0.60, -0.06), (0.26, 0.12, 0.02)]
    bones = spine((0, 1.15, 0), (0, 1.42, 0.02), (0, 1.76, 0.05), (0, 2.08, -0.06), (0, 2.18, -0.18)) + limbs(arm, leg)
    side = [
        ell((0.44, 1.95, 0.04), (0.21, 0.21, 0.21), "A1_L", SKIN, 0.08, fur=0.006),
        cone(arm[0], arm[1], 0.17, 0.13, "A1_L", SKIN, 0.06, fur=0.006),
        cone(arm[1], arm[2], 0.16, 0.12, "A2_L", SKIN, 0.05, fur=0.006),
        ell((0.73, 0.84, -0.12), (0.13, 0.15, 0.13), "A3_L", DARK, 0.04),
        cone(leg[0], leg[1], 0.18, 0.13, "L1_L", SKIN, 0.06, fur=0.006),
        cone(leg[1], leg[2], 0.13, 0.11, "L2_L", SKIN, 0.05, fur=0.006),
        ell((0.27, 0.08, -0.07), (0.13, 0.08, 0.21), "L3_L", DARK, 0.04),
        ell((0.065, 2.21, -0.345), (0.026, 0.016, 0.014), "Head", ICE, 0.004, glow=1.0),
        cone((0.07, 2.06, -0.36), (0.08, 2.15, -0.38), 0.022, 0.004, "Head", (0.9, 0.92, 0.88), 0.004),
        # Ice crystals: shoulders, back and forearms.
        cone((0.48, 2.10, 0.06), (0.62, 2.42, 0.10), 0.07, 0.0, "A1_L", ICE, 0.01, tag="ice", glow=0.25),
        cone((0.38, 2.12, 0.12), (0.42, 2.45, 0.24), 0.06, 0.0, "A1_L", ICE, 0.01, tag="ice", glow=0.25),
        cone((0.56, 2.04, -0.06), (0.78, 2.26, -0.10), 0.05, 0.0, "A1_L", ICE, 0.01, tag="ice", glow=0.25),
        cone((0.20, 1.95, 0.30), (0.30, 2.25, 0.50), 0.06, 0.0, "Chest", ICE, 0.01, tag="ice", glow=0.25),
        cone((0.12, 1.70, 0.36), (0.20, 1.95, 0.62), 0.05, 0.0, "Chest", ICE, 0.01, tag="ice", glow=0.25),
        cone((0.70, 1.25, 0.06), (0.86, 1.36, 0.18), 0.045, 0.0, "A2_L", ICE, 0.01, tag="ice", glow=0.25),
        cone((0.68, 1.12, 0.08), (0.80, 1.16, 0.25), 0.04, 0.0, "A2_L", ICE, 0.01, tag="ice", glow=0.25),
    ]
    parts = mirror(side) + [
        ell((0, 1.15, 0.0), (0.32, 0.25, 0.25), "Hips", SKIN, 0.08),
        ell((0, 1.42, -0.06), (0.38, 0.32, 0.30), "Spine", SKIN, 0.10, fur=0.005),
        ell((0, 1.78, 0.05), (0.48, 0.36, 0.34), "Chest", SKIN, 0.10, fur=0.006),
        ell((0, 2.0, 0.10), (0.34, 0.15, 0.22), "Chest", SKIN, 0.08),
        ell((0, 2.2, -0.2), (0.16, 0.17, 0.17), "Head", SKIN, 0.06),
        ell((0, 2.08, -0.28), (0.16, 0.09, 0.11), "Head", SKIN, 0.05),
        ell((0, 2.27, -0.33), (0.16, 0.045, 0.06), "Head", DARK, 0.04),
        ell((0, 2.16, -0.37), (0.05, 0.05, 0.05), "Head", DARK, 0.03),
        ell((0, 2.05, -0.375), (0.085, 0.022, 0.025), "Head", (0.12, 0.14, 0.2), 0.01),
        ell((0, 0.98, -0.02), (0.36, 0.20, 0.29), "Hips", CLOTH, 0.015, fur=0.01, tag="cloth"),
        ell((0, 0.84, -0.27), (0.22, 0.16, 0.035), "Hips", CLOTH, 0.01, fur=0.008, tag="cloth"),
    ]
    m = Model("IceTroll", bones, parts, voxel=0.02, tris=7500, fur_freq=30, seed=4)
    m.color_fn = lambda v, n, pd, c: mottle(c, v, 0.12, 6, 4) * (1 - 0.18 * np.clip(-n[:, 1], 0, 1))[:, None]
    return m


# ---------------------------------------------------------------- frost spirit

def frost_spirit():
    PALE = (0.86, 0.92, 0.98)
    BLUE = (0.62, 0.76, 0.92)
    arm = [(0.22, 1.66, 0.0), (0.42, 1.38, -0.08), (0.55, 1.12, -0.18)]
    bones = spine((0, 1.1, 0), (0, 1.32, 0), (0, 1.55, 0), (0, 1.76, -0.02), (0, 1.86, -0.05)) + [
        b for b in limbs(arm, [(0.1, 1.0, 0), (0.1, 0.6, 0), (0.1, 0.3, 0)]) if b[0].startswith("A")] + [
        ("Tail", "Hips", (0, 0.95, 0.05))]
    side = [
        cone(arm[0], arm[1], 0.055, 0.04, "A1_L", PALE, 0.04, fur=0.012),
        cone(arm[1], arm[2], 0.04, 0.025, "A2_L", PALE, 0.03, fur=0.012),
        cone(arm[2], (0.60, 0.95, -0.24), 0.025, 0.006, "A3_L", BLUE, 0.02),
        cone(arm[2], (0.66, 1.0, -0.20), 0.02, 0.004, "A3_L", BLUE, 0.015),
        cone(arm[2], (0.52, 0.96, -0.26), 0.02, 0.004, "A3_L", BLUE, 0.015),
        ell((0.04, 1.88, -0.15), (0.022, 0.016, 0.012), "Head", (0.85, 0.97, 1.0), 0.004, glow=1.0),
    ]
    parts = mirror(side) + [
        cone((0, 1.1, 0), (0, 1.55, 0), 0.13, 0.17, "Spine", PALE, 0.06, fur=0.02),
        ell((0, 1.6, 0), (0.2, 0.1, 0.11), "Chest", PALE, 0.06, fur=0.02),
        cone((0, 1.62, 0), (0, 1.8, -0.03), 0.06, 0.05, "Neck", PALE, 0.04, fur=0.015),
        ell((0, 1.9, -0.06), (0.09, 0.115, 0.1), "Head", PALE, 0.04, fur=0.006),
        ell((0, 1.84, -0.12), (0.06, 0.05, 0.06), "Head", PALE, 0.03),
        ell((0, 1.82, -0.155), (0.035, 0.022, 0.012), "Head", (0.2, 0.3, 0.45), 0.008),
        # Lower body unravels into a curling trail of mist.
        cone((0, 1.1, 0), (0.06, 0.75, 0.10), 0.13, 0.09, "Tail", BLUE, 0.06, fur=0.03),
        cone((0.06, 0.75, 0.10), (-0.08, 0.42, 0.22), 0.09, 0.05, "Tail", BLUE, 0.05, fur=0.03),
        cone((-0.08, 0.42, 0.22), (0.05, 0.18, 0.36), 0.05, 0.01, "Tail", BLUE, 0.04, fur=0.025),
    ]
    m = Model("FrostSpirit", bones, parts, voxel=0.012, tris=5000, fur_freq=28, seed=8)
    m.glow_fn = lambda v, n, pd: 0.35 + 0.25 * fbm(v, 5, 2, 3)
    return m


# ---------------------------------------------------------------- lava golem

def lava_golem():
    ROCK = (0.20, 0.17, 0.16)
    ROCK2 = (0.27, 0.23, 0.21)
    LAVA = (1.0, 0.45, 0.08)
    arm = [(0.46, 1.86, 0.02), (0.62, 1.38, 0.04), (0.68, 0.92, -0.06)]
    leg = [(0.24, 1.0, 0.0), (0.28, 0.55, -0.04), (0.28, 0.12, 0.02)]
    bones = spine((0, 1.05, 0), (0, 1.35, 0.0), (0, 1.7, 0.02), (0, 2.0, -0.04), (0, 2.08, -0.12)) + limbs(arm, leg)
    rng = np.random.default_rng(5)
    side = [
        ell((0.48, 1.9, 0.03), (0.24, 0.2, 0.22), "A1_L", ROCK, 0.035, fur=0.01),
        ell((0.55, 1.62, 0.03), (0.16, 0.2, 0.15), "A1_L", ROCK2, 0.035, fur=0.01),
        ell((0.64, 1.25, 0.02), (0.16, 0.22, 0.16), "A2_L", ROCK, 0.035, fur=0.01),
        ell((0.69, 0.86, -0.07), (0.19, 0.19, 0.18), "A3_L", ROCK2, 0.035, fur=0.01),
        ell((0.25, 0.8, -0.02), (0.18, 0.26, 0.18), "L1_L", ROCK, 0.035, fur=0.01),
        ell((0.28, 0.36, -0.02), (0.15, 0.24, 0.15), "L2_L", ROCK2, 0.035, fur=0.01),
        ell((0.29, 0.09, -0.08), (0.17, 0.1, 0.22), "L3_L", ROCK, 0.035, fur=0.01),
        ell((0.07, 2.08, -0.25), (0.035, 0.025, 0.02), "Head", LAVA, 0.004, glow=1.0),
    ]
    for i in range(5):   # extra boulders crusted on the shoulders and back
        c = (0.2 + rng.random() * 0.3, 1.6 + rng.random() * 0.4, 0.1 + rng.random() * 0.2)
        side.append(ell(c, tuple(0.08 + rng.random(3) * 0.08), "Chest" if c[0] < 0.35 else "A1_L", ROCK2, 0.01, fur=0.012))
    parts = mirror(side) + [
        ell((0, 1.05, 0.0), (0.3, 0.22, 0.22), "Hips", ROCK, 0.04, fur=0.01),
        ell((0, 1.36, 0.0), (0.32, 0.24, 0.24), "Spine", ROCK2, 0.04, fur=0.01),
        ell((0, 1.72, 0.03), (0.44, 0.32, 0.3), "Chest", ROCK, 0.04, fur=0.012),
        ell((0, 1.7, -0.27), (0.12, 0.12, 0.06), "Chest", LAVA, 0.03, glow=1.0, tag="core"),
        ell((0, 2.08, -0.13), (0.17, 0.15, 0.16), "Head", ROCK2, 0.04, fur=0.01),
        ell((0, 1.98, -0.27), (0.08, 0.025, 0.02), "Head", LAVA, 0.006, glow=1.0),
    ]
    m = Model("LavaGolem", bones, parts, voxel=0.018, tris=7500, fur_freq=14, seed=6)

    def glow(v, n, pd):
        # Thin molten veins: where a low-frequency noise crosses 0.5.
        g = 1.0 - np.clip(np.abs(fbm(v, 5, 2, 21) - 0.5) / 0.018, 0, 1)
        return g * 0.95

    def col(v, n, pd, c):
        c = mottle(c, v, 0.18, 9, 6)
        g = glow(v, n, pd)[:, None]
        return c * (1 - g) + np.array(LAVA) * g
    m.glow_fn = glow
    m.color_fn = col
    return m


# ---------------------------------------------------------------- fire salamander

def fire_salamander():
    BLACK = (0.10, 0.07, 0.06)
    BELLY = (0.35, 0.12, 0.05)
    EMBER = (1.0, 0.42, 0.06)
    front = [(0.07, 0.18, -0.15), (0.15, 0.15, -0.16), (0.18, 0.05, -0.17), (0.19, 0.01, -0.21)]
    hind = [(0.07, 0.18, 0.15), (0.15, 0.15, 0.17), (0.18, 0.05, 0.18), (0.20, 0.01, 0.16)]
    bones = spine((0, 0.18, 0.15), (0, 0.19, 0.0), (0, 0.19, -0.15), (0, 0.2, -0.25), (0, 0.21, -0.31)) + [
        ("Tail", "Hips", (0, 0.18, 0.25))] + legs(front, hind)
    side = []
    for tag, pts in (("F", front), ("H", hind)):
        for i in range(3):
            side.append(cone(pts[i], pts[i + 1], 0.03 - i * 0.005, 0.025 - i * 0.005, f"{tag}{i + 1}_L", BLACK, 0.02))
        side.append(ell((pts[3][0] + 0.01, 0.01, pts[3][2] - 0.02), (0.03, 0.01, 0.03), f"{tag}4_L", BLACK, 0.015))
    side.append(ell((0.045, 0.235, -0.36), (0.014, 0.012, 0.012), "Head", (0.9, 0.7, 0.2), 0.003, glow=0.8))
    parts = mirror(side) + [
        ell((0, 0.18, 0.0), (0.085, 0.06, 0.25), "Spine", BLACK, 0.04),
        ell((0, 0.19, -0.16), (0.08, 0.06, 0.1), "Chest", BLACK, 0.04),
        cone((0, 0.2, -0.22), (0, 0.205, -0.3), 0.055, 0.05, "Neck", BLACK, 0.03),
        ell((0, 0.21, -0.34), (0.065, 0.04, 0.08), "Head", BLACK, 0.03),
        cone((0, 0.18, 0.2), (0.03, 0.15, 0.45), 0.06, 0.03, "Tail", BLACK, 0.04),
        cone((0.03, 0.15, 0.45), (-0.02, 0.13, 0.66), 0.03, 0.008, "Tail", BLACK, 0.03),
    ]
    m = Model("FireSalamander", bones, parts, voxel=0.007, tris=4000, seed=12)

    def glow(v, n, pd):
        spots = np.clip((fbm(v, 30, 2, 31) - 0.6) / 0.06, 0, 1)
        back = np.clip(n[:, 1], 0, 1)
        return spots * back

    def col(v, n, pd, c):
        down = np.clip(-n[:, 1], 0, 1)[:, None]
        c = c * (1 - down) + np.array(BELLY) * down
        g = glow(v, n, pd)[:, None]
        return c * (1 - g) + np.array(EMBER) * g
    m.glow_fn = glow
    m.color_fn = col
    return m


# ---------------------------------------------------------------- mushroom beetle

def mushroom_beetle():
    SHELL = (0.10, 0.12, 0.22)
    LEG = (0.07, 0.07, 0.10)
    HORN = (0.16, 0.12, 0.10)
    CAP = (0.62, 0.80, 0.92)
    STEM = (0.82, 0.86, 0.88)
    CYAN = (0.35, 0.95, 1.0)
    front = [(0.15, 0.38, -0.32), (0.32, 0.42, -0.42), (0.42, 0.2, -0.5), (0.46, 0.01, -0.55)]
    mid = [(0.17, 0.36, 0.0), (0.37, 0.41, 0.02), (0.48, 0.19, 0.05), (0.52, 0.01, 0.06)]
    hind = [(0.15, 0.36, 0.25), (0.34, 0.41, 0.36), (0.44, 0.19, 0.48), (0.48, 0.01, 0.56)]
    bones = spine((0, 0.46, 0.25), (0, 0.48, 0.0), (0, 0.46, -0.3), (0, 0.43, -0.42), (0, 0.42, -0.5)) + legs(front, hind)
    for side_tag, sx in (("_L", 1), ("_R", -1)):
        prev = "Spine"
        for i, (x, y, z) in enumerate(mid):
            bones.append((f"M{i + 1}{side_tag}", prev, (x * sx, y, z)))
            prev = f"M{i + 1}{side_tag}"
    side = []
    for tag, pts in (("F", front), ("M", mid), ("H", hind)):
        for i in range(3):
            side.append(cone(pts[i], pts[i + 1], 0.06 - i * 0.012, 0.05 - i * 0.012, f"{tag}{i + 1}_L", LEG, 0.015))
    side.append(ell((0.09, 0.45, -0.6), (0.025, 0.02, 0.02), "Head", (0.05, 0.05, 0.05), 0.004))
    mush = [(0.12, 0.74, 0.0, 0.11), (-0.06, 0.76, 0.18, 0.14), (0.02, 0.72, -0.16, 0.08), (-0.16, 0.70, -0.02, 0.07), (0.17, 0.68, 0.24, 0.06)]
    caps = []
    for (x, y, z, r) in mush:
        caps.append(cone((x, y - 0.12, z), (x, y + r * 0.6, z), r * 0.28, r * 0.22, "Spine", STEM, 0.02, tag="stem", glow=0.2))
        caps.append(ell((x, y + r * 0.7, z), (r, r * 0.42, r), "Spine", CAP, 0.01, tag="cap", glow=0.55))
    parts = mirror(side) + caps + [
        ell((0, 0.52, 0.1), (0.38, 0.26, 0.52), "Spine", SHELL, 0.03, tag="shell"),
        ell((0, 0.47, -0.37), (0.30, 0.2, 0.18), "Chest", SHELL, 0.03, tag="shell"),
        ell((0, 0.41, -0.55), (0.13, 0.1, 0.1), "Head", SHELL, 0.03),
        cone((0, 0.42, -0.6), (0, 0.58, -0.86), 0.06, 0.035, "Head", HORN, 0.02),
        cone((0, 0.58, -0.86), (0, 0.78, -0.90), 0.035, 0.008, "Head", HORN, 0.015),
        cone((0, 0.6, -0.42), (0, 0.66, -0.68), 0.05, 0.01, "Chest", HORN, 0.02),
    ]
    m = Model("MushroomBeetle", bones, parts, voxel=0.012, tris=8000, seed=14)
    shell = np.array([p.tag == "shell" for p in m.parts])
    capm = np.array([p.tag == "cap" for p in m.parts])

    def glow(v, n, pd):
        on_shell = pd[:, shell].min(1) < 0.01
        spots = np.clip((fbm(v, 22, 1, 41) - 0.62) / 0.05, 0, 1)
        return spots * on_shell * (n[:, 1] > -0.2)

    def col(v, n, pd, c):
        g = glow(v, n, pd)[:, None]
        c = c * (1 - g) + np.array(CYAN) * g
        under = (pd[:, capm].min(1) < 0.01) & (n[:, 1] < -0.3)
        c[under] = CYAN   # glowing gills under the caps
        return c
    m.glow_fn = lambda v, n, pd: np.maximum(glow(v, n, pd), ((pd[:, capm].min(1) < 0.01) & (n[:, 1] < -0.3)) * 0.9)
    m.color_fn = col
    return m


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    only = sys.argv[1:]
    for fn in (ice_troll, frost_spirit, lava_golem, fire_salamander, mushroom_beetle):
        m = fn()
        if only and m.name not in only:
            continue
        nv, nf = m.build(OUT / f"{m.name}.glb")
        print(f"{m.name}: {nv} verts, {nf} tris")


if __name__ == "__main__":
    main()
