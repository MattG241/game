#!/usr/bin/env python3
"""Sculpts the session instruments as smooth meshes (assets/instruments/*.obj).

Same method as tools/gen_people.py (signed distances, marching cubes, simplification). Each
instrument is split by material: the varnished body, the dark fittings (fingerboard, tailpiece,
pegs, bridge), and for the drum and banjo the skin. Painting (f-holes, purfling, rosette, frets,
goatskin) is done by assets/shaders/instrument.gdshader from these local coordinates.

Local frames (metres):
  fiddle  : body centre at the origin, scroll towards -Z, chin end +Z, top face +Y
  guitar, banjo : body centre at the origin, neck towards +X, top face (strings) towards -Z
  accordion : bellows between x -0.08..0.08 (scaled in game), ends beyond; keys on the -Z face
  bodhran : drum axis along Z, skin on the -Z face, rim radius 0.22
Requires: numpy, scikit-image, pyfqmr.
"""
import os

import numpy as np

import gen_people as gp
from gen_people import ellipsoid, length, rbox, round_cone, smax, smin, sphere, union

gp.OUT = os.path.join(gp.HERE, "..", "assets", "instruments")
os.makedirs(gp.OUT, exist_ok=True)


def ellipse2(x, z, cx, cz, rx, rz):
    """Approximate signed distance to an ellipse in a plane."""
    qx, qz = (x - cx) / rx, (z - cz) / rz
    k = np.sqrt(qx * qx + qz * qz)
    return (k - 1.0) * min(rx, rz)


# ------------------------------------------------------------------ fiddle
def fiddle_outline(x, z):
    lower = ellipse2(x, z, 0.0, 0.092, 0.102, 0.103)
    upper = ellipse2(x, z, 0.0, -0.088, 0.083, 0.078)
    d = smin(lower, upper, 0.05)
    for s in (-1, 1):
        cbout = ellipse2(x, z, s * 0.098, 0.004, 0.036, 0.05)
        d = smax(d, -cbout, 0.012)
    return d


def fiddle_body(p):
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    d2 = fiddle_outline(x, z)
    arch = np.clip(-d2 / 0.045, 0.0, 1.0)
    arch = arch * arch * (3 - 2 * arch)
    top = 0.0155 + 0.0075 * arch
    slab = np.abs(y) - top
    body = smax(d2, slab, 0.004)
    neck = round_cone(p, (0, 0.012, -0.165), (0, 0.014, -0.3), 0.012, 0.01)
    pegbox = rbox(p, (0, 0.012, -0.33), (0.011, 0.014, 0.026), 0.004)
    scroll = sphere(p, (0, 0.012, -0.365), 0.0165)
    head = union([neck, pegbox, scroll], 0.008)
    bridge = rbox(p, (0, 0.033, 0.035), (0.021, 0.0085, 0.0018), 0.001)
    return union([smin(body, head, 0.006), bridge], 0.002)


def fiddle_fittings(p):
    board = rbox(p, (0, 0.0265, -0.18), (0.0125, 0.0035, 0.132), 0.002)
    tail = rbox(p, (0, 0.027, 0.15), (0.017, 0.0035, 0.038), 0.004)
    chin = ellipsoid(p, (-0.038, 0.026, 0.17), (0.042, 0.009, 0.03))
    pegs = [round_cone(p, (-0.028, 0.014, -0.322 - 0.012 * i), (0.028, 0.014, -0.322 - 0.012 * i), 0.0035, 0.0035)
            for i in range(2)]
    pegs += [sphere(p, (s * 0.03, 0.014, -0.322 - 0.012 * i), 0.0065) for s in (-1, 1) for i in range(2)]
    button = sphere(p, (0, 0.0, 0.197), 0.005)
    return union([board, tail, chin, button] + pegs, 0.002)


# ------------------------------------------------------------------ guitar and banjo
def guitar_body(p):
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    lower = ellipse2(x, y, -0.12, 0.0, 0.205, 0.192)
    upper = ellipse2(x, y, 0.135, 0.0, 0.152, 0.142)
    d2 = smin(lower, upper, 0.07)
    waist = ellipse2(x, y, 0.035, 0.0, 0.04, 0.4)
    d2 = smax(d2, -(waist + 0.115), 0.04) if False else d2
    body = smax(d2, np.abs(z) - 0.05, 0.012)
    neck = rbox(p, (0.46, 0.0, -0.025), (0.2, 0.024, 0.018), 0.01)
    heel = ellipsoid(p, (0.285, 0.0, 0.0), (0.04, 0.03, 0.04))
    head = rbox(p, (0.74, 0.0, -0.035), (0.09, 0.042, 0.009), 0.006)
    return union([body, smin(neck, heel, 0.02), head], 0.01)


def guitar_fittings(p):
    board = rbox(p, (0.43, 0.0, -0.046), (0.24, 0.026, 0.003), 0.002)
    bridge = rbox(p, (-0.17, 0.0, -0.053), (0.014, 0.075, 0.004), 0.003)
    pegs = [sphere(p, (0.69 + 0.04 * i, s * 0.052, -0.035), 0.0075) for s in (-1, 1) for i in range(3)]
    return union([board, bridge] + pegs, 0.002)


