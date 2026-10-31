"""The air and oil filters BikeModel._draw_air_filter and _draw_oil_filter put on the engine, each
round its middle and standing up the game's Y (the game turns it to point where the filter
points; a point (x, y, z) in the game's axes is Blender's (x, -z, y)):

- "filter/pod.glb": a pod filter, 40 mm in radius and 90 mm tall, its pleated element between a
  rubber base and a cap.
- "filter/stack.glb": a velocity stack, 26 mm round its base flaring to 42 mm over its 50 mm.
- "filter/cone.glb": a cone filter, 65 mm round its base tapering to 40 mm over its 140 mm, pleated.
- "filter/airbox.glb": the airbox under the tank, 200 by 150 by 140 mm round its middle, ribbed,
  with its clips (the game stretches it across to the engine's width).
- "filter/housing.glb": the element's housing out of the airbox's end, 60 mm in radius and a unit
  long (the game sets its length), with its lid "filter/lid.glb", 66 mm across and 12 mm thick.
- "filter/cleaner.glb": a V-twin's round air cleaner, 70 mm in radius and 45 mm deep, with its
  chrome rim 28 mm out on its face.
- "filter/oil.glb": the spin-on oil filter, 35 mm in radius and 70 mm long, fluted, its spanner
  flats on the end at +Y.

Tags: paint (the filter's colour), paint_2 (the darker cap, lid or end), rubber, chrome, black_metal."""

import math

import kit


def g(x, y, z):
    return (x, -z, y)


def upright(name, secs, segs, tag, at=(0.0, 0.0, 0.0)):
    """A loft up the game's Y through (y, radius x, radius z, n) sections, round game point `at`."""
    ob = kit.loft(name, [(y, rx, rz, rz, n) for y, rx, rz, n in secs], segs, tag)
    # (A loft runs along Blender Y; turned up, its Y becomes Blender Z, the game's Y.)
    ob.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    ob.location = g(*at)
    return ob


def pleated(name, profile, pleats, depth, segs, tag):
    """An upright pleated element through `profile` ((y, radius) up the game's Y), its radius
    pressed in `depth` of the way between each of its `pleats` (none when pleats is 0)."""
    rings = []
    for y, r in profile:
        ring = []
        for k in range(segs):
            t = 2.0 * math.pi * k / segs
            rr = r * (1.0 - depth * (0.5 + 0.5 * math.cos(pleats * t))) if pleats else r
            ring.append(g(rr * math.cos(t), y, rr * math.sin(t)))
        rings.append(ring)
    return kit.skin(name, rings, tag)


def pod(lod):
    segs = [48, 16, 6][lod]
    pl = 24 if lod == 0 else 0
    profile = [(-0.034, 0.037), (-0.012, 0.039), (0.012, 0.039), (0.034, 0.037)] if lod < 2 else [(-0.04, 0.038), (0.04, 0.038)]
    parts = [pleated("element", profile, pl, 0.07, segs, "paint")]
    if lod < 2:
        s = [24, 14][lod]
        parts.append(upright("base", [(-0.045, 0.036, 0.036, 2.0), (-0.042, 0.04, 0.04, 2.0), (-0.034, 0.04, 0.04, 2.0)], s, "rubber"))
        parts.append(upright("cap", [(0.034, 0.04, 0.04, 2.0), (0.041, 0.04, 0.04, 2.0), (0.045, 0.03, 0.03, 2.0)], s, "paint_2"))
    if lod == 0:
        parts.append(upright("clamp", [(-0.04, 0.041, 0.041, 2.0), (-0.036, 0.041, 0.041, 2.0)], 24, "chrome"))
    return kit.join(parts, "pod")


def stack(lod):
    segs = [24, 14, 6][lod]
    n = [6, 3, 1][lod]
    secs = []
    for i in range(n + 1):
        f = i / n
        r = 0.026 + 0.012 * f ** 2.4
        secs.append((-0.025 + 0.044 * f, r, r, 2.0))
    parts = [upright("bell", secs, segs, "chrome")]
    # The rolled lip round its mouth.
    if lod < 2:
        lip = kit.ring("lip", 0.0, 0.039, 0.004, segs, "chrome", 6 if lod == 0 else 4)
        lip.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
        lip.location = g(0.0, 0.021, 0.0)
        parts.append(lip)
    else:
        parts.append(upright("lip", [(0.019, 0.042, 0.042, 2.0), (0.025, 0.042, 0.042, 2.0)], segs, "chrome"))
    return kit.join(parts, "stack")


def cone(lod):
    segs = [56, 16, 6][lod]
    pl = 28 if lod == 0 else 0
    n = [6, 3, 1][lod]
    profile = []
    for i in range(n + 1):
        f = i / n
        profile.append((-0.06 + 0.12 * f, 0.063 - 0.025 * f))
    parts = [pleated("element", profile, pl, 0.06, segs, "paint")]
    if lod < 2:
        s = [28, 14][lod]
        parts.append(upright("neck", [(-0.07, 0.06, 0.06, 2.0), (-0.066, 0.065, 0.065, 2.0), (-0.058, 0.065, 0.065, 2.0)], s, "rubber"))
        parts.append(upright("end", [(0.058, 0.04, 0.04, 2.0), (0.066, 0.04, 0.04, 2.0), (0.07, 0.03, 0.03, 2.0)], s, "paint_2"))
    if lod == 0:
        parts.append(upright("clamp", [(-0.068, 0.067, 0.067, 2.0), (-0.062, 0.067, 0.067, 2.0)], 28, "chrome"))
    return kit.join(parts, "cone")


