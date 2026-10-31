"""The sprockets: each count of teeth the catalogue's final drives use, round the axle (the game's
X, Blender's X), its teeth on the chain's pitch circle as BikeModel.sprocket_radius works it out
(a point (x, y, z) in the game's axes is Blender's (x, -z, y)).

- "final_drive/front_<teeth>.glb": the gearbox sprocket, 12 mm thick, on its splined boss.
- "final_drive/rear_<teeth>.glb": the rear sprocket, 8 mm thick, with five lightening holes and
  the bolts to the cush drive.

The sprocket is tagged paint (the final drive's colour), the holes black_metal, bolts raw_steel."""

import math

import kit

PITCH = 0.015875
FRONT = [13, 14, 15, 16]
REAR = [40, 42, 45, 50, 52]


def radius(teeth):
    return PITCH / (2.0 * math.sin(math.pi / max(teeth, 6))) + 0.003


def outline(teeth, lod):
    """The toothed edge in the wheel's plane, as (y, z) in Blender's axes."""
    r = radius(teeth) - 0.003
    if lod > 0:
        n = 24 if lod == 1 else 12
        return [(r * math.cos(2.0 * math.pi * k / n), r * math.sin(2.0 * math.pi * k / n)) for k in range(n)]
    pts = []
    shape = [(-0.32, r - 0.0045), (-0.16, r + 0.0015), (0.16, r + 0.0015), (0.32, r - 0.0045)]
    for k in range(teeth):
        for f, rr in shape:
            a = 2.0 * math.pi * (k + 0.5 + f) / teeth
            pts.append((rr * math.cos(a), rr * math.sin(a)))
    return pts


def disc(name, r, x0, x1, segs, tag, at=(0.0, 0.0, 0.0)):
    return kit.prism(name, [(r * math.cos(2.0 * math.pi * k / segs), r * math.sin(2.0 * math.pi * k / segs)) for k in range(segs)], x0, x1, tag, plane="YZ", at=at)


def front(teeth):
    def build(lod):
        parts = [kit.prism("sprocket", outline(teeth, lod), -0.006, 0.006, "paint", plane="YZ")]
        if lod < 2:
            parts.append(disc("boss", 0.016, -0.009, 0.009, 12 if lod == 0 else 8, "paint"))
        if lod == 0:
            parts.append(kit.hex_nut("nut", (-0.011, 0.0, 0.0), (-1.0, 0.0, 0.0), 0.012, 0.006))
        return kit.join(parts, "front_%d" % teeth)
    return build


def rear(teeth):
    def build(lod):
        r = radius(teeth)
        parts = [kit.prism("sprocket", outline(teeth, lod), -0.004, 0.004, "paint", plane="YZ")]
        if lod < 2:
            for k in range(5):
                a = 2.0 * math.pi * k / 5
                at = (0.0, math.sin(a) * r * 0.72, math.cos(a) * r * 0.72)
                parts.append(disc("hole", r * 0.12, -0.00425, 0.00425, 10 if lod == 0 else 6, "black_metal", at))
        if lod == 0:
            for k in range(6):
                a = 2.0 * math.pi * (k + 0.5) / 6
                parts.append(kit.hex_nut("nut", (-0.0045, math.sin(a) * 0.05, math.cos(a) * 0.05), (-1.0, 0.0, 0.0), 0.007, 0.005))
        return kit.join(parts, "rear_%d" % teeth)
    return build


def parts():
    return [{"kind": "final_drive", "path": "final_drive/front_%d.glb" % n, "build": front(n), "mounts": {}} for n in FRONT] + \
        [{"kind": "final_drive", "path": "final_drive/rear_%d.glb" % n, "build": rear(n), "mounts": {}} for n in REAR]