def banjo_body(p):
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    r = np.sqrt(x * x + y * y)
    pot = smax(r - 0.14, np.abs(z - 0.01) - 0.045, 0.01)
    hollow = smax(r - 0.122, np.abs(z - 0.03) - 0.03, 0.004)
    pot = smax(pot, -hollow, 0.004)
    rim = smax(np.abs(r - 0.138) - 0.006, np.abs(z + 0.034) - 0.006, 0.002)
    neck = rbox(p, (0.38, 0.0, -0.03), (0.24, 0.02, 0.016), 0.008)
    head = rbox(p, (0.68, 0.0, -0.035), (0.075, 0.034, 0.008), 0.005)
    return union([pot, rim, neck, head], 0.008)


def banjo_head(p):
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    r = np.sqrt(x * x + y * y)
    return smax(r - 0.13, np.abs(z + 0.0355) - 0.003, 0.002)


def banjo_fittings(p):
    board = rbox(p, (0.36, 0.0, -0.049), (0.24, 0.021, 0.003), 0.002)
    bridge = rbox(p, (-0.04, 0.0, -0.041), (0.003, 0.03, 0.005), 0.001)
    tail = rbox(p, (-0.12, 0.0, -0.039), (0.03, 0.012, 0.003), 0.002)
    pegs = [sphere(p, (0.64 + 0.04 * i, s * 0.044, -0.035), 0.007) for s in (-1, 1) for i in range(2)]
    return union([board, bridge, tail] + pegs, 0.002)


# ------------------------------------------------------------------ accordion
def accordion_end(p, keys):
    body = rbox(p, (0, 0, 0), (0.045, 0.15, 0.09), 0.012)
    if keys:
        board = rbox(p, (-0.005, 0.0, -0.095), (0.03, 0.13, 0.012), 0.006)
        body = smin(body, board, 0.008)
    grille = rbox(p, (0, 0.06, 0.0), (0.047, 0.07, 0.07), 0.01)
    return smin(body, grille, 0.005)


def accordion_buttons(p):
    bs = [sphere(p, (-0.005 + (j - 0.5) * 0.02, -0.105 + i * 0.021 + j * 0.01, -0.108), 0.0062)
          for i in range(10) for j in range(2)]
    straps = [rbox(p, (0.05, 0.0, 0.0), (0.004, 0.11, 0.022), 0.003)]
    return union(bs + straps, 0.001)


def accordion_bellows(p):
    x = p[..., 0]
    body = rbox(p, (0, 0, 0), (0.08, 0.142, 0.083), 0.01)
    pleat = 0.0055 * np.abs(np.sin(x * np.pi / 0.0115))
    return body + pleat


# ------------------------------------------------------------------ bodhrán
def bodhran_frame(p):
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    r = np.sqrt(x * x + y * y)
    ring = smax(np.abs(r - 0.216) - 0.0065, np.abs(z) - 0.045, 0.003)
    bar = round_cone(p, (-0.205, 0.0, 0.02), (0.205, 0.0, 0.02), 0.009, 0.009)
    tacks = [sphere(p, (np.cos(a) * 0.223, np.sin(a) * 0.223, -0.036), 0.0035) for a in np.linspace(0, 2 * np.pi, 28, endpoint=False)]
    return union([ring, bar] + tacks, 0.002)


def bodhran_skin(p):
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    r = np.sqrt(x * x + y * y)
    return smax(r - 0.222, np.abs(z + 0.046) - 0.003, 0.002)


def main():
    m = gp.mesh_sdf
    m(fiddle_body, (-0.11, -0.03, -0.39), (0.11, 0.05, 0.21), 0.0022, 3000, "fiddle_body")
    m(fiddle_fittings, (-0.09, -0.01, -0.35), (0.04, 0.04, 0.21), 0.0016, 1400, "fiddle_fittings")
    m(guitar_body, (-0.34, -0.21, -0.07), (0.84, 0.21, 0.07), 0.005, 3000, "guitar_body")
    m(guitar_fittings, (0.15, -0.08, -0.06), (0.8, 0.08, -0.025), 0.0025, 900, "guitar_fittings")
    m(banjo_body, (-0.16, -0.16, -0.07), (0.77, 0.16, 0.07), 0.004, 2600, "banjo_body")
    m(banjo_head, (-0.14, -0.14, -0.046), (0.14, 0.14, -0.024), 0.0025, 500, "banjo_head")
    m(banjo_fittings, (-0.17, -0.06, -0.06), (0.73, 0.06, -0.025), 0.0025, 700, "banjo_fittings")
    m(lambda q: accordion_end(q, False), (-0.07, -0.17, -0.11), (0.07, 0.17, 0.11), 0.004, 900, "accordion_end_l")
    m(lambda q: accordion_end(q, True), (-0.07, -0.17, -0.12), (0.07, 0.17, 0.11), 0.004, 1100, "accordion_end_r")
    m(accordion_buttons, (-0.04, -0.13, -0.12), (0.06, 0.12, 0.03), 0.0018, 1200, "accordion_buttons")
    m(accordion_bellows, (-0.1, -0.16, -0.1), (0.1, 0.16, 0.1), 0.0025, 2200, "accordion_bellows")
    m(bodhran_frame, (-0.235, -0.235, -0.055), (0.235, 0.235, 0.055), 0.0035, 2400, "bodhran_frame")
    m(bodhran_skin, (-0.23, -0.23, -0.056), (0.23, 0.23, -0.036), 0.0025, 500, "bodhran_skin")


if __name__ == "__main__":
    main()
