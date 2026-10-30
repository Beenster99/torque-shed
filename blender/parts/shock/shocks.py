"""The rear shocks, one glb for each in the catalogue (agreement 6b): from mount_top, the origin, down
-Z to mount_bottom, at a reference length the game stretches between BikeModel's two shock points
(a twin's eye to eye about as long as BikeModel draws them, a mono's too, so the stretch stays
small). A twin shock is a chrome damper body and rod inside a coil spring in the part's colour, an
eye at each end; a mono a black body with a remote reservoir alongside, a fatter spring and an
anodised preload collar. The game draws them moving with the swingarm, as it does its own."""

import json
import math
import os

import kit

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOGUE = os.path.join(HERE, "..", "..", "..", "data", "parts.json")

# Eye to eye (m) for each layout.
LENGTH = {"twin": 0.34, "mono": 0.3}

DETAIL = [{"round": 14, "wire": 6, "per_coil": 14}, {"round": 8, "wire": 4, "per_coil": 8}, {"round": 6, "wire": 0, "per_coil": 0}]


def catalogue():
    with open(CATALOGUE) as f:
        return json.load(f)["shock"]


def coil(name, z0, z1, r, wire, turns, d, tag):
    """A coil spring round Z from z0 down to z1 (z1 < z0), `r` to the wire's middle."""
    pts = []
    n = int(turns * d["per_coil"])
    for i in range(n + 1):
        a = 2.0 * math.pi * turns * i / n
        pts.append((math.cos(a) * r, math.sin(a) * r, z0 + (z1 - z0) * i / n))
    return kit.sweep(name, pts, wire, d["wire"], tag)


def eye(name, z, r, d):
    """A mounting eye across X at height z, with its bush."""
    return kit.tube(name, (-0.014, 0.0, z), (0.014, 0.0, z), r, d["round"], "raw_steel")


def shock(part_id, lod):
    p = catalogue()[part_id]
    d = DETAIL[lod]
    twin = p.get("layout", "mono") == "twin"
    L = LENGTH["twin" if twin else "mono"]
    # (Far off, lod2, a shock is just its body, rod and spring.)
    parts = [] if lod == 2 else [eye("top_eye", 0.0, 0.013 if twin else 0.016, d), eye("bottom_eye", -L, 0.013 if twin else 0.016, d)]
    if twin:
        # The damper body down from the top, the rod out of it to the bottom eye.
        parts.append(kit.tube("body", (0.0, 0.0, -0.01), (0.0, 0.0, -L * 0.6), 0.019, d["round"], "chrome"))
        parts.append(kit.tube("rod", (0.0, 0.0, -L * 0.6), (0.0, 0.0, -L + 0.012), 0.008, max(6, d["round"] // 2), "chrome"))
        # Spring seats, and the spring between them.
        for z in (-L * 0.08, -L * 0.75) if lod < 2 else ():
            parts.append(kit.tube("seat", (0.0, 0.0, z + 0.003), (0.0, 0.0, z - 0.003), 0.031, d["round"], "chrome"))
        if d["wire"]:
            parts.append(coil("spring", -L * 0.08 - 0.004, -L * 0.75 + 0.004, 0.026, 0.0042, 8.5, d, "paint"))
        else:
            parts.append(kit.tube("spring", (0.0, 0.0, -L * 0.08), (0.0, 0.0, -L * 0.75), 0.028, d["round"], "paint"))
        return kit.join(parts, "shock")
    parts.append(kit.tube("body", (0.0, 0.0, -0.012), (0.0, 0.0, -L * 0.62), 0.022, d["round"], "black_metal"))
    parts.append(kit.tube("rod", (0.0, 0.0, -L * 0.62), (0.0, 0.0, -L + 0.014), 0.009, max(6, d["round"] // 2), "chrome"))
    if lod < 2:
        # The remote reservoir alongside the top, on a short hose block.
        parts.append(kit.tube("reservoir", (0.034, 0.0, -0.02), (0.034, 0.0, -L * 0.36), 0.015, d["round"], "anodised"))
        parts.append(kit.tube("block", (0.0, 0.0, -0.03), (0.034, 0.0, -0.03), 0.009, max(6, d["round"] // 2), "black_metal"))
    # The preload collar at the top of the spring, the seat at its foot.
    if lod < 2:
        parts.append(kit.tube("collar", (0.0, 0.0, -L * 0.09), (0.0, 0.0, -L * 0.1 - 0.012), 0.036, d["round"], "anodised"))
        parts.append(kit.tube("seat", (0.0, 0.0, -L * 0.7 + 0.003), (0.0, 0.0, -L * 0.7 - 0.003), 0.04, d["round"], "black_metal"))
    if d["wire"]:
        parts.append(coil("spring", -L * 0.1 - 0.014, -L * 0.7 + 0.004, 0.032, 0.0058, 7.0, d, "paint"))
    else:
        parts.append(kit.tube("spring", (0.0, 0.0, -L * 0.1), (0.0, 0.0, -L * 0.7), 0.036, d["round"], "paint"))
    return kit.join(parts, "shock")


def parts():
    out = []
    for part_id, p in catalogue().items():
        L = LENGTH["twin" if p.get("layout", "mono") == "twin" else "mono"]
        out.append({"kind": "shock", "path": "shock/%s.glb" % part_id, "build": lambda lod, i=part_id: shock(i, lod),
            "mounts": {"top": ((0.0, 0.0, 0.0), (0.0, 0.0, 1.0)), "bottom": ((0.0, 0.0, -L), (0.0, 0.0, -1.0))}})
    return out
