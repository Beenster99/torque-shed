"""The number boards BikeModel._draw_number_boards bolts on, each round its middle in the game's
axes (a point (x, y, z) is Blender's (x, -z, y)); the game prints the race number on them:

- "number_board/plate.glb": the MX front plate, 220 by 210 mm and 8 mm thick, upright and facing
  the game's -Z, with its rolled lip round the edge and two strap slots at the top (the game
  turns and stretches it for the side boards and the shroud wings).
- "number_board/oval.glb": an oval board's blank, a disc 100 mm in radius and 8 mm thick lying flat
  (its face up the game's Y; the game stands it up and stretches it into the oval), with its lip.

Tags: paint (the board's colour), black_metal (the strap slots)."""

import math

import kit


def g(x, y, z):
    return (x, -z, y)


def outline(hx, hy, r, segs):
    return kit.rounded_rect(hx, hy, r, segs)


def plate(lod):
    cs = [6, 3, 1][lod]
    pts = outline(0.11, 0.105, 0.03, cs)
    ob = kit.prism("plate", pts, -0.003, 0.003, "paint")
    # (A prism stands out along Blender Z; turned, it stands out along the game's Z, its outline upright.)
    ob.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    parts = [ob]
    if lod < 2:
        lip = [g(x, y, 0.0) for x, y in outline(0.106, 0.101, 0.026, cs)]
        parts.append(kit.sweep("lip", lip + lip[:2], 0.004, [8, 4][lod], "paint"))
        for x in (-0.05, 0.05):
            slot = kit.prism("slot", outline(0.014, 0.004, 0.003, 2), -0.0042, 0.0042, "black_metal", at=(x, 0.085, 0.0))
            slot.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
            parts.append(slot)
    return kit.join(parts, "plate")


def oval(lod):
    segs = [40, 20, 8][lod]
    ob = kit.loft("board", [(-0.003, 0.1, 0.1, 0.1, 2.0), (0.003, 0.1, 0.1, 0.1, 2.0)], segs, "paint")
    ob.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    parts = [ob]
    if lod < 2:
        lip = kit.ring("lip", 0.0, 0.096, 0.004, segs, "paint", [6, 4][lod])
        lip.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
        parts.append(lip)
    return kit.join(parts, "oval")


def parts():
    return [{"kind": "number_board", "path": "number_board/%s.glb" % name, "build": build, "mounts": {}}
        for name, build in (("plate", plate), ("oval", oval))]
