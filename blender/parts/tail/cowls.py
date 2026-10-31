"""The seat cowls and tail sections a tail unit's look can ask for, one glb each (BikeModel's
TAIL_COWLS, read from the game's code): ducktail, hump, solo and tracker lofted smooth with gently
rounded ends, and the sports and race tails folded from flat panels, creased at every fold, to
match the full fairings. Each is drawn in metres from the end of the subframe (BikeModel's _tail),
back along -Y; the game stretches it back by the look's "length". The tracker's number board, the
solo's back stop and any stripe are still the game's. All `paint`."""

import math

import kit

COWLS = kit.gd_const("TAIL_COWLS")
FACETED = ["sport", "racing"]
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
    keys = COWLS[name]
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
