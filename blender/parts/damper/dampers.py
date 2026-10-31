"""The steering dampers' bodies (the linear one's body and rod are swept from the frame's round
tube by the game), round their middles (a point (x, y, z) in the game's axes is Blender's
(x, -z, y)):

- "damper/rotary.glb": a rotary damper's puck, 35 mm in radius and 22 mm tall up its axis (the
  game's Y, set flat on the top yoke), with its adjuster knob on top and the link's arm.
- "damper/friction.glb": an old friction damper's star knob under the steering head, round its
  axis (the game's Y).

Tagged paint (the damper's colour) and black_metal (the knobs)."""

import math

import kit


def rotary(lod):
    segs = [24, 14, 8][lod]
    puck = kit.loft("puck", [(-0.011, 0.033, 0.033, 0.033, 2.0), (-0.009, 0.035, 0.035, 0.035, 2.0), (0.009, 0.035, 0.035, 0.035, 2.0), (0.011, 0.033, 0.033, 0.033, 2.0)]
        if lod < 2 else [(-0.011, 0.035, 0.035, 0.035, 2.0), (0.011, 0.035, 0.035, 0.035, 2.0)], segs, "paint")
    puck.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    parts = [puck]
    if lod < 2:
        parts.append(kit.tube("knob", (0.0, 0.0, 0.011), (0.0, 0.0, 0.023), 0.008, 10, "black_metal"))
        parts.append(kit.loft("arm", [(-0.06, 0.006, 0.004, 0.004, 4.0), (-0.02, 0.008, 0.004, 0.004, 4.0)], 6, "paint", at=(0.0, 0.0, 0.006)))
    return kit.join(parts, "rotary")


def friction(lod):
    segs = [16, 10, 6][lod]
    pts = []
    lobes = 5
    n = lobes * (4 if lod == 0 else 2)
    for k in range(n):
        a = 2.0 * math.pi * k / n
        r = 0.022 if (k % (n // lobes)) < (n // lobes) // 2 else 0.016
        pts.append((r * math.cos(a), r * math.sin(a)))
    parts = [kit.prism("knob", pts, -0.009, 0.009, "black_metal")]
    if lod < 2:
        parts.append(kit.tube("rod", (0.0, 0.0, 0.009), (0.0, 0.0, 0.05), 0.006, segs, "paint"))
    return kit.join(parts, "friction")


def parts():
    return [{"kind": "damper", "path": "damper/rotary.glb", "build": rotary, "mounts": {}},
        {"kind": "damper", "path": "damper/friction.glb", "build": friction, "mounts": {}}]
