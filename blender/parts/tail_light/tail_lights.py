"""The rear lights: each lamp BikeModel._draw_tail puts at the tail unit's light point, round
that point, its red glass looking back (game +Z; a point (x, y, z) here in the game's axes is
Blender's (x, -z, y)).

- "tail_light/round.glb": a round can with a domed glass and a chrome bezel (the default).
- "tail_light/tombstone.glb": the chrome tombstone, an arch-topped body with its glass.
- "tail_light/cateye.glb": the long chrome cat's eye with a slit glass.
- "tail_light/twin.glb": a pair of small round lamps side by side.
- "tail_light/halo.glb": a ring of light round a black hub.
- "tail_light/lucas.glb": the old Lucas lamp, a chrome box with a hood over its glass.
- "tail_light/strip.glb": a slim LED strip on a black backing.
- "tail_light/bullet.glb": a black bullet with a round glass on its end.
- "tail_light/led.glb": a compact LED block.

The glass is tagged lens_red (the game lays its tail and stop lamp material over it); black
housings are plastic, bright ones chrome."""

import math

import kit


def gbox(name, c, half, tag, segs, n=4.0, taper=1.0):
    """A rounded box round game point `c`, half sizes `half`, its front (game -Z) end shrunk by `taper`."""
    x, y, z = c
    hx, hy, hz = half
    return kit.loft(name, [(-z - hz, hx, hy, hy, n), (-z + hz, hx * taper, hy * taper, hy * taper, n)], segs, tag, at=(x, 0.0, y))


def gdisc(name, c, r, length, tag, segs, back=1.0):
    """A disc or can round game point `c`, along game Z, `length` long, its front end `back` of `r`."""
    x, y, z = c
    return kit.loft(name, [(-z - length * 0.5, r, r, r, 2.0), (-z + length * 0.5, r * back, r * back, r * back, 2.0)], segs, tag, at=(x, 0.0, y))


def dome(name, c, r, depth, tag, segs, lod):
    """A glass bulging back from game point `c` by `depth`."""
    x, y, z = c
    secs = [(-z + 0.001, r, r, r, 2.0), (-z - depth * 0.5, r * 0.92, r * 0.92, r * 0.92, 2.0)]
    if lod < 2:
        secs.append((-z - depth, r * 0.5, r * 0.5, r * 0.5, 2.0))
    return kit.loft(name, secs, segs, tag, at=(x, 0.0, y))


def round_lamp(lod):
    segs = [20, 12, 8][lod]
    parts = [gdisc("can", (0.0, 0.0, 0.0), 0.036, 0.04, "plastic", segs, 0.85), dome("glass", (0.0, 0.0, 0.02), 0.032, 0.008, "lens_red", segs, lod)]
    if lod < 2:
        parts.append(kit.ring("bezel", -0.02, 0.033, 0.0025, segs, "chrome", 6 if lod == 0 else 4))
    return kit.join(parts, "round")


def arch(r, y0, y1, segs):
    """An arch-topped outline in the game's XY: straight sides from y0 up to y1, a half circle of
    radius r over the top."""
    pts = [(r, y0)]
    for i in range(segs + 1):
        a = math.pi * i / segs
        pts.append((r * math.cos(a), y1 + r * math.sin(a)))
    pts.append((-r, y0))
    return pts


def extrude(name, outline, z0, z1, tag):
    """An outline in the game's XY pushed from game z0 to z1."""
    return kit.skin(name, [[(x, -z, y) for x, y in outline] for z in (z0, z1)], tag)


def tombstone(lod):
    segs = [12, 8, 4][lod]
    parts = [extrude("body", arch(0.05, -0.03, 0.03, segs), -0.025, 0.025, "chrome"),
        extrude("glass", arch(0.0425, -0.025, 0.0105, segs), 0.024, 0.03, "lens_red")]
    if lod == 0:
        # The number plate lamp's little window under the glass.
        parts.append(gbox("window", (0.0, -0.034, 0.01), (0.025, 0.004, 0.012), "glass", 8, 4.0))
    return kit.join(parts, "tombstone")


