#!/usr/bin/env python3
"""Plans the island's water from its real terrain and writes game/data/water.json.

Water goes where water would go: lakes and ponds fill the island's natural
hollows up to just below their lowest rim (found with a priority flood),
streams start at springs on higher ground and follow the steepest way down
until they reach a lake, and a waterfall is placed wherever a stream drops
steeply. Frost Peaks water is frozen; Glow Hollow water glows.

Nothing is put where it would get in the way: roads and paths, houses, the
church and your house, quest spots, discoveries, shrines, treasure and boss
arenas are kept dry (with a margin), as is the lava field and the island's
rim. The terrain itself is not changed.

    python3 tools/world_generation/plan_water.py      # rewrites game/data/water.json
"""
import heapq
import json
import math
import os

import numpy as np

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "game")
RES, STEP, HALF = 513, 2.0, 512.0
ZONES = ["Hub Meadow", "Frost Peaks", "Ember Wastes", "Glow Hollow", "Brickton"]


def load():
    h = np.fromfile(os.path.join(ROOT, "data/height.bin"), dtype="<f4").reshape(RES, RES)
    b = np.fromfile(os.path.join(ROOT, "data/biome.bin"), dtype=np.uint8).reshape(RES, RES, 4) / 255.0
    m = np.fromfile(os.path.join(ROOT, "data/mask.bin"), dtype=np.uint8).reshape(RES, RES, 2).max(axis=2) / 255.0
    zone = np.zeros((RES, RES, 5))
    zone[..., 1:] = b
    zone[..., 0] = np.clip(1.0 - b.sum(axis=2), 0, 1)
    return h, zone.argmax(axis=2), m


def world(i, j):
    return -HALF + i * STEP, -HALF + j * STEP


def cell(x, z):
    return int(round((x + HALF) / STEP)), int(round((z + HALF) / STEP))


def keep_dry(m):
    """Cells where no water may go: paths, buildings, quest and feature spots, lava, the rim."""
    dry = m > 0.25
    spots = []
    feats = json.load(open(os.path.join(ROOT, "data/world_features.json")))
    for key in ["structures", "discoveries", "treasures", "shrines", "rare_bosses"]:
        for f in feats.get(key, []):
            if "pos" in f:
                spots.append((f["pos"][0], f["pos"][1], 22.0 + float(f.get("radius", 0))))
    quests = json.load(open(os.path.join(ROOT, "data/quests.json")))
    for q in quests.get("quests", {}).values():
        for s in q.get("steps", []):
            if isinstance(s.get("pos"), list):
                spots.append((s["pos"][0], s["pos"][-1], 18.0))
    for hs in json.load(open(os.path.join(ROOT, "data/village.json"))):
        spots.append((hs["x"], hs["z"], max(hs.get("w", 8), hs.get("d", 8)) * 0.8 + 6.0))
    for lm in json.load(open(os.path.join(ROOT, "data/landmarks.json")))["landmarks"]:
        spots.append((lm["x"], lm["z"], max(lm.get("w", 10), lm.get("d", 10)) * 0.8 + 12.0))
    spots += [(-300, 0, 95.0), (0, 0, 30.0)]   # Brickton itself, the meadow spawn
    jj, ii = np.mgrid[0:RES, 0:RES]
    xs, zs = -HALF + ii * STEP, -HALF + jj * STEP
    for (x, z, r) in spots:
        dry |= (xs - x) ** 2 + (zs - z) ** 2 < r * r
    dry |= (np.abs(xs - 360) < 160) & (np.abs(zs) < 270)       # the lava field
    dry |= np.hypot(xs, zs) > 400                                # the rim
    # A margin around everything kept dry.
    grown = dry.copy()
    for _ in range(4):
        grown[1:] |= grown[:-1]; grown[:-1] |= grown[1:]; grown[:, 1:] |= grown[:, :-1]; grown[:, :-1] |= grown[:, 1:]
    return grown


