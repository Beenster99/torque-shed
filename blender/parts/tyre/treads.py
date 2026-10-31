"""The tyres, one glb for each tread pattern: a section of the hoop the game bends round each tyre
at its own size (BlenderParts.tyre_hoop), as a tyre's size comes from the wheel as well as the
tyre. A section is drawn in units of the tyre (agreement 6b): X from -1 to 1 across its width, Z
from 0 at the bead to 1 at the crown, and -Y from 0 to 1 over 1/32 of the way round. The carcass is
BikeModel's (tyre_mesh): sidewalls bulging out to the full width 40% of the way up, then the crown,
rounder on a road tyre and squarer on an off-road one.

Road patterns are grooves pressed into the crown; off-road ones knobs (or bigger, flatter blocks on
a 50/50 tyre, with a tungsten stud in each on a studded one) standing off a carcass sunk to leave
them as tall as BikeModel's. The sizes in metres are at a reference tyre 0.1 m tall."""

import math

import bmesh
import bpy  # noqa: F401
from mathutils import Vector

import kit

H_REF = 0.1                # m: the reference tyre's height off the bead
SECTIONS = 32              # sections round a tyre
TREADS = ["slick", "rib", "touring", "sport", "cruiser", "trail", "sipes", "knobs", "blocks", "studs"]
OFFROAD = ["knobs", "blocks", "studs"]

DETAIL = [
    {"along": 6, "crown": 10, "wall": 4},
    {"along": 2, "crown": 4, "wall": 2},
    {"along": 1, "crown": 2, "wall": 1},
]


def profile(tread, d):
    """The carcass's section from the left bead over the crown to the right, as (across, up) in the
    tyre's units, and which points are on the crown (where the tread is)."""
    sq = 2.8 if tread in OFFROAD else 2.0
    # (Knobs stand off a carcass sunk under them, so their tops are where BikeModel's are.)
    top = 1.0 - (0.19 if tread in ("knobs", "studs") else 0.1 if tread == "blocks" else 0.0)
    bulge = 0.434
    side = []
    for i in range(d["wall"]):
        t = i / d["wall"]
        side.append((0.9 + 0.1 * math.sin(t * math.pi * 0.5), bulge * (1.0 - math.cos(t * math.pi * 0.5))))
    crown = []
    n = d["crown"] // 2
    for i in range(n + 1):
        th = i / n * math.pi * 0.5
        c = math.cos(th) ** (2.0 / sq)
        s = math.sin(th) ** (2.0 / sq)
        crown.append((c, bulge + (top - bulge) * s))
    right = side + crown
    left = [(-x, y) for x, y in reversed(right[:-1])]
    pts = left + right
    on_crown = [abs(x) < 0.97 and y > bulge + 0.05 for x, y in pts]
    return pts, on_crown


def groove(tread, u, x):
    """How deep (in the tyre's units) a road tread's groove is at `u` along the section and `x`
    across: ribs round it, diagonal sport grooves, a touring tyre's ribs and sipes, a trail
    tyre's blocks, a winter tyre's sipes."""
    ax = abs(x)
    deep = 0.025
    # (Kept off the shoulders, so the tyre's outline stays smooth however it's leant over.)
    if ax > 0.75:
        return 0.0
    if tread == "rib":
        return deep if min(abs(ax - 0.0), abs(ax - 0.45)) < 0.08 else 0.0
    if tread == "touring":
        if abs(ax - 0.3) < 0.08:
            return deep
        return deep * 0.6 if 0.45 < ax < 0.9 and abs((u * 2.0 + ax) % 1.0 - 0.5) < 0.12 else 0.0
    if tread == "sport":
        return deep if 0.15 < ax < 0.9 and abs((u * 2.0 + ax * 0.8) % 1.0 - 0.5) < 0.14 else 0.0
    if tread == "cruiser":
        if ax < 0.07:
            return deep
        return deep if 0.2 < ax < 0.85 and abs((u * 2.0 - ax * 0.6) % 1.0 - 0.5) < 0.13 else 0.0
    if tread == "trail":
        return deep if (u * 3.0) % 1.0 < 0.2 or abs(ax - 0.35) < 0.07 else 0.0
    if tread == "sipes":
        return deep * 0.6 if (u * 3.0) % 1.0 < 0.18 and ax < 0.9 else 0.0
    return 0.0


