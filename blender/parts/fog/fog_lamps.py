"""The fog and spot lamps BikeModel._draw_fog_lights hangs off the fork, each round its middle and
looking forward (game -Z; a point (x, y, z) in the game's axes is Blender's (x, -z, y)):

- "fog/round.glb": a small round lamp, 40 mm in radius, its glass at z -0.03.
- "fog/cube.glb": a 60 mm cube LED pod.
- "fog/rally.glb": a big rally lamp, 60 mm in radius and 60 mm deep, with its stone guard bars.
- "fog/bar.glb": the LED light bar, 340 mm across.

The shell is tagged paint (the lamps' finish), the glass lens_white (the game lays its own lit
material over it), the bracket black_metal."""

import kit


def g(x, y, z):
    return (x, -z, y)


def round_lamp(lod):
    segs = [20, 12, 4][lod]
    parts = [kit.sphere("shell", (0.0, 0.0, 0.0), 0.04, (1.0, 0.8, 1.0), segs, "paint")]
    parts.append(kit.loft("glass", [(0.026, 0.036, 0.036, 0.036, 2.0), (0.034, 0.033, 0.033, 0.033, 2.0)], segs, "lens_white"))
    if lod < 2:
        parts.append(kit.ring("bezel", 0.028, 0.036, 0.003, segs, "paint", 4))
        parts.append(kit.tube("stud", (0.0, -0.01, -0.03), (0.0, -0.01, -0.05), 0.006, 6, "black_metal"))
    return kit.join(parts, "round")


def cube(lod):
    segs = [12, 8, 4][lod]
    parts = [kit.loft("pod", [(-0.03, 0.03, 0.03, 0.03, 6.0), (0.028, 0.03, 0.03, 0.03, 6.0)], segs, "paint"),
        kit.loft("glass", [(0.027, 0.025, 0.025, 0.025, 6.0), (0.033, 0.024, 0.024, 0.024, 6.0)], segs, "lens_white")]
    if lod == 0:
        for k in range(4):
            parts.append(kit.loft("fin", [(-0.034, 0.002, 0.026, 0.026, 4.0), (-0.03, 0.002, 0.026, 0.026, 4.0)], 4, "paint", at=(-0.018 + k * 0.012, 0.0, 0.0)))
    return kit.join(parts, "cube")


def rally(lod):
    segs = [24, 14, 6][lod]
    parts = [kit.loft("can", [(-0.03, 0.045, 0.045, 0.045, 2.0), (-0.015, 0.058, 0.058, 0.058, 2.0), (0.03, 0.06, 0.06, 0.06, 2.0)]
        if lod < 2 else [(-0.03, 0.05, 0.05, 0.05, 2.0), (0.03, 0.06, 0.06, 0.06, 2.0)], segs, "paint"),
        kit.loft("glass", [(0.028, 0.055, 0.055, 0.055, 2.0), (0.036, 0.05, 0.05, 0.05, 2.0)], segs, "lens_white")]
    if lod < 2:
        parts.append(kit.ring("bezel", 0.031, 0.057, 0.004, segs, "paint", 4))
        for i in range(3):
            parts.append(kit.tube("bar", g(-0.055, (i - 1) * 0.03, -0.04), g(0.055, (i - 1) * 0.03, -0.04), 0.003, 6, "paint"))
    return kit.join(parts, "rally")


def bar(lod):
    segs = [12, 8, 4][lod]
    parts = [kit.loft("bar", [(-0.025, 0.17, 0.0225, 0.0225, 6.0), (0.024, 0.17, 0.0225, 0.0225, 6.0)], segs, "paint"),
        kit.loft("glass", [(0.023, 0.155, 0.015, 0.015, 8.0), (0.028, 0.154, 0.014, 0.014, 8.0)], segs, "lens_white")]
    if lod == 0:
        # The LEDs' reflector cups behind the glass, and the end brackets.
        for k in range(10):
            parts.append(kit.loft("cup", [(0.0275, 0.009, 0.009, 0.009, 2.0), (0.029, 0.007, 0.007, 0.007, 2.0)], 8, "lens_white", at=(-0.135 + k * 0.03, 0.0, 0.0)))
        for x in (-1.0, 1.0):
            parts.append(kit.loft("bracket", [(-0.015, 0.004, 0.03, 0.01, 4.0), (0.015, 0.004, 0.03, 0.01, 4.0)], 4, "black_metal", at=(x * 0.174, 0.0, -0.01)))
    return kit.join(parts, "bar")


def parts():
    return [{"kind": "fog", "path": "fog/%s.glb" % name, "build": build, "mounts": {}}
        for name, build in (("round", round_lamp), ("cube", cube), ("rally", rally), ("bar", bar))]
