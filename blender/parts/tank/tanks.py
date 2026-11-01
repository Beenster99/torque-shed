"""The fuel tanks, rig built (bodywork track H3): one glb for each shape BikeModel draws
(TANK_SHAPES, read from the game's code so the two never drift apart). Teardrop, cafe, peanut,
coffin, fatbob, sport, race, touring, adv and enduro are lofted smooth; the angular gt,
streetfighter and wedge are folded from flat panels with a crease at every fold.

Each tank is a shape plus a tunnel, as a real one is pressed: the shell's underside is a flat
floor either side of a channel that straddles the frame's backbone. The glb is drawn at a
reference length of 1 m and the size BikeModel draws a 15 litre tank, its origin on the tunnel's
roof under the nose and the roof running straight back along -Y (the game's +Z): the game bends
that line along the rig's tank floor (BikeModel.rig "tank_floor", lines agreement 3), so the
tunnel sits on the backbone whatever its shape, and stretches the tank from the nose to the rear.

Shape keys (glTF morph targets, Godot blend shapes) that the game sets per bike:
- `tunnel_height`: the flanks and floor 60 mm lower, to cover a deeper backbone or spars;
- `tunnel_width`: the channel 50 mm wider each side (twin top tubes, a wide airbox lid);
- `tunnel_length`: the tunnel open right out of the back; at 0 it closes from 80% of the
  length, where the frame drops away under the tank's rear;
- `nose_reach`: the nose's two cheeks reaching 120 mm further forward round the head stock,
  the middle left where it is;
- `knee_fore`, `knee_aft`: knee recesses 30 mm deep in the lower flanks centred at 58% and 84%
  of the length. The game mixes the two to put the recess at the rider's knee.

The underside stays closed and smooth, with no welded seam or rolled ends to catch the spray:
tanks are painted all over in the booth (see SprayJob). All `paint`."""

import math

import kit

SHAPES = kit.gd_const("TANK_SHAPES")

DETAIL = [
    {"rings": 30, "arc": 20},
    {"rings": 14, "arc": 8},
    {"rings": 6, "arc": 3},
]
FACET_RINGS = [40, 20, 6]

BASE = {"T": 0.035, "tw": 0.035, "ut": 0.8, "reach": 0.0, "kf": 0.0, "ka": 0.0}
KEYS = {
    "tunnel_height": {"T": 0.095},
    "tunnel_width": {"tw": 0.085},
    "tunnel_length": {"ut": 1.25},
    "nose_reach": {"reach": 0.12},
    "knee_fore": {"kf": 0.03},
    "knee_aft": {"ka": 0.03},
}
LIP = 0.014               # m of flat floor kept outside the tunnel each side
NOSE = 0.25               # share of the length the nose's reach fades over
KNEES = ((0.58, "kf"), (0.84, "ka"))
KNEE_SPAN = 0.13          # share of the length either side of a knee's middle


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


def knee_at(p, u):
    """How far (m) the knee recesses pull the flank in at `u`."""
    d = 0.0
    for mid, name in KNEES:
        f = 1.0 - smoothstep(0.0, KNEE_SPAN, abs(u - mid))
        d += p[name] * f
    return d


def own_knee(shape, u):
    """A faceted shape's own knee cut ("knee": [from, to, depth] along the length)."""
    knee = shape.get("knee", [])
    if len(knee) != 3:
        return 0.0
    return knee[2] * smoothstep(knee[0], knee[0] + 0.05, u) * (1.0 - smoothstep(knee[1] - 0.05, knee[1], u))


def tunnel(p, u, x_end, y_end, tw, lod=0):
    """The floor and tunnel from the end of the flank (`x_end`, `y_end`) in to the roof's middle,
    the right half, without the middle point. Open, the roof is at 0; behind `p["ut"]` the
    tunnel closes, its points laid flat along the floor."""
    open_ = 1.0 - smoothstep(p["ut"] - 0.12, p["ut"], u)
    wall = y_end * 0.45
    if lod == 2:
        pts = [(tw, y_end), (tw * 0.8, 0.0)]
    else:
        pts = [(x_end * 0.5 + tw * 0.5, y_end), (tw, y_end), (tw, wall), (tw * 0.98, y_end * 0.08), (tw * 0.7, 0.0)]
    n = len(pts)
    flat = [(x_end * (1.0 - (j + 1.0) / (n + 1.0)), y_end) for j in range(n)]
    return [(f[0] + (o[0] - f[0]) * open_, f[1] + (o[1] - f[1]) * open_) for o, f in zip(pts, flat)]


