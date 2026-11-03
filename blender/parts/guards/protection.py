"""The engine's protection and the small guards BikeModel._draw_guards and _draw_lever_guards put on,
and the linear steering damper's body, in the game's axes round the point each goes on (a point
(x, y, z) in the game's axes is Blender's (x, -z, y)). Crash bars, cages and the lever guards' hoops
are the frame's round tube swept along their lines by the game.

- "guards/plate.glb": an adventure bike's alloy bash plate under the engine, round the middle of
  its tray, drawn for a 700 cc engine (0.42 m long, the game stretches it along to the engine's
  length): the tray with its sides turned up, the lip swept up in front of the cases, drain holes
  and the bolts that hold it to the frame.
- "guards/skid.glb": an MX skid plate, narrower and thicker, with ribs underneath and its lip.
- "guards/bung.glb": a crash bung (frame slider): a nylon puck on an alloy spacer, its axis along
  +X out from the frame, its bolt cap on the end.
- "guards/lever_boss.glb": the lever guard's boss over the bar end, along +Y (out along the bar):
  a knurled alloy collar with its socket screw.
- "damper/linear.glb": a linear steering damper's body, from its back end at the origin 0.15 m
  along +Y: the oil body, its adjuster knob at the back, the clamp band to the frame and the
  rod's seal at the front.

Tags: paint (the part's colour), black_metal, plastic, raw_steel, polished_alloy, anodised."""

import math

import kit

DETAIL = [{"round": 16, "small": 8}, {"round": 10, "small": 6}, {"round": 6, "small": 4}]
PLATE_LEN = 0.42


def g(x, y, z):
    return (x, -z, y)


def box_y(name, c, half, tag, r=0.004, segs=2, bevel=0.0):
    """A rounded box round game point `c`, rounded seen from above (the game's Y)."""
    x, y, z = c
    hx, hy, hz = half
    return kit.prism(name, kit.rounded_rect(hx, hz, r, segs), y - hy, y + hy, tag, bevel, at=(x, -z, 0.0))


def side_plate(name, x, pts, thick, tag):
    """A flat plate across at x through the outline `pts` of (y, z) points (game axes)."""
    return kit.prism(name, [(-z, y) for y, z in pts], x - thick * 0.5, x + thick * 0.5, tag, plane="YZ")


def lip(name, w, t, a, b, tag):
    """A flat plank `w` across and `t` thick from (y, z) point a to b (game axes)."""
    (ya, za), (yb, zb) = a, b
    dy, dz = yb - ya, zb - za
    n = math.hypot(dy, dz)
    ny, nz = -dz / n * t * 0.5, dy / n * t * 0.5
    pts = [(ya + ny, za + nz), (yb + ny, zb + nz), (yb - ny, zb - nz), (ya - ny, za - nz)]
    return side_plate(name, 0.0, pts, w, tag)


def plate(skid, lod):
    d = DETAIL[lod]
    w = 0.19 if skid else 0.24
    t = 0.014 if skid else 0.01
    hl = PLATE_LEN * 0.5
    parts = [box_y("tray", (0.0, 0.0, 0.0), (w * 0.5, t * 0.5, hl), "paint", 0.03 if lod < 2 else 0.01, 3 if lod < 2 else 1)]
    # The lip up in front of the cases (BikeModel's plank, from just ahead of the tray up and forward).
    parts.append(lip("lip", w * 0.9, t, (0.005, -hl - 0.01), (0.095, -hl - 0.06), "paint"))
    if not skid:
        for side in (-1.0, 1.0):
            parts.append(side_plate("side", side * w * 0.5, [(0.0, -hl + 0.03), (0.045, -hl + 0.06), (0.045, hl - 0.06), (0.0, hl - 0.03)], 0.008, "paint"))
    if lod < 2:
        if skid:
            # Ribs along its underside.
            for k in range(5):
                x = -w * 0.36 + w * 0.72 * k / 4
                parts.append(box_y("rib", (x, -t * 0.5 - 0.003, 0.0), (0.003, 0.003, hl * 0.85), "paint", 0.0015, 1))
        else:
            # Drain holes through the tray, dark.
            for z in (-0.08, 0.0, 0.08):
                parts.append(kit.tube("hole", g(0.0, -t * 0.5 - 0.0005, z), g(0.0, t * 0.5 + 0.0005, z), 0.012, d["round"], "black_metal"))
    if lod == 0:
        for x in (-w * 0.38, w * 0.38):
            for z in (-hl + 0.025, hl - 0.025):
                parts.append(kit.hex_nut("bolt", g(x, -t * 0.5, z), (0.0, -1.0, 0.0), 0.0055, 0.004))
        for x in (-w * 0.3, w * 0.3):
            parts.append(kit.hex_nut("bolt", g(x, 0.07, -hl - 0.048), (0.0, 0.48, -0.88), 0.0055, 0.004))
    return kit.join(parts, "skid" if skid else "plate")


