#!/usr/bin/env python3
"""Assembles realistic pub customers from MakeHuman's CC0 data (step 1 of 2).

Reads the MakeHuman base mesh, macro and expression targets, rig and skin weights (all CC0, from
the MPFB2 repository's data folder) and the MakeHuman system asset pack (CC0: body proxies,
skins, clothes, hair, eyes, brows, lashes, teeth). This script only reads those data files; it
runs none of their code.

For each character in characters.json it:
  * morphs the base mesh for gender, age, muscle, weight, height and ethnicity (MakeHuman's
    macro target formula), and makes blink, mouth-open and smile versions from the expression
    targets
  * fits the body proxy and every clothing, hair, eye, brow, lash and teeth asset to the morphed
    body (MakeHuman's proxy fitting: three weighted reference vertices plus a scaled offset)
  * hides body skin under clothes, and gives every part skin weights for the game-engine rig
  * places the bones from the joint helpers, then re-poses the arms to hang straight down (the
    rest pose the game animates from)
  * converts to metres, Y up, facing -Z, feet on the floor
and writes tools/people/build/<name>.npz plus a JSON manifest for blender_export.py.

Textures are resized, logo-free and recoloured into assets/people_mh/textures.

Usage: python3 tools/people/mh_build.py <mpfb2 data dir> <makehuman system assets dir>
"""
import gzip
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BUILD = os.path.join(HERE, "build")
TEX_OUT = os.path.join(ROOT, "assets", "people_mh", "textures")


# ------------------------------------------------------------------ OBJ and asset parsing
def read_obj(path):
    """Vertices, UVs and faces (each a list of (v, vt) pairs) with their group names."""
    v, vt, faces, groups = [], [], [], []
    group = ""
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("v "):
                v.append([float(x) for x in line.split()[1:4]])
            elif line.startswith("vt "):
                vt.append([float(x) for x in line.split()[1:3]])
            elif line.startswith("g "):
                group = line[2:].strip()
            elif line.startswith("f "):
                corners = []
                for c in line.split()[1:]:
                    p = c.split("/")
                    corners.append((int(p[0]) - 1, int(p[1]) - 1 if len(p) > 1 and p[1] else -1))
                faces.append(corners)
                groups.append(group)
    return np.array(v, np.float64), np.array(vt, np.float64), faces, groups


def parse_ranges(tokens):
    out = []
    i = 0
    while i < len(tokens):
        if i + 2 < len(tokens) and tokens[i + 1] == "-":
            out.extend(range(int(tokens[i]), int(tokens[i + 2]) + 1))
            i += 3
        else:
            out.append(int(tokens[i]))
            i += 1
    return out


def read_mhclo(path):
    """A .proxy or .mhclo file: reference vertices, weights, offsets, scales and deletions."""
    info = {"refs": [], "weights": [], "offsets": [], "scale": {}, "delete": [], "dir": os.path.dirname(path)}
    mode = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            tok = line.split()
            key = tok[0]
            if key in ("x_scale", "y_scale", "z_scale"):
                info["scale"][key[0]] = (int(tok[1]), int(tok[2]), float(tok[3]))
            elif key in ("obj_file", "material", "name", "z_depth"):
                info[key] = tok[1] if len(tok) > 1 else ""
            elif key == "verts":
                mode = "verts"
            elif key == "delete_verts":
                mode = "delete"
            elif not (key[0].isdigit() or key[0] in "-."):
                continue   # other keywords (uuid, tag, weights file...) can appear anywhere
            elif mode == "verts":
                nums = [float(x) for x in tok]
                if len(nums) == 1:
                    i = int(nums[0])
                    info["refs"].append((i, i, i))
                    info["weights"].append((1.0, 0.0, 0.0))
                    info["offsets"].append((0.0, 0.0, 0.0))
                elif len(nums) >= 9:
                    info["refs"].append((int(nums[0]), int(nums[1]), int(nums[2])))
                    info["weights"].append(tuple(nums[3:6]))
                    info["offsets"].append(tuple(nums[6:9]))
            elif mode == "delete":
                info["delete"].extend(parse_ranges(tok))
    for k in ("refs", "weights", "offsets"):
        info[k] = np.array(info[k], np.float64 if k != "refs" else np.int64)
    return info