def carcass(tread, lod):
    d = dict(DETAIL[lod])
    if tread in OFFROAD and lod == 0:
        # (Its knobs take the triangles a road tyre's pressed grooves need along it.)
        d["along"] = 3
    pts, on_crown = profile(tread, d)
    bm = bmesh.new()
    rows = []
    for i in range(d["along"] + 1):
        u = i / d["along"]
        row = []
        for (x, y), crown in zip(pts, on_crown):
            dy = groove(tread, u, x) if crown and lod == 0 else 0.0
            row.append(bm.verts.new((x, -u, y - dy)))
        rows.append(row)
    for a, b in zip(rows, rows[1:]):
        for j in range(len(pts) - 1):
            bm.faces.new((a[j], b[j], b[j + 1], a[j + 1]))
    # (Open all round: the beads sit in the rim and the ends run on into the next section. The
    # faces point out, away from the middle of the section.)
    for f in bm.faces:
        c = f.calc_center_median()
        if f.normal.dot(Vector((c.x, 0.0, c.z - 0.3))) < 0.0:
            f.normal_flip()
    return kit._new_object("carcass", bm, "rubber")


def crown_at(tread, x):
    """The carcass's height at `x` across (lod0's crown), for setting knobs on it."""
    pts, _ = profile(tread, DETAIL[0])
    best = min(pts, key=lambda p: abs(p[0] - x) + (0.0 if p[1] > 0.4 else 10.0))
    return best[1]


def knob(name, x, u, w, length, h, tread, tilt=0.0):
    """A knob `w` across and `length` along (tyre units), standing `h` off the carcass at (x, u),
    leaning out by `tilt` on the shoulder. Five faces: its foot is in the rubber."""
    base = crown_at(tread, x) - 0.02
    bm = bmesh.new()
    lo = [bm.verts.new((x + sx * w * 0.5, -(u + sy * length * 0.5), base)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    hi = [bm.verts.new((x + sx * w * 0.42 + tilt, -(u + sy * length * 0.42), base + h + 0.02)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    bm.faces.new(hi)
    for i in range(4):
        j = (i + 1) % 4
        bm.faces.new((lo[i], lo[j], hi[j], hi[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        if f.normal.z < -0.5:
            f.normal_flip()
    return kit._new_object(name, bm, "rubber")


def section(tread, lod):
    parts = [carcass(tread, lod)]
    if tread in OFFROAD and lod < 2:
        blocks = tread == "blocks"
        h = 0.1 if blocks else 0.19
        w = 0.84 if blocks else 0.72
        length = 0.75 if blocks else 0.5
        # Two staggered across the middle (BikeModel's), and a smaller one on each shoulder, leaning out.
        spots = [(0.2 if blocks else 0.38, 0.25, w * 0.6, length, 0.0), (-(0.2 if blocks else 0.38), 0.75, w * 0.6, length, 0.0)]
        if lod == 0:
            spots += [(0.82, 0.75, 0.3, length * 0.8, 0.04), (-0.82, 0.25, 0.3, length * 0.8, -0.04)]
        for x, u, kw, kl, tilt in spots:
            parts.append(knob("knob", x, u, kw, kl, h, tread, tilt))
            if tread == "studs" and lod == 0:
                top = crown_at(tread, x) + h
                parts.append(kit.tube("stud", (x + tilt, -u, top - 0.02), (x + tilt, -u, top + 0.03), 0.035, 6, "raw_steel"))
    return kit.join(parts, "tyre")


def parts():
    out = []
    for tread in TREADS:
        def build(lod, tread=tread):
            return section(tread, lod)
        out.append({"kind": "tyre", "path": "tyre/%s.glb" % tread, "build": build, "mounts": {}})
    return out
