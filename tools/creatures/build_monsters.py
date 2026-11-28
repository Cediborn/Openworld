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
from sdf_model import Model, box, cone, ell, eye, mirror, fbm  # noqa: E402
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
        ell((0.065, 2.21, -0.345), (0.026, 0.016, 0.014), "Head", ICE, 0.004, glow=1.0, gloss=1.0),
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
        # Two ivory tusks from the underbite.
        cone((0.065, 2.03, -0.37), (0.09, 2.15, -0.41), 0.022, 0.006, "Head", (0.86, 0.84, 0.76), 0.006, gloss=0.5),
        cone((-0.065, 2.03, -0.37), (-0.09, 2.15, -0.41), 0.022, 0.006, "Head", (0.86, 0.84, 0.76), 0.006, gloss=0.5),
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
    """Basalt slabs and boulders stacked into a hunched giant: huge shoulders and
    fists, a small head sunk under a heavy brow with glowing eye slits, obsidian
    shards on the back, and lava glowing in every seam between the plates."""
    ROCK = (0.17, 0.15, 0.14)
    ROCK2 = (0.24, 0.21, 0.19)
    OBSIDIAN = (0.05, 0.045, 0.06)
    LAVA = (1.0, 0.45, 0.08)
    arm = [(0.46, 1.86, 0.02), (0.62, 1.38, 0.04), (0.68, 0.92, -0.06)]
    leg = [(0.24, 1.0, 0.0), (0.28, 0.55, -0.04), (0.28, 0.12, 0.02)]
    bones = spine((0, 1.05, 0), (0, 1.35, 0.0), (0, 1.7, 0.02), (0, 2.0, -0.04), (0, 2.08, -0.12)) + limbs(arm, leg)
    F = 0.013   # rock grain (noise displacement)
    side = [
        # Shoulder boulders and plates.
        box((0.5, 1.93, 0.03), (0.21, 0.17, 0.2), (0.3, 0.4, 0.5), 0.06, "A1_L", ROCK2, 0.015, fur=F),
        box((0.63, 1.8, 0.06), (0.12, 0.15, 0.17), (0.1, 0.2, 0.9), 0.04, "A1_L", ROCK, 0.012, fur=F),
        # Upper arm, elbow, a forearm that widens into a boulder fist with knuckles.
        box((0.57, 1.6, 0.03), (0.12, 0.18, 0.12), (0.0, 0.0, 0.25), 0.04, "A1_L", ROCK, 0.012, fur=F),
        ell((0.63, 1.38, 0.04), (0.12, 0.1, 0.12), "A2_L", ROCK2, 0.012, fur=F),
        box((0.66, 1.15, 0.0), (0.15, 0.2, 0.15), (0.05, 0.2, 0.08), 0.045, "A2_L", ROCK, 0.012, fur=F),
        box((0.68, 0.99, -0.03), (0.18, 0.09, 0.18), (0.0, 0.5, 0.0), 0.04, "A2_L", ROCK2, 0.01, fur=F),
        box((0.69, 0.84, -0.08), (0.16, 0.11, 0.15), (0.1, 0.3, 0.0), 0.05, "A3_L", ROCK, 0.012, fur=F),
        box((0.62, 0.87, -0.22), (0.035, 0.045, 0.045), (0.2, 0.0, 0.1), 0.015, "A3_L", ROCK2, 0.006),
        box((0.69, 0.87, -0.23), (0.035, 0.045, 0.045), (0.2, 0.1, 0.0), 0.015, "A3_L", ROCK2, 0.006),
        box((0.76, 0.86, -0.21), (0.035, 0.045, 0.045), (0.2, 0.3, -0.1), 0.015, "A3_L", ROCK2, 0.006),
        # Thick pillar legs on wide feet with two toe slabs.
        box((0.25, 0.8, -0.01), (0.15, 0.22, 0.16), (0.0, 0.0, 0.06), 0.05, "L1_L", ROCK2, 0.012, fur=F),
        ell((0.28, 0.55, -0.07), (0.12, 0.1, 0.11), "L2_L", ROCK, 0.012, fur=F),
        box((0.28, 0.34, -0.01), (0.13, 0.19, 0.14), (0.05, 0.0, 0.0), 0.045, "L2_L", ROCK2, 0.012, fur=F),
        box((0.29, 0.08, -0.06), (0.17, 0.08, 0.22), (0.0, 0.1, 0.0), 0.04, "L3_L", ROCK, 0.012, fur=F),
        box((0.22, 0.06, -0.3), (0.06, 0.05, 0.07), (0.0, 0.15, 0.0), 0.02, "L3_L", ROCK2, 0.006),
        box((0.35, 0.06, -0.29), (0.06, 0.05, 0.07), (0.0, -0.1, 0.0), 0.02, "L3_L", ROCK2, 0.006),
        # Chest plates.
        box((0.2, 1.78, -0.24), (0.18, 0.15, 0.07), (0.25, 0.2, 0.1), 0.04, "Chest", ROCK2, 0.012, fur=F),
        # Eye slit under the brow.
        ell((0.068, 2.12, -0.385), (0.045, 0.018, 0.025), "Head", LAVA, 0.003, glow=1.0, tag="core"),
    ]
    # Obsidian shards breaking out of the back, glossy black.
    for i, (x, y, z, tx, ty, tz, r) in enumerate([(0.12, 1.98, 0.22, 0.22, 2.42, 0.42, 0.075), (0.26, 1.88, 0.24, 0.42, 2.22, 0.46, 0.06), (0.06, 1.72, 0.3, 0.12, 2.02, 0.6, 0.055)]):
        side.append(cone((x, y, z), (tx, ty, tz), r, 0.008, "Chest", OBSIDIAN, 0.01, gloss=0.8, tag="shard"))
    parts = mirror(side) + [
        box((0, 1.03, 0.0), (0.3, 0.16, 0.2), (0.05, 0.0, 0.0), 0.05, "Hips", ROCK, 0.012, fur=F),
        box((0, 1.28, 0.0), (0.27, 0.13, 0.2), (0.1, 0.15, 0.04), 0.045, "Spine", ROCK2, 0.012, fur=F),
        box((0, 1.45, -0.02), (0.3, 0.1, 0.21), (-0.08, -0.1, 0.0), 0.04, "Spine", ROCK, 0.012, fur=F),
        box((0, 1.75, 0.03), (0.44, 0.25, 0.27), (0.12, 0.0, 0.0), 0.07, "Chest", ROCK, 0.015, fur=F),
        box((0, 1.92, 0.2), (0.31, 0.15, 0.18), (-0.4, 0.0, 0.0), 0.05, "Chest", ROCK2, 0.012, fur=F),
        ell((0, 1.72, -0.29), (0.09, 0.15, 0.05), "Chest", LAVA, 0.01, glow=1.0, tag="core"),
        # Head: small block, overhanging brow, jaw.
        box((0, 2.1, -0.24), (0.15, 0.13, 0.15), (0.1, 0.0, 0.0), 0.04, "Head", ROCK2, 0.012, fur=F),
        box((0, 2.19, -0.35), (0.18, 0.045, 0.07), (-0.3, 0.0, 0.0), 0.02, "Head", ROCK, 0.008, fur=F),
        box((0, 2.0, -0.34), (0.12, 0.05, 0.07), (0.2, 0.0, 0.0), 0.02, "Head", ROCK, 0.008, fur=F),
    ]
    m = Model("LavaGolem", bones, parts, voxel=0.014, tris=10000, fur_freq=11, seed=6)
    rock = np.array([p.tag == "" for p in m.parts])

    def glow(v, n, pd):
        # Lava shows in the seams where two rock plates meet, and in thin veins.
        rd = np.sort(pd[:, rock], 1)
        seam = np.clip(1.0 - (rd[:, 1] - rd[:, 0]) / 0.005, 0, 1) * (rd[:, 0] < 0.004)
        veins = 1.0 - np.clip(np.abs(fbm(v, 3, 2, 21) - 0.5) / 0.006, 0, 1)
        return np.maximum(seam, veins * 0.6)

    def col(v, n, pd, c):
        c = mottle(c, v, 0.2, 7, 6)
        # Grey ash settles on upward faces.
        ash = np.clip(n[:, 1] - 0.55, 0, 1)[:, None] * 1.4
        c = c * (1 - ash) + np.array([0.42, 0.4, 0.38]) * ash
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
    side.append(ell((0.045, 0.235, -0.36), (0.014, 0.012, 0.012), "Head", (0.9, 0.7, 0.2), 0.003, glow=0.8, gloss=1.0))
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
    """A rhino beetle the size of a pony: split, ridged wing cases with two rows
    of glowing spots, a glossy pronotum with its own short horn, a long curved
    head horn with a forked tip, compound eyes, mandibles, clubbed antennae and
    jointed, spined legs ending in hooked feet. Glowing mushrooms sprout from
    the back (it lives in Glow Hollow)."""
    SHELL = (0.10, 0.19, 0.30)
    UNDER = (0.08, 0.07, 0.09)
    LEG = (0.12, 0.08, 0.06)
    HORN = (0.13, 0.09, 0.07)
    CAP = (0.62, 0.80, 0.92)
    STEM = (0.82, 0.86, 0.88)
    CYAN = (0.35, 0.95, 1.0)
    EYE = (0.32, 0.08, 0.05)
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
        p0, p1, p2, p3 = [np.asarray(q, float) for q in pts]
        side.append(ell(tuple(p0), (0.06, 0.05, 0.06), f"{tag}1_L", LEG, 0.01, gloss=0.5))                     # coxa
        side.append(cone(tuple(p0), tuple(p1), 0.05, 0.045, f"{tag}1_L", LEG, 0.01, gloss=0.5))                # femur
        side.append(cone(tuple(p1), tuple(p2), 0.038, 0.026, f"{tag}2_L", LEG, 0.008, gloss=0.5))              # tibia
        for k in (0.35, 0.6, 0.85):   # spines along the tibia
            q = p1 + (p2 - p1) * k
            side.append(cone(tuple(q), tuple(q + np.array([0.05, -0.02, 0.0])), 0.009, 0.002, f"{tag}2_L", LEG, 0.003, gloss=0.5))
        for k in range(3):            # tarsus segments and the claw
            a_ = p2 + (p3 - p2) * (k / 3.0)
            b_ = p2 + (p3 - p2) * ((k + 1) / 3.0)
            side.append(cone(tuple(a_), tuple(b_), 0.02 - k * 0.003, 0.016 - k * 0.003, f"{tag}3_L", LEG, 0.004, gloss=0.5))
        side.append(cone(tuple(p3), tuple(p3 + np.array([0.03, 0.0, -0.05])), 0.01, 0.002, f"{tag}4_L", LEG, 0.003, gloss=0.6))
    # Wing cases: one per side with a hairline seam down the middle.
    side.append(ell((0.13, 0.56, 0.13), (0.2, 0.19, 0.43), "Spine", SHELL, 0.004, tag="shell", gloss=0.8))
    # Head: compound eye, mandible, clubbed antenna.
    side += [ell((0.1, 0.45, -0.575), (0.042, 0.045, 0.045), "Head", EYE, 0.004, tag="ceye", gloss=1.0),
             cone((0.065, 0.37, -0.62), (0.05, 0.345, -0.72), 0.026, 0.014, "Head", HORN, 0.006, gloss=0.6),
             cone((0.05, 0.345, -0.72), (0.012, 0.34, -0.77), 0.014, 0.004, "Head", HORN, 0.004, gloss=0.6),
             cone((0.085, 0.48, -0.62), (0.2, 0.6, -0.76), 0.008, 0.006, "Head", LEG, 0.004),
             ell((0.21, 0.61, -0.775), (0.022, 0.016, 0.03), "Head", LEG, 0.004)]
    mush = [(0.12, 0.83, 0.04, 0.11), (-0.08, 0.84, 0.2, 0.13), (0.03, 0.81, -0.12, 0.08)]
    caps = []
    for (x, y, z, r) in mush:
        caps.append(cone((x, y - 0.12, z), (x, y + r * 0.6, z), r * 0.28, r * 0.22, "Spine", STEM, 0.02, tag="stem", glow=0.2))
        caps.append(ell((x, y + r * 0.7, z), (r, r * 0.42, r), "Spine", CAP, 0.01, tag="cap", glow=0.55))
    parts = mirror(side) + caps + [
        ell((0, 0.43, 0.1), (0.3, 0.14, 0.46), "Spine", UNDER, 0.03, tag="belly"),
        ell((0, 0.5, -0.33), (0.29, 0.17, 0.19), "Chest", SHELL, 0.02, tag="shell", gloss=0.8),
        ell((0, 0.42, -0.53), (0.13, 0.1, 0.11), "Head", UNDER, 0.02, gloss=0.4),
        # Head horn: a long curve with a forked tip.
        cone((0, 0.42, -0.58), (0, 0.55, -0.82), 0.065, 0.045, "Head", HORN, 0.02, gloss=0.7, tag="horn"),
        cone((0, 0.55, -0.82), (0, 0.73, -0.93), 0.045, 0.028, "Head", HORN, 0.015, gloss=0.7, tag="horn"),
        cone((0, 0.73, -0.93), (0, 0.86, -0.89), 0.028, 0.016, "Head", HORN, 0.01, gloss=0.7, tag="horn"),
        cone((0, 0.86, -0.89), (0.035, 0.93, -0.84), 0.016, 0.004, "Head", HORN, 0.006, gloss=0.7, tag="horn"),
        cone((0, 0.86, -0.89), (-0.035, 0.93, -0.84), 0.016, 0.004, "Head", HORN, 0.006, gloss=0.7, tag="horn"),
        # Short pronotum horn.
        cone((0, 0.62, -0.4), (0, 0.67, -0.6), 0.05, 0.012, "Chest", HORN, 0.02, gloss=0.7, tag="horn"),
    ]
    m = Model("MushroomBeetle", bones, parts, voxel=0.009, tris=11000, seed=14)
    shell = np.array([p.tag == "shell" for p in m.parts])
    capm = np.array([p.tag == "cap" for p in m.parts])
    belly = np.array([p.tag == "belly" for p in m.parts])
    ceye = np.array([p.tag == "ceye" for p in m.parts])

    def spots(v, n, pd):
        # Two rows of round glowing spots down each wing case.
        on = (pd[:, shell].min(1) < 0.01) & (n[:, 1] > -0.1) & (v[:, 2] > -0.12)
        ax = np.abs(v[:, 0])
        row = np.minimum(np.abs(ax - 0.08), np.abs(ax - 0.2))
        along = np.abs(((v[:, 2] + 0.3) / 0.16) % 1.0 - 0.5) * 0.16
        d = np.hypot(row, along)
        return np.clip((0.034 - d) / 0.01, 0, 1) * on

    def under_caps(pd, n):
        return (pd[:, capm].min(1) < 0.01) & (n[:, 1] < -0.3)

    def col(v, n, pd, c):
        on_shell = pd[:, shell].min(1) < 0.01
        # Fine ridges along the wing cases, and an oily blue-violet sheen near the top.
        ridge = 0.5 + 0.5 * np.cos(np.abs(v[:, 0]) * 160.0)
        c[on_shell] *= (0.8 + 0.3 * ridge[on_shell])[:, None]
        sheen = np.clip(n[:, 1], 0, 1)[:, None] * on_shell[:, None]
        c = c * (1 - 0.5 * sheen) + np.array([0.18, 0.16, 0.36]) * 0.5 * sheen
        # Segment bands on the belly, facets on the compound eyes.
        on_belly = pd[:, belly].min(1) < 0.006
        c[on_belly] *= (0.7 + 0.5 * (np.sin(v[on_belly, 2] * 45.0) > 0.6))[:, None]
        on_eye = pd[:, ceye].min(1) < 0.004
        c[on_eye] *= (0.6 + 0.8 * fbm(v[on_eye], 220, 1, 3))[:, None]
        g = spots(v, n, pd)[:, None]
        c = c * (1 - g) + np.array(CYAN) * g
        c[under_caps(pd, n)] = CYAN   # glowing gills under the caps
        return c
    m.glow_fn = lambda v, n, pd: np.maximum(spots(v, n, pd), under_caps(pd, n) * 0.9)
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
