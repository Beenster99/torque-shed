"""The indicators: the head of each style BikeModel._indicator_set puts on its stalk, round the
head's middle, its amber glass looking forward (game -Z; a point (x, y, z) here in the game's axes
is Blender's (x, -z, y)). The game turns a rear one round to look back, and draws the stalk.

- "indicator/stalk.glb": the common square-ish block on a stalk, 45 by 32 mm.
- "indicator/bullet.glb": a chrome bullet with a domed glass.
- "indicator/mini.glb": a 12 mm cube on a thin stalk.
- "indicator/touring.glb": a big touring lamp in the bike's colour, with a chrome trim.
- "indicator/flush.glb": a flush strip set into the bodywork.

The glass is tagged lens_amber (the game lays its own flashing material over it), a black housing
plastic, a coloured one paint, a chrome one chrome."""

import kit


def gbox(name, c, half, tag, segs, n=4.0, taper=1.0):
    """A rounded box round game point `c`, half sizes `half`, its back end shrunk by `taper`."""
    x, y, z = c
    hx, hy, hz = half
    return kit.loft(name, [(-z - hz, hx, hy, hy, n), (-z + hz, hx * taper, hy * taper, hy * taper, n)], segs, tag, at=(x, 0.0, y))


def stalk(lod):
    segs = [16, 10, 6][lod]
    parts = [gbox("head", (0.0, 0.0, 0.0), (0.0225, 0.016, 0.015), "plastic", segs, taper=0.8)]
    parts.append(gbox("glass", (0.0, 0.0, -0.016), (0.021, 0.015, 0.003), "lens_amber", segs))
    if lod == 0:
        # The glass's ribs and the screw holding it in.
        for k in range(3):
            parts.append(gbox("rib", (0.0, -0.008 + k * 0.008, -0.0195), (0.018, 0.0008, 0.0006), "lens_amber", 4, 2.0))
        parts.append(kit.tube("screw", (0.0, -0.0186, -0.006), (0.0, -0.0186, -0.002), 0.002, 6, "chrome"))
    return kit.join(parts, "stalk")


def bullet(lod):
    segs = [16, 10, 4][lod]
    parts = [kit.sphere("shell", (0.0, 0.0, 0.0), 0.018, (1.0, 1.7, 1.0), segs, "chrome")]
    if lod < 2:
        parts.append(kit.sphere("glass", (0.0, 0.022, 0.0), 0.015, (1.0, 0.6, 1.0), segs, "lens_amber"))
    else:
        parts.append(kit.loft("glass", [(0.018, 0.015, 0.015, 0.015, 2.0), (0.03, 0.008, 0.008, 0.008, 2.0)], segs, "lens_amber"))
    if lod < 2:
        parts.append(kit.ring("bezel", 0.021, 0.0155, 0.0018, segs, "chrome", 6 if lod == 0 else 4))
    return kit.join(parts, "bullet")


def mini(lod):
    segs = [12, 8, 4][lod]
    parts = [gbox("head", (0.0, 0.0, 0.0), (0.006, 0.006, 0.014), "plastic", segs, taper=0.85),
        gbox("glass", (0.0, 0.0, -0.015), (0.0055, 0.0055, 0.002), "lens_amber", segs)]
    return kit.join(parts, "mini")


def touring(lod):
    segs = [20, 12, 6][lod]
    parts = [gbox("housing", (0.0, 0.0, 0.0), (0.035, 0.025, 0.02), "paint", segs, 5.0, 0.85),
        gbox("glass", (0.0, 0.0, -0.021), (0.032, 0.022, 0.002), "lens_amber", segs, 5.0)]
    if lod == 0:
        parts.append(gbox("trim", (0.0, 0.0, -0.019), (0.0355, 0.0255, 0.0012), "chrome", segs, 5.0))
        parts.append(gbox("reflector", (0.0, 0.0, -0.0235), (0.012, 0.012, 0.0006), "lens_amber", 12, 2.0))
    return kit.join(parts, "touring")


def flush(lod):
    segs = [12, 8, 4][lod]
    parts = [gbox("bezel", (0.0, 0.0, 0.002), (0.019, 0.0075, 0.004), "plastic", segs, 6.0),
        gbox("glass", (0.0, 0.0, -0.001), (0.0175, 0.006, 0.004), "lens_amber", segs, 6.0)]
    return kit.join(parts, "flush")


def parts():
    return [{"kind": "indicator", "path": "indicator/%s.glb" % name, "build": build, "mounts": {}}
        for name, build in (("stalk", stalk), ("bullet", bullet), ("mini", mini), ("touring", touring), ("flush", flush))]