def read_mhmat(path):
    mat = {"dir": os.path.dirname(path)}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            tok = line.strip().split()
            if len(tok) >= 2 and not tok[0].startswith("#"):
                mat[tok[0]] = " ".join(tok[1:])
    return mat


# ------------------------------------------------------------------ MakeHuman data
class MakeHuman:
    def __init__(self, data_dir, assets_dir):
        self.data = data_dir
        self.assets = assets_dir
        self.base_v, self.base_vt, self.base_f, self.base_g = read_obj(os.path.join(data_dir, "3dobjs", "base.obj"))
        self.groups = {}
        for face, g in zip(self.base_f, self.base_g):
            self.groups.setdefault(g, set()).update(v for v, _ in face)
        with open(os.path.join(data_dir, "targets", "macrodetails", "macro.json")) as f:
            self.macro_cfg = json.load(f)["macrotargets"]
        self._targets = {}
        with open(os.path.join(data_dir, "rigs", "standard", "rig.game_engine.json")) as f:
            self.rig = json.load(f)
        with open(os.path.join(data_dir, "rigs", "standard", "weights.game_engine.json")) as f:
            wj = json.load(f)["weights"]
        self.bones = list(self.rig.keys())
        n = len(self.base_v)
        self.W = np.zeros((n, len(self.bones)), np.float32)
        for bi, b in enumerate(self.bones):
            for vi, w in wj.get(b, []):
                self.W[vi, bi] = w
        s = self.W.sum(axis=1, keepdims=True)
        self.W = np.where(s > 0, self.W / np.maximum(s, 1e-9), self.W)

    def target(self, name):
        if name not in self._targets:
            path = os.path.join(self.data, "targets", name + ".target.gz")
            idx, d = [], []
            if os.path.exists(path):
                with gzip.open(path, "rt") as f:
                    for line in f:
                        p = line.split()
                        if len(p) == 4 and not line.startswith("#"):
                            idx.append(int(p[0]))
                            d.append([float(x) for x in p[1:]])
            else:
                print("  (missing target)", name)
            self._targets[name] = (np.array(idx, np.int64), np.array(d, np.float64).reshape(-1, 3))
        return self._targets[name]

    def _components(self, macro, value):
        out = []
        for part in self.macro_cfg[macro]["parts"]:
            lo, hi = part["lowest"], part["highest"]
            if lo < value < hi:
                pct = (value - lo) / (hi - lo)
                if part["low"]:
                    out.append((part["low"], round(1 - pct, 4)))
                if part["high"]:
                    out.append((part["high"], round(pct, 4)))
        return out

    def macro_stack(self, m):
        """MakeHuman's macro formula: which macrodetail targets to add, with what weights."""
        c = {k: self._components(k, m[k]) for k in ["gender", "age", "muscle", "weight", "proportions", "height", "cupsize", "firmness"]}
        out = []
        for race, rw in m["race"].items():
            if rw <= 0.0001:
                continue
            for a in c["age"]:
                for g in c["gender"]:
                    out.append(("macrodetails/%s-%s-%s" % (race, g[0], a[0]), rw * g[1] * a[1]))
        for g in c["gender"]:
            for a in c["age"]:
                for mu in c["muscle"]:
                    for w in c["weight"]:
                        base = g[1] * a[1] * mu[1] * w[1]
                        out.append(("macrodetails/universal-%s-%s-%s-%s" % (g[0], a[0], mu[0], w[0]), base))
                        for h in c["height"]:
                            out.append(("macrodetails/height/%s-%s-%s-%s-%s" % (g[0], a[0], mu[0], w[0], h[0]), base * h[1]))
                        for p in c["proportions"]:
                            out.append(("macrodetails/proportions/%s-%s-%s-%s-%s" % (g[0], a[0], mu[0], w[0], p[0]), base * p[1]))
                        if g[0] == "female":
                            for cu in c["cupsize"]:
                                for fi in c["firmness"]:
                                    name = "breast/female-%s-%s-%s-%s-%s" % (a[0], mu[0], w[0], cu[0], fi[0])
                                    wt = a[1] * mu[1] * w[1] * cu[1] * fi[1]
                                    if "averagecup-averagefirmness" not in name:
                                        out.append((name, wt))
        return [(n, w) for n, w in out if w > 0.01]

    def morph(self, stack, base=None):
        v = (self.base_v if base is None else base).copy()
        for name, w in stack:
            idx, d = self.target(name)
            if len(idx):
                v[idx] += d * w
        return v

    def joint(self, v, name):
        return v[sorted(self.groups["joint-" + name if not name.startswith("joint-") else name])].mean(axis=0)


