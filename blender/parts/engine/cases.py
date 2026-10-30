"""The engines' crankcases (the engine kind), one glb for each engine in the catalogue: the
rounded cast case, split down the middle (across it on the Japanese-style rows), the alternator
cover bulging out of the left, the ignition cover on the right, and the finned sump under it (a
two-stroke's expansion bulge instead); a V-twin's cam chest nose cone and its pushrod tubes up to
the heads, a four's or triple's cam chain tunnel and starter motor.

Drawn at the reference 700 cc size, the origin on the engine's middle (BikeModel's _engine_c), and
scaled by the engine's size (_eng_s) as BikeModel scales its own. The sizes are BikeModel's
(_draw_engine): the case is _block_w wide (by the layout and how many cylinders), 0.26 m tall and
0.34 m long."""

import json
import math
import os

import kit

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOGUE = os.path.join(HERE, "..", "..", "..", "data", "parts.json")

DETAIL = [
    {"ring": 48, "round": 24, "fins": 4, "bolts": True},
    {"ring": 20, "round": 12, "fins": 2, "bolts": False},
    {"ring": 10, "round": 8, "fins": 0, "bolts": False},
]
# Down the case, nose to tail: (how far along, how full), its ends rounded off (BikeModel's own
# sections, with more of them close up).
SECTIONS = [
    [(0.0, 0.7), (0.02, 0.86), (0.07, 0.95), (0.15, 0.99), (0.25, 1.0), (0.75, 1.0), (0.85, 0.99), (0.93, 0.95), (0.98, 0.86), (1.0, 0.7)],
    [(0.0, 0.78), (0.07, 0.95), (0.25, 1.0), (0.75, 1.0), (0.93, 0.95), (1.0, 0.78)],
    [(0.0, 0.8), (0.2, 1.0), (0.8, 1.0), (1.0, 0.8)],
]


def block_w(engine):
    """The case's width at the reference size (BikeModel's _block_w over _eng_s)."""
    layout = engine["layout"]
    if layout == "vtwin":
        return 0.22
    if layout == "boxer":
        return 0.24
    return 0.2 + 0.11 * (int(engine["cylinders"]) - 1)


def size(engine):
    """The engine's size against a 700 cc (BikeModel's _eng_s outside a cruiser's frame)."""
    return min(max((float(engine["displacement"]) / 700.0) ** 0.3, 0.55), 1.2)


def cylinder_ups(engine):
    """A V-twin's two cylinders' directions (Blender axes), as BikeModel lays them out outside a
    cruiser's frame, with where each barrel's base sits."""
    v = float(engine.get("v_angle", 0.0))
    out = []
    for d in (-1.0, 1.0):
        if 0.0 < v < 90.0:
            half = math.radians(v) * 0.5
            up = (0.0, -math.sin(half) * d, math.cos(half))
        else:
            n = math.hypot(math.cos(0.6), 0.6)
            up = (0.0, -0.6 * d / n, math.cos(0.6) / n)
        base = (0.0, -0.07 * d + up[1] * 0.12, 0.13 + up[2] * 0.12)
        out.append((base, up))
    return out