def smooth_half(shape, p, u):
    """The right half of a smooth tank's section at `u`, from the top round to the tunnel's roof,
    both middle points left out: [(x, y)]."""
    w, up, down = key_at(shape["keys"], u)
    e = 2.0 / shape["n"]
    bw = shape["bw"]
    cy = down
    depth = down + p["T"]
    tuck = 0.3 * (1.0 - smoothstep(0.0, 0.7, u))
    knee = knee_at(p, u)

    def at(a):
        ca, sa = math.cos(a), math.sin(a)
        x = abs(ca) ** e * w * (bw * (1.0 + tuck * sa) if sa < 0.0 else 1.0)
        # The knees pull in the lower flank, most just below its widest.
        x -= knee * max(0.0, 1.0 - abs(a + 0.35) / 0.9)
        y = math.copysign(abs(sa) ** e, sa) * (up if sa > 0.0 else depth)
        return x, cy + y

    tw = min(p["tw"], at(0.0)[0] * 0.55)
    target = tw + LIP
    # Where the flank meets the floor: the angle at which it's `target` out (bisection).
    lo, hi = -math.pi * 0.5, 0.0
    for _ in range(40):
        mid = (lo + hi) * 0.5
        if at(mid)[0] < target:
            lo = mid
        else:
            hi = mid
    a_end = hi
    n = shape["_arc"]
    arc = [at(math.pi * 0.5 + (a_end - math.pi * 0.5) * i / n) for i in range(1, n + 1)]
    x_end, y_end = arc[-1]
    return arc + tunnel(p, u, x_end, y_end, tw, shape["_lod"]), cy + up, roof_of(p, u, y_end)


def facet_half(shape, p, u):
    """BikeModel._facet_tank's profile, right half, over a floor and tunnel."""
    w, up, down = key_at(shape["keys"], u)
    bw = shape["bw"]
    cy = down
    depth = down + p["T"]
    k = own_knee(shape, u)
    knee = knee_at(p, u)
    pts = [(w * 0.42, cy + up * 0.96), (w * 0.84, cy + up * 0.7), (w * (1.0 - k * 0.45) - knee * 0.5, cy + up * 0.18),
        (w * bw * (1.0 - k) - knee, cy - down * 0.4), (w * bw * 0.6 - knee * 0.3, cy - depth)]
    if shape["_lod"] == 2:
        pts = [pts[1], pts[3], pts[4]]
    tw = min(p["tw"], pts[-1][0] - LIP)
    x_end, y_end = pts[-1]
    return pts + tunnel(p, u, x_end, y_end, tw, shape["_lod"]), cy + up, roof_of(p, u, y_end)


def ring(shape, p, u, shrink=1.0, inset=0.0):
    """A whole section at `u`: the top's middle, round the right side, the roof's middle and back
    up the left. Its cheeks reach forward at the nose; `shrink` draws it smaller round its middle
    (a rolled end), moved `inset` in along the tank."""
    half, top, roof = (facet_half if shape.get("facet") else smooth_half)(shape, p, u)
    mid_y = (top + roof) * 0.5
    reach = p["reach"] * (1.0 - smoothstep(0.0, NOSE, u)) ** 2

    def place(x, y):
        z = u + inset - reach * smoothstep(0.02, 0.07, abs(x))
        return g(x * shrink, mid_y + (y - mid_y) * shrink, z)
    out = [place(0.0, top)] + [place(x, y) for x, y in half] + [place(0.0, roof)]
    out += [place(-x, y) for x, y in reversed(half)]
    return out


def roof_of(p, u, y_end):
    return y_end * smoothstep(p["ut"] - 0.12, p["ut"], u)


ENDS = [[(0.0, 0.4), (0.006, 0.76), (0.014, 0.93)], [(0.0, 0.5), (0.012, 0.9)], [(0.0, 0.6)]]


def ends(shape, p, lod, us):
    """The sections down the tank, `us` along it, with each end rolled over in smaller sections
    (ENDS: how far in, how big) to a small flat cap, so the nose is a rounded dome round the
    head stock rather than a cut-off end."""
    roll = ENDS[lod]
    first = roll[-1][0] + 0.012
    inner = [u for u in us if first < u < 1.0 - first]
    out = [ring(shape, p, 0.0, k, d) for d, k in roll] + [ring(shape, p, first)]
    out += [ring(shape, p, u) for u in inner]
    out += [ring(shape, p, 1.0 - first)] + [ring(shape, p, 1.0, k, -d) for d, k in reversed(roll)]
    return out


def body(shape, p, lod):
    shape = dict(shape, _lod=lod)
    if shape.get("facet"):
        n = FACET_RINGS[lod]
        ob = kit.skin("body", ends(shape, p, lod, [i / n for i in range(n + 1)]), "paint")
        kit.sharp_along(ob)
        return ob
    d = DETAIL[lod]
    shape["_arc"] = d["arc"]
    n = d["rings"]
    return kit.skin("body", ends(shape, p, lod, [i / n for i in range(n + 1)]), "paint")


def crease(ob, shape, lod):
    """A smooth tank's shading: smooth all over but for a crisp edge down each side of the
    tunnel's mouth (the angle test join uses catches some of the floor's quads and not others)."""
    if shape.get("facet"):
        return
    arc = DETAIL[lod]["arc"]
    m = 2 * (arc + (2 if lod == 2 else 5)) + 2
    mouth = 1 + arc + (0 if lod == 2 else 1)
    sharp = {mouth, m - mouth}
    me = ob.data
    attr = me.attributes.get("sharp_edge") or me.attributes.new("sharp_edge", "BOOLEAN", "EDGE")
    for e in me.edges:
        a, b = e.vertices
        attr.data[e.index].value = a % m == b % m and a % m in sharp


def build(name):
    shape = SHAPES[name]

    def make(lod):
        def one(p):
            ob = kit.join([body(shape, p, lod)], "tank")
            crease(ob, shape, lod)
            return ob
        return kit.keyed(one, BASE, KEYS)
    return make


def parts():
    return [{"kind": "tank", "path": "tank/%s.glb" % name, "build": build(name), "mounts": {}} for name in SHAPES]
