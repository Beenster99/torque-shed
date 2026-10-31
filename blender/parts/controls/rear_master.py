"""The rear brake's master cylinder: "controls/rear_master.glb", upright round its middle (the
game puts it where its code-built cylinder was, above the pushrod), with its fluid cap, the hose
nipple and the mounting ears (a point (x, y, z) in the game's axes is Blender's (x, -z, y)).

Tagged paint (the body, in the part's colour), black_metal (the cap) and raw_steel (the nipple)."""

import kit


def body(lod):
    segs = [16, 10, 6][lod]
    parts = [kit.loft("body", [(-0.02, 0.018, 0.018, 0.018, 2.0), (0.02, 0.02, 0.02, 0.02, 2.0)], segs, "paint")]
    parts[0].rotation_euler = (1.5707963, 0.0, 0.0)
    if lod < 2:
        parts.append(kit.tube("cap", (0.0, 0.0, 0.02), (0.0, 0.0, 0.028), 0.016, segs, "black_metal"))
        parts.append(kit.loft("ear", [(-0.008, 0.032, 0.006, 0.006, 4.0), (0.008, 0.032, 0.006, 0.006, 4.0)], 6, "paint", at=(0.0, 0.0, -0.012)))
    if lod == 0:
        parts.append(kit.tube("nipple", (0.0, -0.018, -0.01), (0.0, -0.03, -0.012), 0.004, 6, "raw_steel"))
    return kit.join(parts, "rear_master")


def parts():
    return [{"kind": "controls", "path": "controls/rear_master.glb", "build": body, "mounts": {}}]
