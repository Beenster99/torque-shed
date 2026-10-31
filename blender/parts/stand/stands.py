"""The stands' cast pieces (the legs are the frame's round tube, swept by the game):

- "stand/foot.glb": a stand's foot pad, 50 mm across, 70 mm long and 12 mm thick round its
  middle, with a lip turned up at its toe and a boss where the leg goes in. The centre stand's are
  the same pad shortened by the game.
- "stand/pivot.glb": the side stand's pivot lug, 30 by 40 by 40 mm round the pivot, with its bolt
  through and the spring's hook.

A point (x, y, z) in the game's axes is Blender's (x, -z, y). Tagged paint (the stand's colour),
the bolt raw_steel and the spring black_metal."""

import kit


def g(x, y, z):
    return (x, -z, y)


def foot(lod):
    segs = [12, 8, 4][lod]
    parts = [kit.loft("pad", [(-0.035, 0.022, 0.006, 0.006, 4.0), (-0.03, 0.025, 0.006, 0.006, 4.0), (0.03, 0.025, 0.006, 0.006, 4.0), (0.035, 0.022, 0.006, 0.006, 4.0)] if lod < 2
        else [(-0.035, 0.025, 0.006, 0.006, 4.0), (0.035, 0.025, 0.006, 0.006, 4.0)], segs, "paint")]
    if lod < 2:
        parts.append(kit.tube("boss", (0.0, 0.0, 0.004), (0.0, 0.0, 0.016), 0.014, 8 if lod == 0 else 6, "paint"))
    if lod == 0:
        # Ribs under the pad for grip on soft ground.
        for k in range(3):
            parts.append(kit.loft("rib", [(-0.03, 0.002, 0.0, 0.003, 2.0), (0.03, 0.002, 0.0, 0.003, 2.0)], 4, "paint", at=(-0.015 + k * 0.015, 0.0, -0.006)))
    return kit.join(parts, "foot")


def pivot(lod):
    segs = [12, 8, 4][lod]
    parts = [kit.loft("lug", [(-0.02, 0.015, 0.02, 0.02, 4.0), (0.02, 0.015, 0.02, 0.02, 4.0)] if lod < 2 else [(-0.02, 0.015, 0.02, 0.02, 4.0), (0.02, 0.015, 0.02, 0.02, 4.0)], segs, "paint")]
    if lod < 2:
        parts.append(kit.tube("bolt", (-0.019, 0.0, 0.0), (0.019, 0.0, 0.0), 0.006, 8 if lod == 0 else 6, "raw_steel"))
    if lod == 0:
        parts.append(kit.hex_nut("nut", (0.019, 0.0, 0.0), (1.0, 0.0, 0.0), 0.009, 0.006))
        # The return spring, a few turns stretched forward to its frame hook.
        pts = []
        import math
        for i in range(17):
            a = i / 16.0 * 4.0 * math.pi
            pts.append((0.017 + math.cos(a) * 0.004, -0.004 + i * 0.0014, -0.01 + math.sin(a) * 0.004))
        parts.append(kit.sweep("spring", pts, 0.0012, 4, "black_metal"))
    return kit.join(parts, "pivot")


def parts():
    return [{"kind": "stand", "path": "stand/foot.glb", "build": foot, "mounts": {}},
        {"kind": "stand", "path": "stand/pivot.glb", "build": pivot, "mounts": {}}]
