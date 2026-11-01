"""The seats, rig built (bodywork track H3): one glb for each shape BikeModel draws (SEAT_SHAPES,
read from the game's code): bench, cafe, enduro, sport, touring, brat, stepped, king_queen, solo,
gunfighter, hump_long and flat_track. Each is a padded cover over a black base pan, drawn at a
reference length of 1 m. It sits on its rails: its origin is on the top of the seat rails
(BikeModel.rig "seat_rails", lines agreement 3) under the seat's nose, the pan's flat underside
along them, running back along -Y. A hump or a pillion step rises from the pan, as a real seat
unit's does. The game stretches it along the rails from the nose to the tail (or the share of
them a solo seat covers) and tilts it with them. Its stitching, piping, grab rail and sissy bar
are still the game's.

Shape keys the game sets per bike:
- `foam`: 40 mm more foam over the whole top (the saddle part's own foam depth);
- `nose_width`, `nose_height`: the nose 60 mm wider each side and 40 mm taller, fading out by a
  fifth of the way back, so it meets the tank's rear section (lines agreement line 3). Negative
  weights narrow and lower it.

Tags: the cover `leather` (the game gives it the seat's colour and grain), the pan `plastic`."""

import math

import kit

SHAPES = kit.gd_const("SEAT_SHAPES")
BW = 0.85                 # BikeModel._draw_saddle's sections are all this much narrower below
PAN = 0.35                # rad below the sides where the cover tucks under onto the pan

BASE = {"foam": 0.0, "nose_w": 0.0, "nose_h": 0.0}
KEYS = {"foam": {"foam": 0.04}, "nose_width": {"nose_w": 0.06}, "nose_height": {"nose_h": 0.04}}
NOSE = 0.2                # share of the length the nose keys fade over

DETAIL = [{"rings": 32, "segs": 40}, {"rings": 12, "segs": 16}, {"rings": 6, "segs": 8}]


def g(x, y, z):
    """A point in the glb's Godot space (x right, y up, z back) as Blender's."""
    return (x, -z, y)


def key_at(keys, u):
    """BikeModel._seat_key_at: [half width, rise, drop, lift] at `u` along the seat."""
    for k0, k1 in zip(keys, keys[1:]):
        if u <= k1[0]:
            f = (u - k0[0]) / max(k1[0] - k0[0], 0.0001)
            f = f * f * (3.0 - 2.0 * f)
            return [k0[i] + (k1[i] - k0[i]) * f for i in (1, 2, 3, 4)]
    return keys[-1][1:5]


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def point(shape, p, u, a, shrink=1.0):
    """A point on the seat at `u` along it and `a` round it: its section's middle is as high over
    the rails as its drop and lift, so the pan sits flat on them."""
    w, up, down, lift = key_at(shape["keys"], u)
    nose = 1.0 - smoothstep(0.0, NOSE, u)
    w += p["nose_w"] * nose
    up += p["foam"] + p["nose_h"] * nose
    low = down + lift
    e = 2.0 / shape["n"]
    ca, sa = math.cos(a), math.sin(a)
    x = math.copysign(abs(ca) ** e, ca) * w * (BW if sa < 0.0 else 1.0) * shrink
    y = math.copysign(abs(sa) ** e, sa) * (up if sa > 0.0 else low) * shrink
    return g(x, low + y, u)


def seat(name, lod):
    return kit.keyed(lambda p: seat_with(name, lod, p), BASE, KEYS)


def seat_with(name, lod, p):
    shape = SHAPES[name]
    d = DETAIL[lod]
    # Along the seat, with the ends drawn a little smaller for a rolled edge.
    us = [i / d["rings"] for i in range(d["rings"] + 1)]
    if lod < 2:
        us = [0.0, 0.01] + us[1:-1] + [0.99, 1.0]
    shrink = [0.8 if i in (0, len(us) - 1) and lod < 2 else 1.0 for i in range(len(us))]
    n_cover = d["segs"] * 2 // 3
    n_pan = d["segs"] - n_cover
    cover_a = [-PAN + (math.pi + 2.0 * PAN) * j / n_cover for j in range(n_cover + 1)]
    pan_a = [math.pi + PAN + (math.pi - 2.0 * PAN) * j / n_pan for j in range(n_pan + 1)]
    cover = [[point(shape, p, u, a, s) for a in cover_a] for u, s in zip(us, shrink)]
    pan = [[point(shape, p, u, a, s) for a in pan_a] for u, s in zip(us, shrink)]
    parts = [kit.skin("cover", cover, "leather", caps=False, closed=False), kit.skin("pan", pan, "plastic", caps=False, closed=False)]
    for i, flip in ((0, True), (-1, False)):
        ring = cover[i][:-1] + pan[i][:-1]
        parts.append(kit.cap("end", ring, "leather", flip))
    ob = kit.join(parts, "seat")
    kit.weld(ob)
    return ob


def parts():
    return [{"kind": "saddle", "path": "saddle/%s.glb" % name, "build": (lambda lod, n=name: seat(n, lod)), "mounts": {}} for name in SHAPES]
