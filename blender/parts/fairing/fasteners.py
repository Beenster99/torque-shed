"""The fasteners round a fairing's edges, which the game sets along each panel a little in from its
edge (BlenderParts.edge_spots), as a road bike's panels are held on by screws into rubber well nuts
and a race bike's by quarter-turn fasteners. Each stands on the panel at its origin, its head up +Y
in the game (Blender +Z) out of the surface: "button", a black button-head screw on a rubber well
nut's collar; "dzus", a race fairing's slotted quarter-turn head in its steel cup."""

import math

import kit

SEGS = [16, 8, 4]


def turned(name, profile, segs, tag):
    """A solid turned round the fastener's axis (up out of the panel): `profile` as (height, radius)."""
    ob = kit.revolve(name, profile, segs, tag)
    ob.rotation_euler = (0.0, -math.pi * 0.5, 0.0)
    return ob


def button(lod):
    segs = SEGS[lod]
    head = [(0.0011, 0.0), (0.0011, 0.0056), (0.0024, 0.005), (0.0033, 0.0034), (0.0037, 0.0)]
    parts = [turned("head", head, segs, "black_metal")]
    if lod < 2:
        collar = [(-0.0008, 0.0), (-0.0008, 0.0072), (0.0006, 0.0072), (0.0012, 0.0066), (0.0012, 0.0)]
        parts.append(turned("collar", collar, segs, "rubber"))
    return kit.join(parts, "fastener")


def dzus(lod):
    segs = SEGS[lod]
    cup = [(-0.0008, 0.0), (-0.0008, 0.0078), (0.0005, 0.0078), (0.001, 0.0068), (0.001, 0.0)]
    head = [(0.001, 0.0), (0.001, 0.0058), (0.0022, 0.0052), (0.003, 0.0036), (0.0033, 0.0)]
    parts = [turned("cup", cup, segs, "raw_steel"), turned("head", head, segs, "chrome")]
    if lod == 0:
        # The slot across the head, for the quarter turn.
        parts.append(kit.tube("slot", (-0.0045, 0.0, 0.0031), (0.0045, 0.0, 0.0031), 0.0007, 4, "black_metal"))
    return kit.join(parts, "fastener")


def parts():
    return [{"kind": "fastener", "path": "fairing/fastener/%s.glb" % name, "build": build, "mounts": {}}
        for name, build in (("button", button), ("dzus", dzus))]