# ------------------------------------------------------------------ fitting
def fit(proxy, v):
    r, w, o = proxy["refs"], proxy["weights"], proxy["offsets"]
    pos = v[r[:, 0]] * w[:, 0:1] + v[r[:, 1]] * w[:, 1:2] + v[r[:, 2]] * w[:, 2:3]
    scale = np.ones(3)
    for i, ax in enumerate("xyz"):
        if ax in proxy["scale"]:
            a, b, den = proxy["scale"][ax]
            scale[i] = abs(v[a][i] - v[b][i]) / den
    return pos + o * scale


def rotation_between(a, b):
    a = a / np.linalg.norm(a)
    b = b / np.linalg.norm(b)
    v = np.cross(a, b)
    c = float(np.dot(a, b))
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3)
    k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k * (1.0 / (1.0 + c))


def about(R, p):
    """4x4 rotation R about point p."""
    m = np.eye(4)
    m[:3, :3] = R
    m[:3, 3] = p - R @ p
    return m


def apply4(m, pts):
    return pts @ m[:3, :3].T + m[:3, 3]


# ------------------------------------------------------------------ textures
def texture(src, name, size, keep_alpha=False, mode=None):
    """Resized copy of an asset texture in assets/people_mh/textures; returns the file name."""
    os.makedirs(TEX_OUT, exist_ok=True)
    ext = ".png" if keep_alpha else ".jpg"
    out = name + ext
    dst = os.path.join(TEX_OUT, out)
    if os.path.exists(dst):
        return out
    im = Image.open(src)
    im = im.convert("RGBA" if keep_alpha else "RGB")
    if mode and mode.startswith("nologo"):
        tint = [float(x) for x in mode.split("_")[1].split("-")] if "_" in mode else None
        im = remove_logo(im, tint)
    elif mode == "grey":
        im = to_grey_hair(im)
    im = im.resize((size, size), Image.LANCZOS)
    if keep_alpha:
        im.save(dst, optimize=True)
    else:
        im.save(dst, quality=86, optimize=True)
    return out


