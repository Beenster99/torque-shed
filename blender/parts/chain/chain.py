"""The drive chain: "chain/run.glb", a straight strip of RUN_LINKS links of 5/8 inch pitch along
+Z in the game's axes from 0 to RUN_LINKS * PITCH (Blender's -Y; a point (x, y, z) in the game's
axes is Blender's (x, -z, y)), its side plates upright in the chain's plane round X 0. The game
lays strips end to end along each run between the sprockets.

Every surface is tagged raw_steel; the game gives it the chain's own colour, rust and all."""

import kit

PITCH = 0.015875
RUN_LINKS = 8


def g(x, y, z):
    return (x, -z, y)


def run(lod):
    parts = []
    if lod == 1:
        # Seen from a few metres: the two rows of side plates.
        for side in (-1.0, 1.0):
            parts.append(kit.loft("plates", [(-RUN_LINKS * PITCH, 0.0015, 0.0055, 0.0055, 4.0), (0.0, 0.0015, 0.0055, 0.0055, 4.0)], 4, "raw_steel", at=(side * 0.0065, 0.0, 0.0)))
        return kit.join(parts, "run")
    if lod == 2:
        parts.append(kit.loft("strip", [(-RUN_LINKS * PITCH, 0.008, 0.0055, 0.0055, 4.0), (0.0, 0.008, 0.0055, 0.0055, 4.0)], 4, "raw_steel"))
        return kit.join(parts, "run")
    plate_segs = 4
    for k in range(RUN_LINKS):
        z = (k + 0.5) * PITCH
        outer = k % 2 == 0
        x = 0.0075 if outer else 0.0055
        for side in (-1.0, 1.0):
            # An oval side plate along the chain.
            secs = [(-z - PITCH * 0.62, 0.0009, 0.0042, 0.0042, 2.0), (-z, 0.0009, 0.0052, 0.0052, 2.0), (-z + PITCH * 0.62, 0.0009, 0.0042, 0.0042, 2.0)]
            parts.append(kit.loft("plate", secs, plate_segs, "raw_steel", at=(side * x, 0.0, 0.0)))
        # The roller across the chain at the link's end.
        parts.append(kit.tube("roller", g(-0.0046, 0.0, k * PITCH), g(0.0046, 0.0, k * PITCH), 0.005, 6, "raw_steel"))
    return kit.join(parts, "run")


def parts():
    return [{"kind": "chain", "path": "chain/run.glb", "build": run, "mounts": {}}]