def airbox(lod):
    segs = [24, 12, 6][lod]
    parts = [kit.loft("box", [(-0.07, 0.094, 0.07, 0.07, 6.0), (-0.064, 0.1, 0.075, 0.075, 6.0), (0.064, 0.1, 0.075, 0.075, 6.0), (0.07, 0.094, 0.07, 0.07, 6.0)]
        if lod < 2 else [(-0.07, 0.1, 0.075, 0.075, 6.0), (0.07, 0.1, 0.075, 0.075, 6.0)], segs, "paint")]
    if lod < 2:
        # The lid's seam round its top, ribs across its back and side and the spring clips.
        parts.append(kit.loft("seam", [(-0.066, 0.102, 0.004, 0.004, 6.0), (0.066, 0.102, 0.004, 0.004, 6.0)], 8, "paint_2", at=(0.0, 0.0, 0.035)))
        for x in (-0.05, 0.0, 0.05):
            parts.append(kit.loft("rib", [(0.068, 0.004, 0.06, 0.06, 4.0), (0.074, 0.004, 0.06, 0.06, 4.0)], 4, "paint", at=(x, 0.0, 0.0)))
    if lod == 0:
        for side in (-1.0, 1.0):
            for z in (-0.04, 0.04):
                parts.append(kit.loft("clip", [(-z - 0.008, 0.006, 0.02, 0.02, 4.0), (-z + 0.008, 0.006, 0.02, 0.02, 4.0)], 4, "black_metal", at=(side * 0.102, 0.0, 0.03)))
    return kit.join(parts, "airbox")


def housing(lod):
    segs = [24, 12, 6][lod]
    parts = [upright("housing", [(-0.5, 0.06, 0.06, 2.0), (0.5, 0.06, 0.06, 2.0)], segs, "paint")]
    return kit.join(parts, "housing")


def lid(lod):
    segs = [28, 14, 6][lod]
    parts = [upright("lid", [(-0.006, 0.066, 0.066, 2.0), (0.002, 0.066, 0.066, 2.0), (0.006, 0.06, 0.06, 2.0)] if lod < 2
        else [(-0.006, 0.066, 0.066, 2.0), (0.006, 0.066, 0.066, 2.0)], segs, "paint_2")]
    if lod < 2:
        # Radial ribs on its face and the wing nut in the middle.
        for k in range(8 if lod == 0 else 4):
            a = math.pi * 2.0 * k / (8 if lod == 0 else 4)
            rib = kit.tube("rib", g(math.cos(a) * 0.018, 0.0065, math.sin(a) * 0.018), g(math.cos(a) * 0.055, 0.0065, math.sin(a) * 0.055), 0.0025, 4, "paint_2")
            parts.append(rib)
        parts.append(upright("nut", [(0.005, 0.012, 0.012, 2.0), (0.014, 0.01, 0.01, 2.0)], 6, "black_metal"))
    if lod == 0:
        parts.append(kit.tube("wing", g(-0.02, 0.012, 0.0), g(0.02, 0.012, 0.0), 0.003, 4, "black_metal"))
    return kit.join(parts, "lid")


def cleaner(lod):
    segs = [32, 16, 6][lod]
    parts = [upright("cover", [(-0.0225, 0.068, 0.068, 2.0), (-0.012, 0.07, 0.07, 2.0), (0.012, 0.07, 0.07, 2.0), (0.0225, 0.064, 0.064, 2.0)]
        if lod < 2 else [(-0.0225, 0.07, 0.07, 2.0), (0.0225, 0.07, 0.07, 2.0)], segs, "paint")]
    parts.append(upright("rim", [(0.022, 0.095, 0.095, 2.0), (0.034, 0.095, 0.095, 2.0)] if lod == 2
        else [(0.022, 0.088, 0.088, 2.0), (0.025, 0.095, 0.095, 2.0), (0.031, 0.095, 0.095, 2.0), (0.034, 0.086, 0.086, 2.0)], segs, "chrome"))
    if lod < 2:
        # The domed badge in the middle of the face, and its bolt.
        parts.append(upright("badge", [(0.034, 0.045, 0.045, 2.0), (0.04, 0.038, 0.038, 2.0), (0.043, 0.02, 0.02, 2.0)], segs, "chrome"))
    if lod == 0:
        parts.append(upright("bolt", [(0.043, 0.007, 0.007, 2.0), (0.048, 0.006, 0.006, 2.0)], 6, "black_metal"))
    return kit.join(parts, "cleaner")


def oil(lod):
    segs = [36, 14, 6][lod]
    fl = 18 if lod == 0 else 0
    profile = [(-0.035, 0.032), (-0.031, 0.035), (0.028, 0.035), (0.033, 0.033)] if lod < 2 else [(-0.035, 0.035), (0.033, 0.034)]
    parts = [pleated("can", profile, fl, 0.03, segs, "paint")]
    # The flat end with its spanner flats.
    parts.append(upright("flats", [(0.033, 0.016, 0.016, 2.0), (0.043, 0.016, 0.016, 2.0)], 6, "paint_2"))
    if lod < 2:
        parts.append(upright("seal", [(-0.037, 0.03, 0.03, 2.0), (-0.034, 0.03, 0.03, 2.0)], [20, 10][lod], "rubber"))
    return kit.join(parts, "oil")


def parts():
    return [{"kind": "filter", "path": "filter/%s.glb" % name, "build": build, "mounts": {}}
        for name, build in (("pod", pod), ("stack", stack), ("cone", cone), ("airbox", airbox), ("housing", housing),
            ("lid", lid), ("cleaner", cleaner), ("oil", oil))]