def _blur_masked(a, mask, radius):
    """Average colour of the masked pixels around each pixel."""
    m = Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))
    num = Image.fromarray(np.clip(a * mask[..., None], 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(radius))
    w = np.asarray(m).astype(np.float32)[..., None] / 255.0
    return np.asarray(num).astype(np.float32) / np.maximum(w, 1e-3)


def remove_logo(im, tint=None):
    """The CC0 T-shirts carry the MakeHuman logo and orange trims. The texture's pattern pieces are
    found (everything not the grey background), the shirt pieces picked out by their cotton
    colour (sleeves included, jeans not), and inside them anything far from the cotton colour is
    painted out, keeping the weave. Optionally the shirt is dyed another colour."""
    from scipy import ndimage
    a = np.asarray(im).astype(np.float32)
    bgc = a[2, 2]
    bg = np.abs(a - bgc).sum(axis=-1) < 24
    # label shrunken pieces (so touching pieces separate), then give every pixel its nearest label
    core, n = ndimage.label(ndimage.binary_erosion(~bg, iterations=4))
    idx = ndimage.distance_transform_edt(core == 0, return_distances=False, return_indices=True)
    labels = np.where(bg, 0, core[idx[0], idx[1]])
    sizes = ndimage.sum(np.ones_like(labels), labels, index=range(1, n + 1))
    # the shirt colour: the biggest piece in the top half
    top_ids = [i + 1 for i in range(n) if ndimage.center_of_mass(labels == i + 1)[0] < a.shape[0] * 0.45]
    first = max(top_ids, key=lambda i: sizes[i - 1])
    base = np.median(a[labels == first], axis=0)
    lum = a.mean(axis=-1)
    detail = np.abs(lum - ndimage.median_filter(lum, 9))
    texture_of = lambda i: float(np.median(detail[labels == i]))   # robust to trims and seams
    smooth = texture_of(first)
    shirt = np.zeros(labels.shape, bool)
    for i in range(1, n + 1):
        if sizes[i - 1] < 500:
            continue
        med = np.median(a[labels == i], axis=0)
        # same cotton colour, and not the mottled, faded denim
        if np.abs(med - base).sum() < 55 and texture_of(i) < smooth * 1.8 + 0.5:
            shirt |= labels == i
        else:
            # a piece that touches another in the layout (a sleeve against the shorts): keep the
            # smooth, shirt-coloured regions of it, with their trims
            px = (labels == i) & (np.abs(a - base).sum(axis=-1) < 24) & (ndimage.uniform_filter(detail, 9) < smooth * 1.5 + 0.5)
            px = ndimage.binary_opening(px, iterations=3)
            sub, m = ndimage.label(px)
            for j in range(1, m + 1):
                region = sub == j
                if region.sum() > 3000:
                    grown = ndimage.binary_dilation(region, iterations=10) & (labels == i)
                    shirt |= ndimage.binary_fill_holes(ndimage.binary_closing(grown | region, iterations=4)) & (labels == i) & (ndimage.binary_dilation(region, iterations=10))
    shirt = ndimage.binary_fill_holes(shirt)
    near = (np.abs(a - base).sum(axis=-1) < 70) & shirt
    fix = shirt & ~near
    fill = _blur_masked(a, near.astype(np.float32), 40)
    weave = a - np.asarray(Image.fromarray(a.astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))).astype(np.float32)
    a = np.where(fix[..., None], fill + np.roll(weave, 37, axis=1) * 0.8, a)
    if tint is not None:
        lum = a.mean(axis=-1, keepdims=True) / max(float(base.mean()), 1.0)
        a = np.where(shirt[..., None], np.clip(lum * np.array(tint, np.float32), 0, 255), a)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


def to_grey_hair(im):
    a = np.asarray(im).astype(np.float32)
    lum = a[..., :3].mean(axis=-1, keepdims=True)
    lum = 90 + lum * 1.25
    out = a.copy()
    out[..., :3] = np.clip(lum * np.array([0.98, 0.97, 0.95]), 0, 255)
    return Image.fromarray(out.astype(np.uint8))


# ------------------------------------------------------------------ assembly
EXPRESSIONS = {"blink": ["eye-left-closure", "eye-right-closure"], "mouth_open": ["mouth-open"], "smile": ["mouth-corner-puller"]}
TO_GODOT = np.array([-0.1, 0.1, -0.1])   # decimetres -> metres; turned round to face -Z