def capsule(name, half, r, tag, segs, squash=1.0, z=0.0):
    n = [9, 5, 2][0 if segs > 10 else (1 if segs > 6 else 2)]
    pts, radii = [], []
    for i in range(n):
        a = math.pi * 0.5 * i / (n - 1)
        pts.append((-half - r * math.cos(a) * 0.95, -z, 0.0))
        radii.append(max(r * math.sin(a), r * 0.15))
    for i in reversed(range(n)):
        a = math.pi * 0.5 * i / (n - 1)
        pts.append((half + r * math.cos(a) * 0.95, -z, 0.0))
        radii.append(max(r * math.sin(a), r * 0.15))
    return kit.sweep(name, pts, radii, segs, tag, squash)


def cateye(lod):
    segs = [16, 10, 4][lod]
    parts = [capsule("body", 0.043, 0.022, "chrome", segs), capsule("glass", 0.037, 0.018, "lens_red", segs, 0.5, 0.012)]
    return kit.join(parts, "cateye")


def twin(lod):
    segs = [16, 10, 6][lod]
    parts = []
    for x in (-0.045, 0.045):
        parts += [gdisc("can", (x, 0.0, 0.0), 0.026, 0.035, "plastic", segs, 0.85), dome("glass", (x, 0.0, 0.0175), 0.023, 0.006, "lens_red", segs, lod)]
    if lod < 2:
        parts.append(gbox("bridge", (0.0, 0.0, -0.005), (0.03, 0.008, 0.012), "plastic", 8, 4.0))
    return kit.join(parts, "twin")


def halo(lod):
    segs = [24, 14, 6][lod]
    parts = [kit.ring("halo", 0.0, 0.034, 0.006, segs, "lens_red", 6 if lod < 2 else 4), gdisc("hub", (0.0, 0.0, -0.01), 0.03, 0.02, "plastic", segs)]
    if lod == 0:
        parts.append(dome("eye", (0.0, 0.0, 0.0), 0.012, 0.004, "lens_red", 12, lod))
    return kit.join(parts, "halo")


def lucas(lod):
    segs = [12, 8, 4][lod]
    parts = [gbox("body", (0.0, 0.0, 0.0), (0.06, 0.035, 0.035), "chrome", segs, 5.0, 0.9),
        gbox("glass", (0.0, 0.0, 0.036), (0.05, 0.025, 0.004), "lens_red", segs, 5.0)]
    if lod < 2:
        # The hood over the glass.
        parts.append(gbox("hood", (0.0, 0.031, 0.045), (0.056, 0.004, 0.012), "chrome", segs, 5.0))
    return kit.join(parts, "lucas")


def strip(lod):
    segs = [12, 8, 4][lod]
    parts = [gbox("glass", (0.0, 0.0, 0.0), (0.07, 0.011, 0.005), "lens_red", segs, 6.0),
        gbox("backing", (0.0, 0.0, -0.007), (0.072, 0.013, 0.004), "plastic", segs, 6.0)]
    return kit.join(parts, "strip")


def bullet(lod):
    segs = [16, 10, 6][lod]
    parts = [kit.sphere("shell", (0.0, 0.0, 0.0), 0.03, (1.0, 1.5, 1.0), segs, "plastic"), dome("glass", (0.0, 0.0, 0.04), 0.025, 0.006, "lens_red", segs, lod)]
    if lod < 2:
        parts.append(kit.ring("bezel", -0.04, 0.0255, 0.002, segs, "chrome", 6 if lod == 0 else 4))
    return kit.join(parts, "bullet")


def led(lod):
    segs = [12, 8, 4][lod]
    parts = [gbox("body", (0.0, 0.0, -0.01), (0.035, 0.0175, 0.015), "plastic", segs, 5.0, 0.9),
        gbox("glass", (0.0, 0.0, 0.006), (0.03, 0.0125, 0.003), "lens_red", segs, 5.0)]
    if lod == 0:
        for k in range(5):
            parts.append(gbox("led", (-0.02 + k * 0.01, 0.0, 0.0095), (0.003, 0.003, 0.0006), "lens_red", 8, 2.0))
    return kit.join(parts, "led")


def parts():
    return [{"kind": "tail_light", "path": "tail_light/%s.glb" % name, "build": build, "mounts": {}}
        for name, build in (("round", round_lamp), ("tombstone", tombstone), ("cateye", cateye), ("twin", twin), ("halo", halo),
            ("lucas", lucas), ("strip", strip), ("bullet", bullet), ("led", led))]
