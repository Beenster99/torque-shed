"""The cooling: what BikeModel._draw_cooling puts in front of the engine (a point (x, y, z) in the
game's axes is Blender's (x, -z, y)).

- "radiator/core.glb": a radiator a unit wide and a unit tall round its middle (the game
  stretches it to the part's width and height), 50 mm deep: the finned core, the side tanks, the
  top and bottom of its surround and the filler cap (the game puts its grille in front, at -Z).
- "radiator/oil_cooler.glb": an oil cooler, 240 by 100 mm, with its rows of fins and its unions.

The core is tagged black_metal (the game gives it its fine fin texture), the tanks and surround
paint, the cap and unions chrome."""

import kit


def box(name, c, half, tag, segs=4, n=10.0):
    x, y, z = c
    hx, hy, hz = half
    return kit.loft(name, [(-z - hz, hx, hy, hy, n), (-z + hz, hx, hy, hy, n)], segs, tag, at=(x, 0.0, y))


def core(lod):
    parts = [box("core", (0.0, 0.0, 0.0), (0.5, 0.5, 0.025), "black_metal")]
    if lod < 2:
        for sx in (-1.0, 1.0):
            parts.append(box("tank", (sx * 0.54, 0.0, 0.0), (0.04, 0.53, 0.0275), "paint", 8, 4.0))
        for sy in (-1.0, 1.0):
            parts.append(box("rail", (0.0, sy * 0.535, 0.0), (0.55, 0.035, 0.025), "paint", 8, 4.0))
    if lod == 0:
        # The core's fins, a row of fine ribs across its face, and the filler cap on the right tank.
        for k in range(24):
            parts.append(box("fin", (0.0, -0.48 + k * (0.96 / 23), -0.0255), (0.49, 0.0025, 0.0012), "black_metal"))
        parts.append(kit.tube("cap", (0.54, 0.0, 0.56), (0.54, 0.0, 0.6), 0.03, 10, "chrome"))
    return kit.join(parts, "core")


def oil_cooler(lod):
    parts = [box("core", (0.0, 0.0, 0.0), (0.12, 0.05, 0.0175), "black_metal")]
    if lod < 2:
        for sx in (-1.0, 1.0):
            parts.append(box("end", (sx * 0.125, 0.0, 0.0), (0.008, 0.058, 0.02), "paint", 6, 4.0))
            parts.append(kit.tube("union", (sx * 0.1, 0.0, -0.05), (sx * 0.1, 0.0, -0.065), 0.007, 8, "chrome"))
    if lod == 0:
        for k in range(10):
            parts.append(box("fin", (0.0, -0.045 + k * 0.01, -0.018), (0.118, 0.0015, 0.001), "black_metal"))
    return kit.join(parts, "oil_cooler")


def parts():
    return [{"kind": "radiator", "path": "radiator/core.glb", "build": core, "mounts": {}},
        {"kind": "radiator", "path": "radiator/oil_cooler.glb", "build": oil_cooler, "mounts": {}}]
