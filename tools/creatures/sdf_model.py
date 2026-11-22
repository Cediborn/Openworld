"""Tiny signed-distance modeller that turns a list of soft primitives into a
skinned, vertex-coloured glTF (.glb) that Godot imports directly.

Author: Claude (Openworld). Used by build_creatures.py; no outside downloads.

How a model is described
------------------------
* Bones: (name, parent, head_xyz). Each bone becomes a glTF joint at its head,
  with no rest rotation, so the game can swing legs by rotating around local X.
* Parts: soft primitives (round cones, ellipsoids) tagged with a bone, a colour
  and a smoothing radius. They are blended with a smooth minimum, so joints and
  muscles flow into each other instead of looking like stacked capsules.
* Fur: optional noise added to the distance field gives a tufted silhouette.

The field is sampled on a grid, meshed with marching cubes, decimated to a
triangle budget for phones, then coloured and skinned from the primitives
nearest each vertex.
"""
import json
import struct

import numpy as np
import pyfqmr
from skimage import measure

# ---------------------------------------------------------------- noise

def _hash(ix, iy, iz, seed):
    h = (ix * 374761393 + iy * 668265263 + iz * 2147483647 + seed * 144269) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return (h & 0xFFFF) / 65535.0


def value_noise(p, freq, seed=0):
    """Smooth 3D value noise in [0, 1] for an (N, 3) array of points."""
    q = p * freq
    i = np.floor(q).astype(np.int64)
    f = q - i
    f = f * f * (3 - 2 * f)
    out = np.zeros(len(p))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out += w * _hash(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz, seed)
    return out


def fbm(p, freq, octaves=3, seed=0):
    total, amp, norm = np.zeros(len(p)), 1.0, 0.0
    for o in range(octaves):
        total += amp * value_noise(p, freq * (2 ** o), seed + o * 17)
        norm += amp
        amp *= 0.5
    return total / norm

# ---------------------------------------------------------------- primitives

