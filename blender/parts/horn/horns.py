"""The horns BikeModel._draw_horn hangs under the headstock, each looking forward (game -Z; a
point (x, y, z) in the game's axes is Blender's (x, -z, y)):

- "horn/disc.glb": the plain disc horn, 40 mm in radius and 30 mm deep round its middle, a black
  grille on its face and a bracket on its back.
- "horn/snail.glb": one snail horn (the game hangs a pair): a coiled shell 35 mm tall, its bell
  opening forward to 25 mm.
- "horn/trumpet.glb": an air horn's trumpet, a unit long from z 0.3 forward to its 30 mm flare
  at z -0.7, its radii in metres (the game stretches it along to each trumpet's length and narrows the melody's).
- "horn/klaxon.glb": the old klaxon, a domed motor housing behind a long flared bell.
- "horn/bulb.glb": the bulb horn's rubber bulb behind a brass trumpet.
- "horn/compressor.glb": the air horns' compressor, 70 by 50 by 60 mm.

Bodies are tagged paint (the horn's colour), grilles and the compressor black_metal, the bulb
rubber; the bulb horn's trumpet is polished_alloy (brass in the game's colour)."""

import math

import kit


def g(x, y, z):
    return (x, -z, y)


def flare(name, z0, z1, r0, r1, segs, tag, lod, at=(0.0, 0.0, 0.0)):
    """A bell from game z0 (radius r0) flaring out to z1 (radius r1), its mouth open a little."""
    n = [8, 4, 2][lod]
    secs = []
    for i in range(n + 1):
        f = i / n
        r = r0 + (r1 - r0) * f ** 2.2
        secs.append((-(z0 + (z1 - z0) * f), r, r, r, 2.0))
    return kit.loft(name, secs, segs, tag, at=at)


def disc(lod):
    segs = [24, 14, 8][lod]
    parts = [kit.loft("body", [(-0.015, 0.032, 0.032, 0.032, 2.0), (-0.01, 0.04, 0.04, 0.04, 2.0), (0.012, 0.04, 0.04, 0.04, 2.0), (0.015, 0.036, 0.036, 0.036, 2.0)]
        if lod < 2 else [(-0.015, 0.04, 0.04, 0.04, 2.0), (0.015, 0.04, 0.04, 0.04, 2.0)], segs, "paint")]
    if lod < 2:
        parts.append(kit.loft("grille", [(0.014, 0.03, 0.03, 0.03, 2.0), (0.02, 0.028, 0.028, 0.028, 2.0)], segs, "black_metal"))
        parts.append(kit.loft("bracket", [(-0.03, 0.006, 0.02, 0.02, 4.0), (-0.015, 0.006, 0.02, 0.02, 4.0)], 6, "black_metal", at=(0.0, 0.0, 0.025)))
    if lod == 0:
        for k in range(3):
            parts.append(kit.loft("slot", [(0.019, 0.024 - k * 0.006, 0.0012, 0.0012, 2.0), (0.021, 0.024 - k * 0.006, 0.0012, 0.0012, 2.0)], 4, "paint", at=(0.0, 0.0, -0.008 + k * 0.008)))
    return kit.join(parts, "disc")


def snail(lod):
    segs = [12, 8, 4][lod]
    parts = [kit.sphere("shell", (0.0, 0.0, 0.0), 0.035, (0.6, 1.0, 1.0), [16, 10, 4][lod], "paint")]
    if lod < 2:
        # The coil round its face.
        pts = []
        for i in range(17 if lod == 0 else 9):
            a = i / (16 if lod == 0 else 8) * 1.6 * math.pi
            rr = 0.026 - a * 0.002
            pts.append((0.022, rr * math.cos(a), rr * math.sin(a)))
        parts.append(kit.sweep("coil", pts, 0.006, 6, "paint"))
    parts.append(flare("bell", -0.02, -0.06, 0.012, 0.025, segs, "paint", lod))
    return kit.join(parts, "snail")


def trumpet(lod):
    segs = [12, 8, 4][lod]
    parts = [flare("trumpet", 0.3, -0.7, 0.009, 0.03, segs, "paint", lod)]
    if lod < 2:
        parts.append(kit.ring("lip", 0.7, 0.03, 0.0025, segs, "paint", 4))
    return kit.join(parts, "trumpet")


def klaxon(lod):
    segs = [16, 10, 4][lod]
    parts = [flare("bell", 0.01, -0.1, 0.018, 0.05, segs, "paint", lod), kit.sphere("motor", (0.0, -0.05, 0.0), 0.04, (1.0, 0.9, 1.0), [16, 10, 4][lod], "paint")]
    if lod == 0:
        parts.append(kit.ring("band", -0.02, 0.04, 0.003, segs, "paint", 4))
    return kit.join(parts, "klaxon")


def bulb(lod):
    segs = [12, 8, 4][lod]
    parts = [flare("trumpet", 0.02, -0.08, 0.008, 0.03, segs, "polished_alloy", lod), kit.sphere("bulb", (0.0, -0.05, 0.0), 0.035, (1.0, 1.15, 1.0), [16, 10, 4][lod], "rubber")]
    return kit.join(parts, "bulb")


def compressor(lod):
    segs = [12, 8, 4][lod]
    parts = [kit.loft("box", [(-0.03, 0.035, 0.025, 0.025, 4.0), (0.03, 0.035, 0.025, 0.025, 4.0)], segs, "black_metal")]
    if lod < 2:
        parts.append(kit.tube("motor", (0.0, 0.0, 0.0), (0.0, -0.045, 0.0), 0.018, 10 if lod == 0 else 6, "black_metal"))
    return kit.join(parts, "compressor")


def parts():
    return [{"kind": "horn", "path": "horn/%s.glb" % name, "build": build, "mounts": {}}
        for name, build in (("disc", disc), ("snail", snail), ("trumpet", trumpet), ("klaxon", klaxon), ("bulb", bulb), ("compressor", compressor))]
