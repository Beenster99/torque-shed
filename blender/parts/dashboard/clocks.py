"""The clocks' housings, drawn in the dial's own frame as BikeModel._draw_dashboard leans it back
to the rider: +X across, +Y up out of the face, +Z down towards the rider's knees (a point
(x, y, z) here in that frame is Blender's (x, -z, y), so a face looks up Blender +Z). The game
draws the lit faces, tick marks, needles and screens over them.

- "dashboard/dial.glb": one round clock's cup, 50 mm in radius and 50 mm deep round its middle,
  with a chrome bezel round its face's edge and a mounting stud underneath.
- "dashboard/lcd.glb", "dashboard/tft.glb": the screen housings, 160 by 90 and 200 by 120 mm,
  30 mm thick round their middle, with a raised lip round the screen and a mount underneath.
- "dashboard/bar.glb": the slim bar of a race dash, 220 by 90 mm.

A housing is tagged paint (the dashboard part's colour); bezels chrome, mounts black_metal."""

import math

import kit


def dial(lod):
    segs = [28, 16, 8][lod]
    full = [(-0.025, 0.04), (-0.021, 0.048), (-0.015, 0.05), (0.02, 0.05), (0.024, 0.048)]
    secs = full if lod == 0 else ([full[0], full[2], full[4]] if lod == 1 else [full[1], full[4]])
    cup = kit.loft("cup", [(y, r, r, r, 2.0) for y, r in secs], segs, "paint")
    cup.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    parts = [cup]
    if lod < 2:
        bezel = kit.ring("bezel", 0.0245, 0.0465, 0.003, segs, "chrome", 6 if lod == 0 else 4)
        bezel.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
        parts.append(bezel)
        parts.append(kit.tube("stud", (0.0, 0.0, -0.025), (0.0, 0.0, -0.034), 0.006, 8, "black_metal"))
    return kit.join(parts, "dial")


def housing(name, hx, hz, lod):
    """A rounded slab hx by hz (half sizes, in the face's plane), 30 mm thick, with a lip round
    its screen."""
    n = 5.0
    segs = [24, 16, 8][lod]
    t = 0.015
    e = 0.004
    secs = [(-hz, hx - e, t - e, t - e, n), (-hz + e, hx, t, t, n), (hz - e, hx, t, t, n), (hz, hx - e, t - e, t - e, n)]
    if lod == 2:
        secs = [(-hz, hx, t, t, n), (hz, hx, t, t, n)]
    parts = [kit.loft(name, secs, segs, "paint")]
    if lod < 2:
        # The lip round the screen (just inside the edge, standing proud of the face).
        parts.append(kit.loft("lip", [(-hz + 0.006, hx - 0.006, t + 0.0008, t - 0.002, n), (hz - 0.006, hx - 0.006, t + 0.0008, t - 0.002, n)], segs, "black_metal"))
        parts.append(kit.tube("mount", (0.0, 0.0, -t), (0.0, 0.0, -t - 0.012), 0.008, 8, "black_metal"))
    return kit.join(parts, name)


def parts():
    out = [{"kind": "dashboard", "path": "dashboard/dial.glb", "build": dial, "mounts": {}}]
    for name, hx, hz in (("lcd", 0.08, 0.045), ("tft", 0.1, 0.06), ("bar", 0.11, 0.045)):
        out.append({"kind": "dashboard", "path": "dashboard/%s.glb" % name, "build": (lambda lod, name=name, hx=hx, hz=hz: housing(name, hx, hz, lod)), "mounts": {}})
    return out
