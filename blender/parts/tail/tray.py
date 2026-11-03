"""A tidy tail's tray under the seat's back (BikeModel._draw_tail's "tidy" style) and the bracket
its tail light sits on:

- "tail/tidy_tray.glb": the moulded tray, 0.18 m across, 25 mm deep and 0.28 m long round its
  middle, in the tray's own axes (the game tilts it and lifts it clear of the tyre): a rounded
  pan with its edges turned down, the stiffening ribs under it, the lip at its back and the four
  bolts that hold it to the subframe.
- "tail/lamp_bracket.glb": the slim bracket across behind the tail light, 0.16 m across.

Axes are the game's (x out, y up, z back) as Blender's (x, -z, y). Tags: `paint` (the tail's
finish), bolts `raw_steel`."""

import kit

DETAIL = [{"corner": 4}, {"corner": 2}, {"corner": 1}]


def g(x, y, z):
    return (x, -z, y)


def box(name, c, half, tag, r=0.004, segs=2, bevel=0.0):
    """A box round game point `c`, rounded seen from above."""
    x, y, z = c
    hx, hy, hz = half
    return kit.prism(name, kit.rounded_rect(hx, hz, r, segs), y - hy, y + hy, tag, bevel, at=(x, -z, 0.0))


def tray(lod):
    d = DETAIL[lod]
    parts = [box("pan", (0.0, 0.007, 0.0), (0.09, 0.005, 0.14), "paint", 0.03, d["corner"], 0.002 if lod == 0 else 0.0)]
    # The edges turned down round its sides and front, and the lip up at its back.
    for s in (-1.0, 1.0):
        parts.append(box("edge", (s * 0.086, -0.004, -0.005), (0.004, 0.008, 0.12), "paint", 0.002, 1))
    parts.append(box("lip", (0.0, 0.0, 0.134), (0.075, 0.0125, 0.004), "paint", 0.002, 1))
    if lod < 2:
        for x in (-0.045, 0.0, 0.045):
            parts.append(box("rib", (x, -0.003, 0.0), (0.003, 0.006, 0.11), "paint", 0.0015, 1))
    if lod == 0:
        for x in (-0.06, 0.06):
            for z in (-0.09, 0.05):
                parts.append(kit.hex_nut("bolt", g(x, 0.012, z), (0.0, 0.0, 1.0), 0.005, 0.003))
    return kit.join(parts, "tidy_tray")


def bracket(lod):
    d = DETAIL[lod]
    parts = [box("bracket", (0.0, 0.0, 0.0), (0.08, 0.0175, 0.004), "paint", 0.01, d["corner"])]
    if lod < 2:
        for x in (-0.06, 0.06):
            parts.append(kit.hex_nut("bolt", g(x, 0.0, 0.004), (0.0, -1.0, 0.0), 0.004, 0.003))
    return kit.join(parts, "lamp_bracket")


def parts():
    return [
        {"kind": "tail", "path": "tail/tidy_tray.glb", "build": tray, "mounts": {}},
        {"kind": "tail", "path": "tail/lamp_bracket.glb", "build": bracket, "mounts": {}},
    ]
