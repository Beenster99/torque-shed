"""The mirrors: the head shells BikeModel._mirror_head puts round each glass, and the clamp that
holds a mirror's stalk to the bar. A head is drawn in its own frame, the glass looking +Z at the
rider (a point (x, y, z) here in that frame is Blender's (x, -z, y)); the game draws the glass.

- "mirror/round.glb": a round head of unit radius (the game scales its width and height by the
  mirror's radius), its depth in metres: a domed back from z -0.013 to the rolled lip round the
  glass at z 0.011.
- "mirror/rect.glb": a rectangular head a unit square (the game stretches it to the mirror's
  width and height), the same depth.
- "mirror/clamp.glb": the clamp round the bar, of unit radius round its axis (the game's local Y,
  Blender's Z; the game scales across it to the bar), 22 mm long, with its pinch bolt's boss.

The shells are tagged paint (the mirrors' finish), the bolt black_metal."""

import math

import kit


def head(name, hw, hh, n, lod):
    segs = [28, 16, 8][lod]
    full = [(-0.013, 0.7), (-0.01, 0.9), (-0.004, 0.99), (0.008, 1.0), (0.011, 0.965)]
    secs = full if lod == 0 else ([full[0], full[2], full[3], full[4]] if lod == 1 else [full[1], full[3]])
    return kit.join([kit.loft(name, [(-z, hw * k, hh * k, hh * k, n) for z, k in secs], segs, "paint")], name)


def clamp(lod):
    segs = [16, 10, 6][lod]
    collar = kit.loft("collar", [(-0.011, 1.0, 1.0, 1.0, 2.0), (0.011, 1.0, 1.0, 1.0, 2.0)], segs, "paint")
    collar.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    parts = [collar]
    if lod < 2:
        # The pinch bolt's boss, out from the collar (in unit sizes across the bar, metres along it).
        parts.append(kit.loft("boss", [(-1.45, 0.35, 0.009, 0.009, 4.0), (-0.85, 0.35, 0.009, 0.009, 4.0)], 8, "paint"))
    if lod == 0:
        parts.append(kit.loft("bolt", [(-1.5, 0.22, 0.004, 0.004, 2.0), (-1.4, 0.22, 0.004, 0.004, 2.0)], 6, "black_metal"))
    return kit.join(parts, "clamp")


def parts():
    return [{"kind": "mirror", "path": "mirror/round.glb", "build": lambda lod: head("round", 1.0, 1.0, 2.0, lod), "mounts": {}},
        {"kind": "mirror", "path": "mirror/rect.glb", "build": lambda lod: head("rect", 0.5, 0.5, 6.0, lod), "mounts": {}},
        {"kind": "mirror", "path": "mirror/clamp.glb", "build": clamp, "mounts": {}}]
