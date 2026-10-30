"""The brake discs, one glb for each disc in the catalogue at its own diameter, as BikeModel's
_draw_brake draws them: the rotor and the carrier in the middle of it, with their holes cut right
through (agreement 6b, no see-through texture): a plain disc's five carrier windows, a drilled
disc's three staggered rows of holes and dark carrier, a wave disc's scalloped edge, a floating
disc's rotor on a carrier of its own colour held by ten buttons. The origin is the disc's middle,
its face square to X (the axle); the game puts it at BikeModel's offset from the wheel's middle and
shrinks it only where BikeModel caps it inside the rim.

A drum brake is two pieces: the finned drum (disc/<id>.glb, turning with the wheel) and its
backplate with any air scoop (disc/<id>_plate.glb, on the hub, its outside face to +X)."""

import json
import math
import os

import bmesh
from mathutils import Vector

import kit

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOGUE = os.path.join(HERE, "..", "..", "..", "data", "parts.json")

# BikeModel's holes (DISC_HOLES): rows of [how far out, how many, hole radius, offset].
HOLES = {"drilled": [[0.7, 24, 0.032, 0.0], [0.8, 24, 0.032, 0.5], [0.9, 24, 0.032, 0.0]],
    "floating": [[0.74, 20, 0.03, 0.0], [0.86, 20, 0.03, 0.5]], "wave": [[0.78, 12, 0.034, 0.5]], "round": []}

DETAIL = [
    {"segs": 96, "rows": 7, "holes": True},
    {"segs": 40, "rows": 3, "holes": False},
    {"segs": 12, "rows": 1, "holes": False},
]


def catalogue():
    with open(CATALOGUE) as f:
        return json.load(f)["disc"]