def priority_flood(h):
    """Height the land would hold water to (Barnes et al. priority flood). The
    island is ringed by its mountain rim, so water drains out at the foot of
    the rim (r = 380 m), not at the map edge; otherwise the whole island
    would count as one hollow."""
    filled = h.copy()
    seen = np.zeros_like(h, dtype=bool)
    pq = []
    jj, ii = np.mgrid[0:RES, 0:RES]
    ring = np.hypot(-HALF + ii * STEP, -HALF + jj * STEP) >= 380
    for j, i in zip(*np.nonzero(ring)):
        heapq.heappush(pq, (h[j, i], j, i)); seen[j, i] = True
    while pq:
        v, j, i = heapq.heappop(pq)
        for dj, di in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nj, ni = j + dj, i + di
            if 0 <= nj < RES and 0 <= ni < RES and not seen[nj, ni]:
                seen[nj, ni] = True
                filled[nj, ni] = max(h[nj, ni], v)
                heapq.heappush(pq, (filled[nj, ni], nj, ni))
    return filled


def basins(h, filled, dry, zone):
    """Connected hollows (depth > 0.8 m), each with its water level and extent."""
    depth = filled - h
    wet = depth > 0.25
    label = np.zeros(h.shape, dtype=int)
    out = []
    stats = []
    n = 0
    for j in range(RES):
        for i in range(RES):
            if wet[j, i] and not label[j, i]:
                n += 1
                stack, cells = [(j, i)], []
                label[j, i] = n
                while stack:
                    cj, ci = stack.pop()
                    cells.append((cj, ci))
                    for dj, di in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nj, ni = cj + dj, ci + di
                        if 0 <= nj < RES and 0 <= ni < RES and wet[nj, ni] and not label[nj, ni] and abs(filled[nj, ni] - filled[cj, ci]) < 0.01:
                            label[nj, ni] = n
                            stack.append((nj, ni))
                cells = np.array(cells)
                d = depth[cells[:, 0], cells[:, 1]]
                stats.append((len(cells) * STEP * STEP, round(float(d.max()), 2), int(dry[cells[:, 0], cells[:, 1]].mean() * 100)))
                # Keep paths and places dry: the water stops 0.3 m below the lowest of them.
                level = float(filled[cells[0][0], cells[0][1]]) - 0.15
                hd = h[cells[:, 0], cells[:, 1]]
                guarded = dry[cells[:, 0], cells[:, 1]]
                if guarded.any():
                    level = min(level, float(hd[guarded].min()) - 0.3)
                cells = cells[(hd < level) & ~guarded]
                if len(cells) * STEP * STEP < 120 or len(cells) == 0 or level - h[cells[:, 0], cells[:, 1]].min() < 0.8:
                    continue
                cj, ci = cells.mean(axis=0)
                x, z = world(ci, cj)
                r = max(math.hypot(*(np.array(world(c[1], c[0])) - (x, z))) for c in cells) + STEP
                z_id = int(np.bincount(zone[cells[:, 0], cells[:, 1]]).argmax())
                out.append({"center": [round(float(x), 1), round(float(z), 1)], "radius": round(float(r), 1),
                            "level": round(level, 2),
                            "max_depth": round(level - float(h[cells[:, 0], cells[:, 1]].min()), 2), "area": len(cells) * STEP * STEP, "zone": z_id,
                            "cells": cells})
    stats.sort(reverse=True)
    print("hollows (area m2, depth m, % kept dry):", stats[:15])
    return out


def trace(h, filled, start, lake, dry):
    """Steepest way down from a spring to the lake. None if it crosses dry ground."""
    j, i = start
    path = [(j, i)]
    target = lake["cells"]
    tset = set(map(tuple, target))
    for _ in range(400):
        if (j, i) in tset:
            return path
        best = None
        for dj in (-1, 0, 1):
            for di in (-1, 0, 1):
                nj, ni = j + dj, i + di
                if (dj or di) and 0 <= nj < RES and 0 <= ni < RES:
                    drop = (filled[j, i] - filled[nj, ni]) / math.hypot(dj, di)
                    if best is None or drop > best[0]:
                        best = (drop, nj, ni)
        if best is None or best[0] <= 0.0:
            return None
        j, i = best[1], best[2]
        if dry[j, i]:
            return None
        path.append((j, i))
    return None