def case(engine, lod, parts):
    """BikeModel scales the case with the engine but not every piece on it (a cover's depth, the
    starter's size): those are divided by the engine's size here, `k`, to come out the same."""
    d = DETAIL[lod]
    k = 1.0 / size(engine)
    layout = engine["layout"]
    half = block_w(engine) * 0.5
    secs = [(0.17 - 0.34 * f, half * g, 0.13 * g, 0.13 * g, 3.6) for f, g in SECTIONS[lod]]
    parts.append(kit.loft("case", secs, d["ring"], "cast_alloy"))
    if lod < 2:
        # The split: across the middle on a Japanese-style row, down the middle on the rest.
        if layout in ("parallel", "triple", "inline"):
            seam = [(y, hw * 1.005, 0.004, 0.004, 3.6) for y, hw, up, down, n in secs[1:-1]]
        else:
            seam = [(y, 0.003, up * 1.005, down * 1.005, 3.6) for y, hw, up, down, n in secs[1:-1]]
        parts.append(kit.loft("seam", seam, d["ring"], "cast_alloy"))
    # The alternator cover on the left, held on by a ring of bolts, and the ignition cover on the right.
    for x, r, depth, y, z, bolts in ((-half - 0.012 * k, 0.085, 0.026 * k, 0.06, -0.015, 6), (half + 0.008 * k, 0.042, 0.018 * k, 0.12, -0.03, 3)):
        side = 1.0 if x > 0 else -1.0
        a = (x - side * depth * 0.5, y, z)
        b = (x + side * depth * 0.5, y, z)
        parts.append(kit.tube("cover", a, b, r, d["round"] * 2, "polished_alloy", 0.004 if lod == 0 else 0.0, r * 0.9))
        if d["bolts"]:
            for i in range(bolts):
                t = 2.0 * math.pi * i / bolts + 0.3
                at = (b[0], y + math.cos(t) * r * 0.82, z + math.sin(t) * r * 0.82)
                # (Set into the cover a little, as BikeModel keeps its covers' bolts close.)
                at = (at[0] - side * 0.002 * k, at[1], at[2])
                parts.append(kit.hex_nut("bolt", at, (side, 0.0, 0.0), 0.0055 * k, 0.004 * k))
    if layout == "2stroke":
        parts.append(kit.prism("bulge", kit.rounded_rect(block_w(engine) * 0.35, 0.12, 0.03, 4 if lod < 2 else 1), -0.16 - 0.03 * k, -0.16 + 0.03 * k, "cast_alloy",
            0.006 if lod == 0 else 0.0, 2, at=(0.0, -0.02 * k, 0.0)))
    else:
        # (BikeModel stops a sump growing past 0.16 m wide however big the engine, so it's drawn
        # narrower for the big ones here, where the whole case is scaled with the engine.)
        w = min(block_w(engine) * 0.55, 0.16 / size(engine))
        parts.append(kit.prism("sump", kit.rounded_rect(w * 0.5, 0.11, 0.012, 3 if lod < 2 else 1), -0.162, -0.125, "cast_alloy",
            0.003 if lod == 0 else 0.0, at=(0.0, 0.01, 0.0)))
        for i in range(d["fins"]):
            x = -w * 0.38 + w * 0.76 * i / max(d["fins"] - 1, 1)
            parts.append(kit.prism("sumpfin", kit.rounded_rect(0.0025, 0.1, 0.002, 1), -0.172, -0.16, "cast_alloy", at=(x, 0.01, 0.0)))
        if lod < 2:
            parts.append(kit.hex_nut("drain", (0.0, -0.06, -0.162), (0.0, 0.0, -1.0), 0.011, 0.012))
    if layout == "vtwin":
        # The cam chest's chrome nose cone, and a pair of pushrod tubes up to each head.
        parts.append(kit.sphere("cone", (half + 0.006, 0.02, 0.03), 0.07, (0.28, 1.35, 0.85), d["round"], "chrome", 0.5))
        if lod < 2:
            # (Up to just above where the barrel starts on the most squat V a frame makes, 60 degree
            # twins in a cruiser's bay with their heads at 0.72, so the tubes stay on the barrels.)
            chest = (half * 0.42, -0.01, 0.11)
            for base, up in cylinder_ups(engine):
                low = 0.12 * 0.72 + 0.02
                head = (half * 0.42, base[1] + up[1] * (low - 0.12), base[2] + up[2] * (low - 0.12))
                for dy in (-0.013, 0.013):
                    parts.append(kit.tube("pushrod", (chest[0], chest[1] + dy, chest[2]), (head[0], head[1] + dy, head[2]), 0.007, d["round"] // 2 + 2, "chrome"))
    elif layout in ("inline", "triple"):
        parts.append(kit.prism("tunnel", kit.rounded_rect(0.03 * k, 0.02 * k, 0.008 * k, 3 if lod < 2 else 1), 0.06, 0.14, "cast_alloy", at=(0.0, 0.12, 0.0)))
        if lod < 2:
            parts.append(kit.tube("starter", (-half * 0.4 - 0.06 * k, -0.12, 0.14), (-half * 0.4 + 0.06 * k, -0.12, 0.14), 0.03 * k, d["round"], "black_metal",
                0.003 * k if lod == 0 else 0.0))


def parts():
    with open(CATALOGUE) as f:
        engines = json.load(f)["engine"]
    out = []
    for engine_id, engine in sorted(engines.items()):
        def build(lod, engine=engine):
            pieces = []
            case(engine, lod, pieces)
            return kit.join(pieces, "lod%d" % lod)
        out.append({"kind": "engine", "path": "engine/%s.glb" % engine_id, "build": build, "mounts": {"engine": ((0.0, 0.0, 0.0), (0.0, 0.0, 1.0))}})
    return out