def plate(name, r, r0, r1, thick, segs, rows, tag, solid, edge=None):
    """A flat ring of the disc (`r` its radius) from r0 to r1 of the way out, `thick` thick across X,
    with every cell of its grid where solid(fraction out, angle) is False cut through, and its
    outer edge at edge(angle) of the way out (a wave disc's scallops)."""
    bm = bmesh.new()
    grid = []
    for i in range(rows + 1):
        f = r0 + (r1 - r0) * i / rows
        row = []
        for j in range(segs):
            a = 2.0 * math.pi * j / segs
            e = edge(a) if (edge and i == rows) else 1.0
            row.append((f * e * r * math.cos(a), f * e * r * math.sin(a)))
        grid.append(row)
    keep = set()
    for i in range(rows):
        for j in range(segs):
            fm = r0 + (r1 - r0) * (i + 0.5) / rows
            am = 2.0 * math.pi * (j + 0.5) / segs
            if solid(fm, am):
                keep.add((i, j))
    layers = {}
    for side in (-1.0, 1.0):
        layers[side] = [[bm.verts.new((side * thick * 0.5, y, z)) for y, z in row] for row in grid]
    for i, j in keep:
        k = (j + 1) % segs
        for side in (-1.0, 1.0):
            L = layers[side]
            quad = (L[i][j], L[i][k], L[i + 1][k], L[i + 1][j])
            bm.faces.new(quad if side > 0 else tuple(reversed(quad)))
    # The walls round every edge left open: the rim, the bore, and each hole's sides.
    for i, j in keep:
        k = (j + 1) % segs
        for (a, b), nb in ((((i, j), (i, k)), (i - 1, j)), (((i + 1, k), (i + 1, j)), (i + 1, j)),
                ((((i, k), (i + 1, k))), (i, k)), (((i + 1, j), (i, j)), (i, (j - 1) % segs))):
            if nb in keep:
                continue
            lo, hi = layers[-1.0], layers[1.0]
            bm.faces.new((hi[a[0]][a[1]], lo[a[0]][a[1]], lo[b[0]][b[1]], hi[b[0]][b[1]]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return kit._new_object(name, bm, tag)


def disc(part_id, lod):
    p = catalogue()[part_id]
    style = str(p.get("style", "round"))
    d = DETAIL[lod]
    r = float(p.get("diameter", 280)) / 2000.0
    holes = HOLES.get(style, [])

    def window(f, a):
        # The carrier's spokes: five kidney-shaped windows between the hub and the rotor.
        return 0.27 < f < 0.53 and abs((a * 5.0 + math.pi) % (2.0 * math.pi) - math.pi) < 1.6

    def drilled(f, a):
        if not d["holes"]:
            return False
        for at, n, hr, off in holes:
            for k in range(n):
                c = (k + off) * 2.0 * math.pi / n
                if math.hypot(f * math.cos(a) - at * math.cos(c), f * math.sin(a) - at * math.sin(c)) < hr * 1.1:
                    return True
        return False

    edge = (lambda a: 1.0 - 0.06 * (0.5 + 0.5 * math.cos(a * 12.0))) if style == "wave" else None
    carrier = {"floating": "anodised", "drilled": "black_metal"}.get(style)
    parts = []
    segs = d["segs"]
    if carrier and lod < 2:
        parts.append(plate("rotor", r, 0.6, 1.0, 0.006, segs, max(1, d["rows"] // 2), "raw_steel", lambda f, a: not drilled(f, a), edge))
        parts.append(plate("carrier", r, 0.14, 0.62, 0.008, segs, max(1, d["rows"] // 2), carrier, lambda f, a: lod == 2 or not window(f, a)))
    else:
        parts.append(plate("disc", r, 0.14, 1.0, 0.006, segs, d["rows"], "raw_steel", lambda f, a: lod == 2 or not (window(f, a) or drilled(f, a)), edge))
    if lod < 2:
        if style == "floating":
            for k in range(10):
                a = 2.0 * math.pi * k / 10
                parts.append(kit.tube("button", (0.002, math.cos(a) * r * 0.61, math.sin(a) * r * 0.61), (0.007, math.cos(a) * r * 0.61, math.sin(a) * r * 0.61),
                    0.0045, 8 if lod == 0 else 4, "raw_steel"))
        for k in range(5):
            a = 2.0 * math.pi * k / 5
            parts.append(kit.hex_nut("bolt", (0.003, math.cos(a) * 0.045, math.sin(a) * 0.045), (1.0, 0.0, 0.0), 0.006, 0.004))
    return kit.join(parts, "disc")


def drum_r(p):
    return max(float(p.get("diameter", 180)) / 2000.0 * 1.1, 0.07)


def drum(part_id, lod):
    """The finned drum, its middle on the axle (BikeModel draws it 0.018 m out from the wheel's)."""
    r = drum_r(catalogue()[part_id])
    segs = [48, 24, 10][lod]
    parts = [kit.revolve("drum", [(-0.035, 0.03), (-0.035, r), (0.035, r), (0.035, 0.03)], segs, "cast_alloy")]
    if lod < 2:
        for k in range(5):
            fin = kit.ring("fin", 0.0, r + 0.003, 0.004, segs, "cast_alloy", 5 if lod == 0 else 3)
            fin.rotation_euler = (0.0, 0.0, math.pi * 0.5)
            fin.location = (-0.024 + k * 0.012, 0.0, 0.0)
            parts.append(fin)
    return kit.join(parts, "drum")


def backplate(part_id, lod):
    """The drum's backplate, dished out to +X, and the air scoop on the front of a racing one
    (scooping from the -Y side here; the game turns it to face forward)."""
    p = catalogue()[part_id]
    r = drum_r(p)
    segs = [48, 20, 8][lod]
    parts = [kit.revolve("plate", [(-0.006, 0.0), (-0.006, r * 0.98), (0.006, r * 0.85), (0.006, 0.0)], segs, "cast_alloy")]
    if str(p.get("shoes", "sls")) != "sls" and lod < 2:
        parts.append(kit.prism("scoop", kit.rounded_rect(r * 0.175, r * 0.125, 0.008, 3 if lod == 0 else 1), 0.0, 0.012, "black_metal",
            plane="YZ", at=(0.006, r * 0.55, r * 0.35)))
        if lod == 0:
            parts.append(kit.prism("mesh", kit.rounded_rect(r * 0.15, r * 0.1, 0.006, 3), 0.0, 0.002, "raw_steel", plane="YZ", at=(0.0175, r * 0.55, r * 0.35)))
    return kit.join(parts, "backplate")


def parts():
    out = []
    centre = {"axle": ((0.0, 0.0, 0.0), (1.0, 0.0, 0.0))}
    for part_id, p in catalogue().items():
        if p.get("style") == "drum":
            out.append({"kind": "disc", "path": "disc/%s.glb" % part_id, "build": lambda lod, i=part_id: drum(i, lod), "mounts": centre})
            out.append({"kind": "disc", "path": "disc/%s_plate.glb" % part_id, "build": lambda lod, i=part_id: backplate(i, lod), "mounts": centre})
        else:
            out.append({"kind": "disc", "path": "disc/%s.glb" % part_id, "build": lambda lod, i=part_id: disc(i, lod), "mounts": centre})
    return out