def build(mh, spec):
    name = spec["name"]
    print("==", name)
    race = spec["race"]
    stack = mh.macro_stack(spec["macro"] | {"race": race})
    v = mh.morph(stack)
    main_race = max(race, key=race.get)
    expr = {}
    for key, units in EXPRESSIONS.items():
        expr[key] = mh.morph([("expression/units/%s/%s" % (main_race, u), 1.0) for u in units], v)

    def asset(kind, aname):
        d = os.path.join(mh.assets, kind, aname)
        files = [f for f in os.listdir(d) if f.endswith(".mhclo") or f.endswith(".proxy")]
        return read_mhclo(os.path.join(d, files[0]))

    parts = []   # (part name, proxy info, material dict, tex mode)
    body = asset("proxymeshes", spec["proxy"])
    skin_dir = os.path.join(mh.assets, "skins", spec["skin"])
    skin_mat = read_mhmat(os.path.join(skin_dir, [f for f in os.listdir(skin_dir) if f.endswith(".mhmat")][0]))
    parts.append(("body", body, skin_mat, None))
    for kind, aname in [("eyes", "low-poly"), ("eyebrows", spec["eyebrows"]), ("eyelashes", spec["eyelashes"])]:
        p = asset(kind, aname)
        if kind == "eyes":
            mat = read_mhmat(os.path.join(mh.assets, "eyes", "materials", spec["eyes"] + ".mhmat"))
        else:
            mat = read_mhmat(os.path.join(p["dir"], p.get("material", aname + ".mhmat")))
        parts.append((kind, p, mat, None))
    if spec.get("hair"):
        p = asset("hair", spec["hair"])
        parts.append(("hair", p, read_mhmat(os.path.join(p["dir"], p["material"])), spec.get("hair_mode")))
    for cl in spec["clothes"]:
        p = asset("clothes", cl)
        parts.append(("clothes:" + cl, p, read_mhmat(os.path.join(p["dir"], p["material"])), spec.get("cloth_mode", {}).get(cl)))

    deleted = set()
    for pname, p, _, _ in parts:
        if pname.startswith("clothes:"):
            deleted.update(p["delete"])

    # --- bones from the joint helpers
    joints = {}
    for b, info in mh.rig.items():
        for end in ("head", "tail"):
            e = info[end]
            if e["strategy"] == "CUBE":
                joints[(b, end)] = mh.joint(v, e["cube_name"])
            else:
                ids = e.get("vertex_indices") or e.get("verts") or []
                joints[(b, end)] = v[ids].mean(axis=0) if ids else np.zeros(3)
    heads = np.array([joints[(b, "head")] for b in mh.bones])
    tails = np.array([joints[(b, "tail")] for b in mh.bones])
    parents = [mh.bones.index(mh.rig[b]["parent"]) if mh.rig[b].get("parent") in mh.rig else -1 for b in mh.bones]

    # --- per-bone re-pose: arms hang straight down
    M = [np.eye(4) for _ in mh.bones]
    bi = {b: i for i, b in enumerate(mh.bones)}
    for side in ("l", "r"):
        # arms hang 10 degrees out from the body, so the hands stay clear of the hips
        out = 1.0 if side == "l" else -1.0          # MakeHuman's left is +X
        down = np.array([np.sin(np.radians(10.0)) * out, -np.cos(np.radians(10.0)), 0.0])
        u, lo, ha = bi["upperarm_" + side], bi["lowerarm_" + side], bi["hand_" + side]
        m_u = about(rotation_between(tails[u] - heads[u], down), heads[u])
        e1 = apply4(m_u, heads[lo][None])[0]
        w1 = apply4(m_u, tails[lo][None])[0]
        m_l = about(rotation_between(w1 - e1, down), e1) @ m_u
        h0 = apply4(m_l, heads[ha][None])[0]
        h1 = apply4(m_l, tails[ha][None])[0]
        m_h = about(rotation_between(h1 - h0, down), h0) @ m_l
        M[u], M[lo], M[ha] = m_u, m_l, m_h
        for b in mh.bones:
            # fingers and thumbs follow the hand
            if b.endswith("_" + side) and any(b.startswith(f) for f in ("thumb", "index", "middle", "ring", "pinky")):
                M[bi[b]] = m_h

    def skin(points, weights):
        out = np.zeros_like(points)
        for b in range(len(mh.bones)):
            wb = weights[:, b]
            if not wb.any():
                continue
            if np.allclose(M[b], np.eye(4)):
                out += points * wb[:, None]
            else:
                out += apply4(M[b], points) * wb[:, None]
        rest = 1.0 - weights.sum(axis=1)
        return out + points * rest[:, None]

    heads_p = np.array([apply4(M[i], heads[i][None])[0] for i in range(len(mh.bones))])
    tails_p = np.array([apply4(M[i], tails[i][None])[0] for i in range(len(mh.bones))])

    # --- fit every part, with its weights and expression shapes
    out_parts = []
    floor = None
    for pname, p, mat, tmode in parts:
        vv, vt, faces, _ = read_obj(os.path.join(p["dir"], p["obj_file"]))
        pos = fit(p, v)
        r, w = p["refs"], p["weights"]
        Wp = mh.W[r[:, 0]] * w[:, 0:1].astype(np.float32) + mh.W[r[:, 1]] * w[:, 1:2].astype(np.float32) + mh.W[r[:, 2]] * w[:, 2:3].astype(np.float32)
        s = Wp.sum(axis=1, keepdims=True)
        Wp = Wp / np.maximum(s, 1e-9)
        shapes = {}
        for key, ev in expr.items():
            d = fit(p, ev) - pos
            if np.abs(d).max() > 0.004:   # 0.4 mm: ignore parts the expression barely touches
                shapes[key] = d
        # hide body skin under clothes
        if pname == "body" and deleted:
            dead = np.array([int(i) in deleted for i in r[:, 0]])
            faces = [f for f in faces if not all(dead[c[0]] for c in f)]
        posed = skin(pos, Wp)
        shapes = {k: skin(pos + d, Wp) - posed for k, d in shapes.items()}
        if pname in ("body",) or pname.startswith("clothes:shoes"):
            lowest = posed[:, 1].min() if pname != "body" else posed[[c[0] for f in faces for c in f], 1].min()
            floor = lowest if floor is None else min(floor, lowest)
        # top four bone weights per vertex
        order = np.argsort(-Wp, axis=1)[:, :4]
        top_w = np.take_along_axis(Wp, order, axis=1)
        top_w = top_w / np.maximum(top_w.sum(axis=1, keepdims=True), 1e-9)
        out_parts.append({"name": pname, "pos": posed, "shapes": shapes, "faces": faces, "uv": vt,
                          "bones": order.astype(np.int32), "bw": top_w.astype(np.float32),
                          "mat": mat, "tmode": tmode, "z_depth": int(p.get("z_depth", 50))})

    # --- convert to metres, Y up, facing -Z, feet on the floor
    def conv(a):
        b = a * TO_GODOT
        b[..., 1] -= floor * 0.1
        return b

    def convd(a):
        return a * TO_GODOT

    os.makedirs(BUILD, exist_ok=True)
    arrays = {"bone_heads": conv(heads_p), "bone_tails": conv(tails_p), "bone_parents": np.array(parents, np.int32)}
    manifest = {"name": name, "bones": mh.bones, "parts": []}
    for i, op in enumerate(out_parts):
        tag = "p%d_" % i
        counts = np.array([len(f) for f in op["faces"]], np.int32)
        fv = np.array([c[0] for f in op["faces"] for c in f], np.int32)
        ft = np.array([c[1] for f in op["faces"] for c in f], np.int32)
        arrays[tag + "pos"] = conv(op["pos"])
        arrays[tag + "counts"] = counts
        arrays[tag + "fv"] = fv
        arrays[tag + "ft"] = ft
        arrays[tag + "uv"] = op["uv"] if len(op["uv"]) else np.zeros((1, 2))
        arrays[tag + "bones"] = op["bones"]
        arrays[tag + "bw"] = op["bw"]
        for k, d in op["shapes"].items():
            arrays[tag + "shape_" + k] = convd(d)
        manifest["parts"].append({"tag": tag, "name": op["name"], "shapes": list(op["shapes"].keys()),
                                  "material": material_for(op["name"], op["mat"], op["tmode"], spec),
                                  "z_depth": op["z_depth"]})
    # anchors the game needs: the lips (for drinking and the whistle) and the eyes
    body_ids = np.array(sorted(mh.groups.get("body", set())))
    # the lips are what the "purse lips" expression moves
    idx, dlt = mh.target("expression/units/%s/mouth-pursing" % main_race)
    mag = np.linalg.norm(dlt, axis=1)
    lip_ids = idx[mag > mag.max() * 0.45]
    mouth = v[lip_ids].mean(axis=0)
    lips = mouth.copy()
    lips[2] = v[lip_ids, 2].max()       # the most forward point of the lips (+Z in MakeHuman)
    anchors = {"mouth": conv(mouth[None])[0].tolist(), "lips": conv(lips[None])[0].tolist(),
               "eye_l": conv(mh.joint(v, "l-eye")[None])[0].tolist(), "eye_r": conv(mh.joint(v, "r-eye")[None])[0].tolist(),
               "height": float(conv(v[body_ids])[:, 1].max())}
    manifest["anchors"] = anchors
    os.makedirs(os.path.join(ROOT, "assets", "people_mh"), exist_ok=True)
    with open(os.path.join(ROOT, "assets", "people_mh", name + ".json"), "w") as f:
        json.dump({"name": name, "gender": "f" if spec["macro"]["gender"] < 0.5 else "m",
                   "age": spec["macro"]["age"], "anchors": anchors, "hair": spec.get("hair", ""),
                   "skin": spec["skin"]}, f, indent=1)
    np.savez_compressed(os.path.join(BUILD, name + ".npz"), **arrays)
    with open(os.path.join(BUILD, name + ".json"), "w") as f:
        json.dump(manifest, f, indent=1)
    tris = sum(int((a - 2).sum()) for k, a in arrays.items() if k.endswith("counts"))
    print("   parts: %s; about %d triangles" % (", ".join(p["name"] for p in manifest["parts"]), tris))


