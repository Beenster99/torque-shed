"""The fuel tanks' bodies, one glb for each shape BikeModel draws (TANK_SHAPES, read from the game's
code so the two never drift apart): teardrop, cafe, peanut, coffin, fatbob, sport, race, touring,
adv and enduro lofted smooth, and the angular gt, streetfighter and wedge folded from flat panels
with a crease at every fold and knee recesses cut in at the back.

Each is drawn at a reference length of 1 m, its origin on the frame line under the nose and running
back along -Y, at the size BikeModel draws a 15 litre tank: the game stretches it to the room
between the head stock and the seat, scales it for the tank's capacity and tilts it to follow the
top tube (BlenderParts.tank_xform). Its filler cap, badges, stripes and pads are still the game's,
laid on the same loft sections.

Over the code's shape: smoother sections, gently rounded ends, the underside tucked in towards the
nose (clear of carburettors and air filters under it), a tunnel under the middle where the top tube
runs, and the seam where the pressings are welded running down each side. All `paint`."""

import math

import kit

SHAPES = kit.gd_const("TANK_SHAPES")

DETAIL = [
    {"rings": 30, "segs": 48, "seam": True},
    {"rings": 14, "segs": 20, "seam": False},
    {"rings": 7, "segs": 10, "seam": False},
]
FACET_RINGS = [40, 20, 7]


def g(x, y, z):
    """A point in the glb's Godot space (x right, y up, z back) as Blender's."""
    return (x, -z, y)


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def key_at(keys, u):
    """BikeModel._key_at: a shape's [half width, rise, drop] at `u` along it."""
    for k0, k1 in zip(keys, keys[1:]):
        if u <= k1[0]:
            f = (u - k0[0]) / max(k1[0] - k0[0], 0.0001)
            f = f * f * (3.0 - 2.0 * f)
            return [k0[i] + (k1[i] - k0[i]) * f for i in (1, 2, 3)]
    return keys[-1][1:4]


def sections(shape, n):
    """The loft sections down the tank: (u, centre height, half width, rise, drop)."""
    out = []
    for i in range(n + 1):
        u = i / n
        w, up, down = key_at(shape["keys"], u)
        out.append((u, down, w, up, down))
    return out


def tunnel(u, down):
    """How far the tunnel under the tank rises into it at `u` along (none at the ends)."""
    return min(0.03, down * 0.45) * smoothstep(0.0, 0.18, u) * (1.0 - smoothstep(0.82, 1.0, u))


def smooth_ring(shape, s, segs, shrink=1.0):
    u, cy, w, up, down = s
    e = 2.0 / shape["n"]
    bw = shape["bw"]
    t = tunnel(u, down)
    # The underside tucked in towards the nose, clear of what sits on the engine under it.
    tuck = 1.0 - 0.22 * (1.0 - smoothstep(0.0, 0.7, u))
    pts = []
    for j in range(segs):
        a = -math.pi * 0.5 + 2.0 * math.pi * j / segs
        ca, sa = math.cos(a), math.sin(a)
        x = math.copysign(abs(ca) ** e, ca) * w * (bw * tuck if sa < 0.0 else 1.0) * shrink
        y = math.copysign(abs(sa) ** e, sa) * (up if sa > 0.0 else down) * shrink
        if sa < 0.0 and t > 0.0:
            # The tunnel: the underside pushed up either side of the middle, over the top tube.
            y += t * max(0.0, 1.0 - (x / 0.045) ** 2) ** 2
        pts.append(g(x, cy + y, u))
    return pts


def facet_ring(shape, s, n_rows):
    """BikeModel._facet_tank's profile, closed under the middle by a flat-topped tunnel."""
    u, cy, w, up, down = s
    bw = shape["bw"]
    knee = shape.get("knee", [])
    k = 0.0
    if len(knee) == 3:
        k = knee[2] * smoothstep(knee[0], knee[0] + 0.05, u) * (1.0 - smoothstep(knee[1] - 0.05, knee[1], u))
    t = min(0.03, down * 0.45)
    half = [(w * bw * 0.6, -down), (w * bw * (1.0 - k), -down * 0.4), (w * (1.0 - k * 0.45), up * 0.18),
        (w * 0.84, up * 0.7), (w * 0.42, up * 0.96), (0.0, up)]
    # Round from the top of the tunnel under the middle, up the left side and down the right.
    prof = [(0.0, -down + t), (-w * bw * 0.35, -down + t)] + [(-x, y) for x, y in half[:-1]] + [half[-1]] + \
        [half[i] for i in range(len(half) - 2, -1, -1)] + [(w * bw * 0.35, -down + t)]
    return [g(x, cy + y, u) for x, y in prof]


def body(shape, lod):
    if shape.get("facet", False):
        rings = [facet_ring(shape, s, 0) for s in sections(shape, FACET_RINGS[lod])]
        ob = kit.skin("body", rings, "paint")
        return [ob], True
    d = DETAIL[lod]
    secs = sections(shape, d["rings"])
    rings = []
    for i, s in enumerate(secs):
        end = i == 0 or i == len(secs) - 1
        if end and lod < 2:
            # Rounded ends: the end section drawn a little smaller, with one full size just in.
            u = s[0] + (0.012 if i == 0 else -0.012)
            w, up, down = key_at(shape["keys"], u)
            full = smooth_ring(shape, (u, down, w, up, down), d["segs"])
            ring = smooth_ring(shape, s, d["segs"], 0.82)
            rings += [ring, full] if i == 0 else [full, ring]
        else:
            rings.append(smooth_ring(shape, s, d["segs"]))
    parts = [kit.skin("body", rings, "paint")]
    if d["seam"]:
        # The seam down each side, a little below the widest point, where the halves are welded.
        for side in (-1.0, 1.0):
            pts = []
            for s in secs[1:-1]:
                u, cy, w, up, down = s
                a = -0.42
                e = 2.0 / shape["n"]
                x = abs(math.cos(a)) ** e * w * shape["bw"] * (1.0 - 0.22 * (1.0 - smoothstep(0.0, 0.7, u))) * 1.004
                y = -(abs(math.sin(a)) ** e) * down * 1.004
                pts.append(g(x * side, cy + y, u))
            parts.append(kit.sweep("seam", pts, 0.0022, 5, "paint"))
    return parts, False


def build(name):
    def make(lod):
        parts, facet = body(SHAPES[name], lod)
        ob = kit.join(parts, "tank")
        if facet:
            kit.sharp_along(ob)
        return ob
    return make


def parts():
    return [{"kind": "tank", "path": "tank/%s.glb" % name, "build": build(name), "mounts": {}} for name in SHAPES]
