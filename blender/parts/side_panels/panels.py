"""The side panels, one glb for each style BikeModel draws but the oval number boards (which carry
the race number the game prints on them): "triangle", a classic's pressed-steel side cover, domed
and taller at the front, with a chrome badge; "mx", a flat plastic plate; "cowl", a raked panel
with a chrome trim strip; "chrome", a domed round cover. Each is the right-hand panel, its origin
where BikeModel puts that side's panel and drawn for a seat 0.2 m above the swingarm pivot
(BikeModel's h): the game scales it up and down for the bike's own h (and across for the round
cover) and mirrors it for the left.

Tags: the panel `paint` (the game gives it the part's own finish), trim and badge `chrome`."""

import math

import kit

H = 0.2                   # m: the reference panel height BikeModel works from
DETAIL = [{"round": 32, "rings": 6}, {"round": 16, "rings": 3}, {"round": 8, "rings": 1}]


def g(x, y, z):
    """A point in the glb's Godot space (x out, y up, z back) as Blender's."""
    return (x, -z, y)


def turned(p, rot):
    """`p` (x, y, z) turned `rot` about X, as BikeModel turns a panel by its rotation.x."""
    x, y, z = p
    c, s = math.cos(rot), math.sin(rot)
    return (x, y * c - z * s, y * s + z * c)


def dome(name, outline, centre, dome_x, thick, rings, tag, rot=0.0, at=(0.0, 0.0, 0.0)):
    """A pressed panel: the closed `outline` [(y, z)] domed out along +X by up to `dome_x` in the
    middle, `thick` at the edge, flat behind; turned `rot` about X and moved to `at`."""
    cy, cz = centre
    ringpts = []
    for i in range(rings + 1):
        s = 1.0 - i / (rings + 1)
        x = thick + dome_x * (1.0 - s * s)
        ringpts.append([(x, cy + (y - cy) * s, cz + (z - cz) * s) for y, z in outline])
    # The edge rolled round to the flat back.
    back = [(0.0, y, z) for y, z in outline]
    rings_all = [back] + ringpts
    def place(p):
        q = turned(p, rot)
        return g(q[0] + at[0], q[1] + at[1], q[2] + at[2])
    return kit.skin(name, [[place(p) for p in r] for r in rings_all], tag)


def rounded(hy, hz, n, segs, cy=0.0, cz=0.0, taller=None):
    """A superellipse outline [(y, z)], `taller(z)` stretching it up and down along its length."""
    out = []
    for k in range(segs):
        t = 2.0 * math.pi * k / segs
        c, s = math.cos(t), math.sin(t)
        z = cz + hz * math.copysign(abs(c) ** (2.0 / n), c)
        tall = taller(z) if taller else 1.0
        out.append((cy + hy * tall * math.copysign(abs(s) ** (2.0 / n), s), z))
    return out


def triangle(lod):
    d = DETAIL[lod]
    def tall(z):
        f = (z + 0.1) / 0.2
        return (1.0 - 0.3 * f) * (0.75 + 0.25 * math.sin(math.pi * min(max(f * 1.2, 0.0), 1.0)))
    def lift(z):
        return 0.12 * H * (z + 0.1) / 0.2
    pts = rounded(H * 0.5, 0.1, 4.5, d["round"] * 2, taller=tall)
    outline = [(y + lift(z), z) for y, z in pts]
    parts = [dome("panel", outline, (lift(0.0), 0.0), 0.012, 0.004, d["rings"], "paint")]
    if lod < 2:
        parts.append(kit.sphere("badge", g(0.018, 0.012, -0.02), 0.022, (0.25, 1.5, 1.0), max(8, d["round"] // 2), "chrome"))
    return kit.join(parts, "panel")


def mx(lod):
    d = DETAIL[lod]
    outline = rounded(H * 1.15 * 0.5, 0.17, 6.0, d["round"] * 2)
    return kit.join([dome("plate", outline, (0.0, 0.0), 0.006, 0.005, d["rings"], "paint", -0.18, (0.012, -0.01, 0.1))], "panel")


def cowl(lod):
    d = DETAIL[lod]
    outline = rounded(H * 0.85 * 0.5, 0.18, 5.0, d["round"] * 2)
    parts = [dome("cowl", outline, (0.0, 0.0), 0.01, 0.006, d["rings"], "paint", 0.32, (0.008, 0.03, -0.03))]
    if lod < 2:
        parts.append(kit.tube("trim", g(0.016, -H * 0.25, -0.17), g(0.016, -H * 0.25, 0.13), 0.004, 6, "chrome"))
    return kit.join(parts, "panel")


def chrome(lod):
    d = DETAIL[lod]
    outline = rounded(H * 0.45, H * 0.45 * 1.2, 2.0, d["round"] * 2)
    return kit.join([dome("cover", outline, (0.0, 0.0), 0.016, 0.004, d["rings"], "paint", 0.0, (0.01, -0.01, -0.02))], "panel")


def parts():
    return [{"kind": "side_panels", "path": "side_panels/%s.glb" % name, "build": build, "mounts": {}}
        for name, build in (("triangle", triangle), ("mx", mx), ("cowl", cowl), ("chrome", chrome))]
