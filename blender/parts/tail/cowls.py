"""The seat cowls and tail sections a tail unit's look can ask for, one glb each (BikeModel's
TAIL_COWLS, read from the game's code): ducktail, hump, solo and tracker lofted smooth with gently
rounded ends, and the sports and race tails folded from flat panels, creased at every fold, to
match the full fairings. Rig built (bodywork track H3): each sits on the seat rails and carries
the seat's line on to the tail. Its origin is on the top of the rails (BikeModel.rig
"seat_rails") under the cowl's front, its underside wrapping 20 mm below them, and it runs back
along -Y in metres; the game stretches it back to the rig's "tail" (lines agreement line 4).
The tracker's number board, the solo's back stop and any stripe are still the game's.

Shape keys the game sets per bike:
- `front_width`, `front_height`: the front 50 mm wider each side and 40 mm taller, fading out by
  a third of the way back, so it meets the seat's rear section; negative weights shrink it;
- `kick`: the tail's end 80 mm higher, rising more towards the tip (lines agreement
  "tail_rise_mm").

All `paint`."""

import math

import kit

COWLS = kit.gd_const("TAIL_COWLS")
FACETED = ["sport", "racing"]
WRAP = 0.02               # m the cowl's underside wraps below the rails
BASE = {"fw": 0.0, "fh": 0.0, "kick": 0.0}
KEYS = {"front_width": {"fw": 0.05}, "front_height": {"fh": 0.04}, "kick": {"kick": 0.08}}


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def on_rails(keys, p):
    """The code's keys moved to sit on the rails from the cowl's front, with the shape keys'
    changes: [z, half width, up, down, centre height, squareness]."""
    z0 = keys[0][0]
    total = max(keys[-1][0] - z0, 0.01)
    out = []
    for z, w, up, down, lift, n in keys:
        f = (z - z0) / total
        front = 1.0 - smoothstep(0.0, 0.35, f)
        out.append([z - z0, w + p["fw"] * front, up + p["fh"] * front, down, lift + down - WRAP + p["kick"] * f * f, n])
    return out
PER_SPAN = [8, 3, 1]
SEGS = [36, 14, 8]


def g(x, y, z):
    """A point in the glb's Godot space (x right, y up, z back) as Blender's."""
    return (x, -z, y)


def along(keys, steps, smooth=True):
    """Points down the cowl between its keys: [z, half width, up, down, lift, squareness]."""
    out = []
    for i in range(len(keys) - 1):
        a, b = keys[i], keys[i + 1]
        for s in range(steps if i < len(keys) - 2 else steps + 1):
            f = s / steps
            if smooth:
                f = f * f * (3.0 - 2.0 * f)
            out.append([a[k] + (b[k] - a[k]) * f for k in range(6)])
    return out


def ring(k, segs, shrink=1.0):
    z, w, up, down, lift, n = k
    e = 2.0 / n
    pts = []
    for j in range(segs):
        a = -math.pi * 0.5 + 2.0 * math.pi * j / segs
        ca, sa = math.cos(a), math.sin(a)
        x = math.copysign(abs(ca) ** e, ca) * w * shrink
        y = math.copysign(abs(sa) ** e, sa) * (up if sa > 0.0 else down) * shrink
        pts.append(g(x, lift + y, z))
    return pts


def facet_ring(k):
    """BikeModel._facet_cowl's profile: a tucked-in underside, a crease along each flank, a ridged top."""
    z, w, up, down, lift, n = k
    half = [(0.0, -down), (w * 0.62, -down), (w, -down + (up + down) * 0.4), (w * 0.72, up * 0.82), (w * 0.3, up), (0.0, up + 0.008)]
    prof = [(-x, y) for x, y in half[:-1]] + [half[-1]] + [half[i] for i in range(len(half) - 2, 0, -1)]
    return [g(x, lift + y, z) for x, y in prof]


def cowl(name, lod):
    return kit.keyed(lambda p: cowl_with(name, lod, p), BASE, KEYS)


def cowl_with(name, lod, p):
    keys = on_rails(COWLS[name], p)
    if name in FACETED:
        # (The code takes three rows a span; more here, so the creases run smoothly to the point.)
        rows = [facet_ring(k) for k in along(keys, [6, 3, 1][lod], False)]
        ob = kit.join([kit.skin("cowl", rows, "paint")], "cowl")
        kit.sharp_along(ob)
        return ob
    ks = along(keys, PER_SPAN[lod])
    rings = [ring(k, SEGS[lod]) for k in ks]
    if lod < 2:
        # Rounded ends: each end drawn a little smaller, with a full size ring just in from it.
        first, last = list(ks[0]), list(ks[-1])
        first[0] += 0.006
        last[0] -= 0.006
        rings = [ring(ks[0], SEGS[lod], 0.85), ring(first, SEGS[lod])] + rings[1:-1] + [ring(last, SEGS[lod]), ring(ks[-1], SEGS[lod], 0.85)]
    return kit.join([kit.skin("cowl", rings, "paint")], "cowl")


def parts():
    return [{"kind": "tail", "path": "tail/cowl/%s.glb" % name, "build": (lambda lod, n=name: cowl(n, lod)), "mounts": {}} for name in COWLS]