def round_cone(p, a, b, ra, rb):
    """Distance to a capsule from a (radius ra) to b (radius rb)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    ba = b - a
    l2 = max(float(ba @ ba), 1e-9)
    t = np.clip(((p - a) @ ba) / l2, 0.0, 1.0)
    closest = a + t[:, None] * ba
    return np.linalg.norm(p - closest, axis=1) - (ra + (rb - ra) * t)


def ellipsoid(p, c, r):
    q = (p - np.asarray(c, float)) / np.asarray(r, float)
    k0 = np.linalg.norm(q, axis=1)
    k1 = np.linalg.norm(q / np.asarray(r, float), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
    return b * (1 - h) + a * h - k * h * (1 - h)


class Part:
    def __init__(self, kind, args, bone, color, blend=0.04, fur=0.0, tag="", glow=0.0):
        self.kind, self.args, self.bone = kind, args, bone
        self.color = np.asarray(color, float)
        self.blend, self.fur, self.tag, self.glow = blend, fur, tag, glow

    def dist(self, p):
        if self.kind == "cone":
            return round_cone(p, *self.args)
        return ellipsoid(p, *self.args)


def cone(a, b, ra, rb, bone, color, blend=0.04, fur=0.0, tag="", glow=0.0):
    return Part("cone", (a, b, ra, rb), bone, color, blend, fur, tag, glow)


def ell(c, r, bone, color, blend=0.04, fur=0.0, tag="", glow=0.0):
    return Part("ell", (c, r), bone, color, blend, fur, tag, glow)


def mirror(parts):
    """Adds the left-right mirror (x -> -x) of each part; bone names L<->R."""
    out = []
    for pt in parts:
        out.append(pt)
        if pt.kind == "cone":
            a, b, ra, rb = pt.args
            args = ((-a[0], a[1], a[2]), (-b[0], b[1], b[2]), ra, rb)
        else:
            c, r = pt.args
            args = ((-c[0], c[1], c[2]), r)
        bone = pt.bone.replace("_L", "_R") if pt.bone.endswith("_L") else pt.bone
        out.append(Part(pt.kind, args, bone, pt.color, pt.blend, pt.fur, pt.tag, pt.glow))
    return out

# ---------------------------------------------------------------- model

class Model:
    def __init__(self, name, bones, parts, voxel=0.02, tris=6000, fur_freq=55.0, seed=1):
        self.name, self.bones, self.parts = name, bones, parts
        self.voxel, self.tris, self.fur_freq, self.seed = voxel, tris, fur_freq, seed
        self.color_fn = None   # optional fn(points, normals, part_dist, rgb) -> rgb
        self.glow_fn = None    # optional fn(points, normals, part_dist) -> glow 0..1 (stored in alpha)

    def field(self, p, with_fur=True):
        d = None
        fur_amt = np.zeros(len(p))
        for pt in self.parts:
            di = pt.dist(p)
            if pt.fur > 0:
                near = np.clip(1.0 - np.abs(di) / 0.05, 0, 1)
                fur_amt = np.maximum(fur_amt, pt.fur * near)
            d = di if d is None else smin(d, di, pt.blend)
        if with_fur and fur_amt.max() > 0:
            n = fbm(p, self.fur_freq, 3, self.seed) - 0.5
            d = d - fur_amt * n * 2.0
        return d

    def _bounds(self):
        lo, hi = np.full(3, 1e9), np.full(3, -1e9)
        for pt in self.parts:
            if pt.kind == "cone":
                a, b, ra, rb = pt.args
                r = max(ra, rb)
                for q in (a, b):
                    lo = np.minimum(lo, np.asarray(q) - r)
                    hi = np.maximum(hi, np.asarray(q) + r)
            else:
                c, r = pt.args
                lo = np.minimum(lo, np.asarray(c) - np.asarray(r))
                hi = np.maximum(hi, np.asarray(c) + np.asarray(r))
        pad = 0.06
        return lo - pad, hi + pad

    def mesh(self):
        lo, hi = self._bounds()
        v = self.voxel
        shape = np.ceil((hi - lo) / v).astype(int) + 1
        axes = [lo[i] + np.arange(shape[i]) * v for i in range(3)]
        gx, gy, gz = np.meshgrid(*axes, indexing="ij")
        pts = np.stack([gx.ravel(), gy.ravel(), gz.ravel()], 1)
        vals = np.empty(len(pts))
        step = 400000
        for s in range(0, len(pts), step):
            vals[s:s + step] = self.field(pts[s:s + step])
        vol = vals.reshape(shape)
        verts, faces, _, _ = measure.marching_cubes(vol, 0.0, spacing=(v, v, v))
        verts = verts + lo
        # skimage already winds faces counter-clockwise seen from outside (glTF front).
        simp = pyfqmr.Simplify()
        simp.setMesh(verts, faces)
        simp.simplify_mesh(target_count=self.tris, aggressiveness=6, preserve_border=True, verbose=False)
        verts, faces, _ = simp.getMesh()
        return np.asarray(verts, float), np.asarray(faces, np.int64)

    def normals(self, verts):
        e = 0.004
        g = np.zeros_like(verts)
        for i in range(3):
            off = np.zeros(3)
            off[i] = e
            g[:, i] = self.field(verts + off) - self.field(verts - off)
        return g / np.maximum(np.linalg.norm(g, axis=1, keepdims=True), 1e-9)

    def part_distances(self, verts):
        return np.stack([pt.dist(verts) for pt in self.parts], 1)

    def colors(self, verts, norms, pd, faces):
        # Soft blend of the colours of nearby parts, so seams don't show.
        w = np.exp(-np.maximum(pd, 0) / 0.012) * (pd < 0.08)
        w[np.arange(len(verts)), np.argmin(pd, 1)] += 1e-3
        cols = (w @ np.stack([pt.color for pt in self.parts])) / w.sum(1, keepdims=True)
        if self.color_fn is not None:
            cols = self.color_fn(verts, norms, pd, cols)
        hard = np.zeros_like(w)
        hard[np.arange(len(verts)), np.argmin(pd, 1)] = 1.0
        glow = hard @ np.array([pt.glow for pt in self.parts])
        if self.glow_fn is not None:
            glow = np.maximum(glow, self.glow_fn(verts, norms, pd))
        return np.clip(cols, 0, 1), np.clip(glow, 0, 1)

    def weights(self, verts, pd):
        names = [b[0] for b in self.bones]
        nb = len(names)
        bw = np.zeros((len(verts), nb))
        for j, pt in enumerate(self.parts):
            bw[:, names.index(pt.bone)] += np.exp(-np.maximum(pd[:, j], 0) / 0.02)
        idx = np.argsort(-bw, 1)[:, :4]
        top = np.take_along_axis(bw, idx, 1)
        top = top / np.maximum(top.sum(1, keepdims=True), 1e-9)
        top[top < 0.02] = 0
        top = top / top.sum(1, keepdims=True)
        return idx.astype(np.uint16), top.astype(np.float32)

    def build(self, path):
        verts, faces = self.mesh()
        norms = self.normals(verts)
        pd = self.part_distances(verts)
        cols, glow = self.colors(verts, norms, pd, faces)
        joints, wts = self.weights(verts, pd)
        write_glb(path, self.name, verts, norms, cols, faces, joints, wts, self.bones, glow)
        return len(verts), len(faces)

# ---------------------------------------------------------------- glTF

def write_glb(path, name, verts, norms, cols, faces, joints, wts, bones, glow=None):
    """Vertex alpha stores 1 - glow, so ordinary surfaces stay fully opaque white-alpha."""
    if glow is None:
        glow = np.zeros(len(verts))
    blobs, views, accs = [], [], []

    def add(arr, comp, typ, target=None, minmax=False, normalized=False):
        data = np.ascontiguousarray(arr).tobytes()
        off = sum(len(b) for b in blobs)
        pad = (-len(data)) % 4
        blobs.append(data + b"\0" * pad)
        view = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            view["target"] = target
        views.append(view)
        acc = {"bufferView": len(views) - 1, "componentType": comp, "count": len(arr), "type": typ}
        if normalized:
            acc["normalized"] = True
        if minmax:
            acc["min"] = [float(x) for x in arr.min(0)]
            acc["max"] = [float(x) for x in arr.max(0)]
        accs.append(acc)
        return len(accs) - 1

    F, U8, U16, U32 = 5126, 5121, 5123, 5125
    a_pos = add(verts.astype(np.float32), F, "VEC3", 34962, True)
    a_nor = add(norms.astype(np.float32), F, "VEC3", 34962)
    c8 = np.concatenate([np.round(cols * 255), np.round((1 - glow[:, None]) * 255)], 1).astype(np.uint8)
    a_col = add(c8, U8, "VEC4", 34962, normalized=True)
    a_jnt = add(joints, U16, "VEC4", 34962)
    a_wgt = add(wts, F, "VEC4", 34962)
    a_idx = add(faces.astype(np.uint32).ravel(), U32, "SCALAR", 34963)

    names = [b[0] for b in bones]
    heads = {b[0]: np.asarray(b[2], float) for b in bones}
    nodes = [{"name": name, "children": [1]}, {"name": name + "_mesh", "mesh": 0, "skin": 0}]
    first = len(nodes)
    for nm, parent, head in bones:
        rel = heads[nm] - (heads[parent] if parent else np.zeros(3))
        nodes.append({"name": nm, "translation": [float(x) for x in rel]})
    for i, (nm, parent, _) in enumerate(bones):
        if parent:
            pn = nodes[first + names.index(parent)]
            pn.setdefault("children", []).append(first + i)
        else:
            nodes[0]["children"].append(first + i)
    ibm = []
    for nm in names:
        m = np.eye(4)
        m[:3, 3] = -heads[nm]
        ibm.append(m.T.ravel())   # glTF matrices are column-major
    a_ibm = add(np.asarray(ibm, np.float32), F, "MAT4")

    gltf = {
        "asset": {"version": "2.0", "generator": "openworld sdf_model.py"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": nodes,
        "meshes": [{"name": name, "primitives": [{
            "attributes": {"POSITION": a_pos, "NORMAL": a_nor, "COLOR_0": a_col, "JOINTS_0": a_jnt, "WEIGHTS_0": a_wgt},
            "indices": a_idx, "material": 0}]}],
        "materials": [{"name": name + "_fur", "pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.0, "roughnessFactor": 0.85}}],
        "skins": [{"joints": list(range(first, first + len(bones))), "inverseBindMatrices": a_ibm, "skeleton": first}],
        "accessors": accs,
        "bufferViews": views,
        "buffers": [{"byteLength": sum(len(b) for b in blobs)}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    bin_ = b"".join(blobs)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bin_)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(bin_), 0x004E4942) + bin_)


def write_static_glb(path, name, verts, norms, cols, faces):
    """Same as write_glb but without a skeleton (for props like hair or boots)."""
    one = np.zeros((len(verts), 4), np.uint16)
    w = np.zeros((len(verts), 4), np.float32)
    w[:, 0] = 1
    write_glb(path, name, verts, norms, cols, faces, one, w, [("root", None, (0, 0, 0))])