def material_for(pname, mat, tmode, spec):
    """Resized textures and the shading settings Blender should use for this part."""
    d = mat["dir"]
    key = pname.replace("clothes:", "")
    out = {"kind": "opaque", "roughness": 0.75, "tint": [1, 1, 1]}
    diffuse = mat.get("diffuseTexture")
    normal = mat.get("normalmapTexture")
    if pname == "body":
        out.update(kind="skin", roughness=0.55)
        out["albedo"] = texture(os.path.join(d, diffuse), "skin_" + spec["skin"], 1024)
    elif pname == "eyes":
        out.update(kind="eye", roughness=0.08)
        out["albedo"] = texture(os.path.join(d, diffuse), "eye_" + spec["eyes"], 256)
    elif pname in ("eyebrows", "eyelashes", "hair"):
        out.update(kind="alpha", roughness=0.5 if pname == "hair" else 0.7)
        size = 1024 if pname == "hair" else 256
        suffix = ("_" + tmode) if tmode else ""
        out["albedo"] = texture(os.path.join(d, diffuse), pname + "_" + os.path.splitext(diffuse)[0] + suffix, size, keep_alpha=True, mode=tmode)
        if normal and pname == "hair":
            out["normal"] = texture(os.path.join(d, normal), "hairn_" + os.path.splitext(normal)[0], 512)
    elif pname == "teeth":
        out.update(kind="opaque", roughness=0.3)
        out["albedo"] = texture(os.path.join(d, diffuse), "teeth", 256) if diffuse else None
    else:
        suffix = ("_" + tmode) if tmode else ""
        out["albedo"] = texture(os.path.join(d, diffuse), "cloth_" + key + suffix, 1024, mode=tmode)
        if normal:
            out["normal"] = texture(os.path.join(d, normal), "clothn_" + key, 512)
        out["roughness"] = 0.4 if key.startswith("shoes") else 0.85
    return out


def main():
    data_dir, assets_dir = sys.argv[1], sys.argv[2]
    only = sys.argv[3:]
    mh = MakeHuman(data_dir, assets_dir)
    with open(os.path.join(HERE, "characters.json")) as f:
        specs = json.load(f)["characters"]
    for spec in specs:
        if not only or spec["name"] in only:
            build(mh, spec)


if __name__ == "__main__":
    main()