def carve_meadows(h, zone, dry, water):
    """Hub Meadow and Brickton have no natural hollows clear of roads and
    places, so each gets a dug pond in its most open spot, fed by a brook
    that follows the steepest way down from a spring above it. The game
    carves them into the terrain when it loads (WorldData.carve_water)."""
    from scipy import ndimage
    room = ndimage.distance_transform_edt(~dry) * STEP
    gy, gx = np.gradient(h, STEP)
    slope = np.hypot(gx, gy)
    names = {0: ("Meadow Pond", "Meadow Brook"), 4: ("Millpond", "Mill Brook"), 3: ("Glimmer Pool", "Glimmer Rill")}
    for z_id, (lake_name, brook_name) in names.items():
        if any(l["name"].startswith(ZONES[z_id]) for l in water["lakes"]) and z_id != 3:
            continue
        score = np.where((zone == z_id) & (slope < 0.12), room, 0)
        j, i = np.unravel_index(score.argmax(), score.shape)
        if score[j, i] < 30:
            continue
        r = min(16.0, room[j, i] - 12.0)
        x, z = world(i, j)
        ring = [h[cell(x + r * math.cos(a), z + r * math.sin(a))[::-1]] for a in np.linspace(0, math.tau, 24, endpoint=False)]
        level = float(min(ring)) - 0.2
        lake = {"name": lake_name, "center": [round(float(x), 1), round(float(z), 1)], "radius": round(float(r), 1), "level": round(level, 2),
                "carve": {"floor": round(level - 1.5, 2)}, "glow": 1.0 if z_id == 3 else 0.0, "clarity": 2.0}
        water["lakes"].append(lake)
        best = None
        for ang in range(0, 360, 10):
            for dist in (70, 100, 130):
                si, sj = cell(x + dist * math.cos(math.radians(ang)), z + dist * math.sin(math.radians(ang)))
                if not (0 <= si < RES and 0 <= sj < RES) or dry[sj, si] or h[sj, si] < level + 3.0:
                    continue
                path = [(sj, si)]
                ok = False
                for _ in range(300):
                    cj, ci = path[-1]
                    if math.hypot(*(np.array(world(ci, cj)) - (x, z))) < r + 2.0:   # at the rim
                        ok = True
                        break
                    # Steepest way down, nudged towards the pond so it does not stall on flats.
                    opts = []
                    for dj in (-1, 0, 1):
                        for di in (-1, 0, 1):
                            nj, ni = cj + dj, ci + di
                            if (dj or di) and 0 <= nj < RES and 0 <= ni < RES and not dry[nj, ni] and (nj, ni) not in path:
                                d_now = math.hypot(*(np.array(world(ci, cj)) - (x, z)))
                                d_next = math.hypot(*(np.array(world(ni, nj)) - (x, z)))
                                opts.append(((h[cj, ci] - h[nj, ni]) / math.hypot(dj, di) + (d_now - d_next) * 0.05, nj, ni))
                    if not opts:
                        break
                    opts.sort(reverse=True)
                    path.append((opts[0][1], opts[0][2]))
                if ok and len(path) > 25 and (best is None or len(path) < len(best)):
                    best = path
        if best is None:
            continue
        pts, bed = [], None
        for k in range(0, len(best), 3):
            cj, ci = best[k]
            bx, bz = world(ci, cj)
            b = float(h[cj, ci]) - 0.45
            bed = b if bed is None else min(b, bed - 0.03)   # always downhill
            pts.append([round(float(bx), 1), round(float(bz), 1), round(max(bed, level - 0.3), 2)])
        # Run on to the pond's rim; if the rim stands above the water, the brook falls in.
        lx, lz = pts[-1][0], pts[-1][1]
        dx, dz = x - lx, z - lz
        dist = math.hypot(dx, dz)
        rim_x, rim_z = x - dx / dist * (r + 0.5), z - dz / dist * (r + 0.5)
        ri, rj = cell(rim_x, rim_z)
        pts.append([round(rim_x, 1), round(rim_z, 1), round(min(pts[-1][2], float(h[rj, ri]) - 0.1), 2)])   # the lip sits on the ground
        water["rivers"].append({"name": brook_name, "points": pts, "width": 2.4, "depth": 0.35, "speed": 0.8,
                                "glow": lake["glow"], "rapids": [len(pts) // 3, len(pts) - 1], "carve": True})
        drop = pts[-1][2] + 0.35 - level
        if drop > 1.2:
            in_x, in_z = x - dx / dist * (r - 2.5), z - dz / dist * (r - 2.5)
            water["falls"].append({"name": brook_name + " Falls", "top": [pts[-1][0], round(pts[-1][2] + 0.35, 2), pts[-1][1]],
                                   "bottom": [round(in_x, 1), round(level + 0.05, 2), round(in_z, 1)], "width": 2.8})


def plan():
    h, zone, m = load()
    dry = keep_dry(m)
    filled = priority_flood(h)
    lakes = basins(h, filled, dry, zone)
    water = {"_comment": "Written by tools/world_generation/plan_water.py from the real terrain. Lakes fill natural hollows to just below their rims; streams follow the steepest way down from a spring; falls are where they drop steeply. Points are [x, z, bed height].",
             "rivers": [], "falls": [], "lakes": []}
    # Per zone, keep the larger hollows (at most 3), then find a stream for each.
    for z_id in range(5):
        if z_id == 2:
            continue   # Ember Wastes has its lava instead
        mine = sorted([l for l in lakes if l["zone"] == z_id], key=lambda l: -l["area"])[:3]
        for lake in mine:
            entry = {"name": "%s %s" % (ZONES[z_id], "Tarn" if z_id == 1 else "Pool" if z_id == 3 else "Pond"),
                     "center": lake["center"], "radius": lake["radius"], "level": lake["level"],
                     "frozen": z_id == 1, "glow": 1.0 if z_id == 3 else 0.0, "clarity": 2.0}
            water["lakes"].append(entry)
            cj, ci = cell(*lake["center"])[::-1]
            # Springs: higher ground 50-160 m away, tried nearest-first by how much they fall.
            best = None
            for ang in range(0, 360, 12):
                for dist in (60, 90, 120, 150):
                    x = lake["center"][0] + dist * math.cos(math.radians(ang))
                    z = lake["center"][1] + dist * math.sin(math.radians(ang))
                    si, sj = cell(x, z)
                    if not (0 <= si < RES and 0 <= sj < RES) or dry[sj, si] or h[sj, si] < lake["level"] + 4.0:
                        continue
                    p = trace(h, filled, (sj, si), lake, dry)
                    if p and len(p) > 20 and (best is None or h[sj, si] - lake["level"] > best[0]):
                        best = (h[sj, si] - lake["level"], p)
            if best is None:
                continue
            path = best[1]
            pts, fall = [], None
            for k in range(0, len(path), 3):
                j, i = path[k]
                x, z = world(i, j)
                pts.append([round(x, 1), round(z, 1), round(float(h[j, i]) - 0.1, 2)])
            for k in range(1, len(path)):
                (j0, i0), (j1, i1) = path[k - 1], path[k]
                if h[j0, i0] - h[j1, i1] > 2.2 and fall is None:   # > 2.2 m over one 2-3 m step: a fall
                    x0, z0 = world(i0, j0)
                    x1, z1 = world(i1, j1)
                    fall = {"name": entry["name"] + " Falls", "top": [round(x0, 1), round(float(h[j0, i0]) + 0.1, 2), round(z0, 1)],
                            "bottom": [round(x1, 1), round(float(h[j1, i1]) + 0.2, 2), round(z1, 1)], "width": 2.6, "frozen": z_id == 1}
            water["rivers"].append({"name": entry["name"].replace("Pond", "Brook").replace("Tarn", "Beck").replace("Pool", "Rill"),
                                    "points": pts, "width": 2.6, "depth": 0.18, "speed": 0.9, "frozen": z_id == 1,
                                    "glow": entry["glow"], "rapids": [len(pts) // 2]})
            if fall:
                water["falls"].append(fall)
    carve_meadows(h, zone, dry, water)
    out = os.path.join(ROOT, "data/water.json")
    json.dump(water, open(out, "w"), indent=1)
    print("lakes %d, rivers %d, falls %d -> %s" % (len(water["lakes"]), len(water["rivers"]), len(water["falls"]), os.path.normpath(out)))
    for l in water["lakes"]:
        print("  %-22s at %s r=%.0f level %.1f" % (l["name"], l["center"], l["radius"], l["level"]))


if __name__ == "__main__":
    plan()
