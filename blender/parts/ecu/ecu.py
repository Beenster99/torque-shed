"""The ECU BikeModel._draw_ecu tucks under the side panel, round its middle in the game's axes (a
point (x, y, z) is Blender's (x, -z, y)):

- "ecu/box.glb": the control box, 35 by 80 by 130 mm, its finned alloy heat sink on the outer face
  (+X) and its loom plug on the top at the front.

Tags: paint (the box's colour), cast_alloy (the heat sink), plastic (the plug), raw_steel (screws)."""

import kit


def g(x, y, z):
    return (x, -z, y)


def box(name, c, half, tag, segs=8, n=8.0):
    """A box round game point `c` with slightly rounded edges."""
    x, y, z = c
    hx, hy, hz = half
    return kit.loft(name, [(-z - hz, hx, hy, hy, n), (-z + hz, hx, hy, hy, n)], segs, tag, at=(x, 0.0, y))


def ecu(lod):
    segs = [16, 8, 4][lod]
    parts = [box("case", (0.0, 0.0, 0.0), (0.0175, 0.04, 0.065), "paint", segs, 6.0 if lod < 2 else 20.0)]
    # The heat sink: a plate with fins along it.
    parts.append(box("sink", (0.0185, 0.0, 0.0), (0.0015, 0.025, 0.045), "cast_alloy", 4, 20.0))
    if lod < 2:
        for k in range(7 if lod == 0 else 3):
            y = -0.021 + 0.042 * k / (6 if lod == 0 else 2)
            parts.append(box("fin", (0.0215, y, 0.0), (0.0015, 0.0012, 0.044), "cast_alloy", 4, 20.0))
        parts.append(box("plug", (0.0, 0.044, -0.045), (0.012, 0.006, 0.016), "plastic", 6, 6.0))
    if lod == 0:
        for y in (-0.034, 0.034):
            for z in (-0.058, 0.058):
                parts.append(kit.tube("screw", g(0.0175, y, z), g(0.0195, y, z), 0.0025, 6, "raw_steel"))
    return kit.join(parts, "box")


def parts():
    return [{"kind": "ecu", "path": "ecu/box.glb", "build": ecu, "mounts": {}}]