def bung(lod):
    d = DETAIL[lod]
    parts = [kit.tube("spacer", g(-0.025, 0.0, 0.0), g(-0.008, 0.0, 0.0), 0.016, d["round"], "polished_alloy"),
        kit.tube("puck", g(-0.01, 0.0, 0.0), g(0.025, 0.0, 0.0), 0.022, d["round"], "plastic")]
    if lod < 2:
        parts.append(kit.tube("cap", g(0.025, 0.0, 0.0), g(0.028, 0.0, 0.0), 0.017, d["round"], "plastic"))
        parts.append(kit.tube("edge", g(0.021, 0.0, 0.0), g(0.025, 0.0, 0.0), 0.022, d["round"], "plastic", r_end=0.019))
    if lod == 0:
        parts.append(kit.tube("socket", g(0.027, 0.0, 0.0), g(0.0285, 0.0, 0.0), 0.007, 6, "raw_steel"))
    return kit.join(parts, "bung")


def lever_boss(lod):
    d = DETAIL[lod]
    parts = [kit.tube("collar", g(0.0, -0.008, 0.0), g(0.0, 0.006, 0.0), 0.019, d["round"], "paint"),
        kit.tube("face", g(0.0, 0.006, 0.0), g(0.0, 0.008, 0.0), 0.019, d["round"], "paint", r_end=0.016)]
    if lod == 0:
        for k in range(12):
            a = 2.0 * math.pi * k / 12
            parts.append(kit.tube("knurl", g(math.cos(a) * 0.0192, -0.006, math.sin(a) * 0.0192), g(math.cos(a) * 0.0192, 0.004, math.sin(a) * 0.0192), 0.0015, 4, "paint"))
    if lod < 2:
        parts.append(kit.tube("screw", g(0.0, 0.008, 0.0), g(0.0, 0.0105, 0.0), 0.0065, d["small"], "raw_steel"))
    return kit.join(parts, "lever_boss")


def linear(lod):
    d = DETAIL[lod]
    parts = [kit.tube("body", g(0.0, 0.0, 0.0), g(0.0, 0.13, 0.0), 0.016, d["round"], "paint"),
        kit.tube("seal", g(0.0, 0.13, 0.0), g(0.0, 0.15, 0.0), 0.012, d["round"], "black_metal", r_end=0.009)]
    if lod < 2:
        parts.append(kit.tube("knob", g(0.0, -0.016, 0.0), g(0.0, 0.0, 0.0), 0.014, d["small"] + 2, "anodised"))
    if lod < 2:
        parts.append(kit.tube("band", g(0.0, 0.05, 0.0), g(0.0, 0.07, 0.0), 0.0185, d["round"], "black_metal"))
        parts.append(box_y("clamp", (-0.022, 0.06, 0.0), (0.008, 0.01, 0.012), "black_metal", 0.003, 1))
    if lod == 0:
        for k in range(8):
            a = 2.0 * math.pi * k / 8
            parts.append(kit.tube("grip", g(math.cos(a) * 0.0142, -0.014, math.sin(a) * 0.0142), g(math.cos(a) * 0.0142, -0.002, math.sin(a) * 0.0142), 0.0018, 4, "anodised"))
        for y in (0.004, 0.126):
            parts.append(kit.tube("ring", g(0.0, y, 0.0), g(0.0, y + 0.002, 0.0), 0.0168, d["round"], "polished_alloy"))
    return kit.join(parts, "linear")


def parts():
    return [
        {"kind": "guards", "path": "guards/plate.glb", "build": lambda lod: plate(False, lod), "mounts": {}},
        {"kind": "guards", "path": "guards/skid.glb", "build": lambda lod: plate(True, lod), "mounts": {}},
        {"kind": "guards", "path": "guards/bung.glb", "build": bung, "mounts": {}},
        {"kind": "guards", "path": "guards/lever_boss.glb", "build": lever_boss, "mounts": {}},
        {"kind": "damper", "path": "damper/linear.glb", "build": linear, "mounts": {}},
    ]
