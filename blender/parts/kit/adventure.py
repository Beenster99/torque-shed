"""The adventure kit KitModel draws on a bike, each in the game's axes (a point (x, y, z) is
Blender's (x, -z, y)), drawn at the size KitModel draws it at its reference size (the game
stretches or scales it from there):

- "kit/tank_bag.glb": a soft tank bag 260 mm long, 200 mm across and 100 mm tall, from the middle of
  its front bottom edge back along +Z, with its piping round the base and the lid's seam (the game
  leans it along the tank's top and stretches it to the bag's size).
- "kit/fuel_can.glb": the flat steel jerry can, 75 by 260 by 200 mm round its middle, the pressed X
  on its outer face (-X), its handle and spout on top.
- "kit/fuel_cell.glb": the slim alloy cell, 55 mm in radius, its round ends 480 mm apart round its
  middle along Z, with its weld seams and filler.
- "kit/rear_tank.glb": the moulded tank behind the seat, round its middle, with its filler.
- "kit/side_tank.glb": one of the rally pair low beside the engine, round its middle.
- "kit/bladder.glb": the soft bladder across the back, 360 mm long across, with its welded seams
  and filler.
- "kit/tool_roll.glb": the leather tool roll, 35 mm in radius and 220 mm across round its middle,
  with its two straps.
- "kit/tool_tube.glb": the screw-capped tool tube, 45 mm in radius, from its front end at the origin
  back 340 mm along +Z to its knurled cap.
- "kit/toolbox.glb": the alloy toolbox, 80 by 120 by 220 mm round its middle, its lid, latch, lock
  and ribs on its outer face (-X).
- "kit/bash_box.glb": the box built into the bash plate, 160 by 60 by 280 mm round its middle, on
  its plate.
- "kit/satnav.glb": a sat nav's housing for a 100 by 65 mm screen, round its middle, its face up
  the game's +Y (the game tilts it to the rider), a bezel round the screen and its buttons.
- "kit/phone.glb": a phone 136 by 87 by 9 mm round its middle, its glass facing +Z, with its camera
  bump on the back.

Tags: paint (the part's colour), paint_2 (its darker panels), leather, fabric, black_metal (caps,
latches, a phone), chrome (locks), rubber (bands and seams)."""

import math

import kit


def g(x, y, z):
    return (x, -z, y)


def box(name, c, half, tag, segs=8, n=8.0):
    """A box round game point `c` with slightly rounded edges."""
    x, y, z = c
    hx, hy, hz = half
    return kit.loft(name, [(-z - hz, hx, hy, hy, n), (-z + hz, hx, hy, hy, n)], segs, tag, at=(x, 0.0, y))


def along(name, secs, segs, tag, at=(0.0, 0.0, 0.0)):
    """A loft along the game's Z through (z, half width, up, down, n) sections round game `at`."""
    return kit.loft(name, [(-z - at[2], hw, up, dn, n) for z, hw, up, dn, n in secs], segs, tag, at=(at[0], 0.0, at[1]))


def across(name, secs, segs, tag, at=(0.0, 0.0, 0.0)):
    """A loft across the game's X through (x, half depth in Z, up, down, n) sections round game `at`."""
    ob = kit.loft(name, [(x, hz, up, dn, n) for x, hz, up, dn, n in secs], segs, tag)
    # (A loft runs along Blender Y; turned a quarter about Z, its Y becomes Blender -X.)
    ob.rotation_euler = (0.0, 0.0, -math.pi * 0.5)
    ob.location = g(*at)
    return ob


def upright(name, secs, segs, tag, at=(0.0, 0.0, 0.0)):
    """A loft up the game's Y through (y, half width in X, half depth in Z, n) sections round `at`."""
    ob = kit.loft(name, [(y, hw, hd, hd, n) for y, hw, hd, n in secs], segs, tag)
    ob.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    ob.location = g(*at)
    return ob


def sections(rows, segs, tag, name, square=False):
    """A solid through (centre, half width, up, down, n) cross-sections, upright, or (`square`) each
    square to the line through the middles as the code's loft lays them."""
    rings = []
    for i, (c, hw, up, dn, n) in enumerate(rows):
        uy, uz = 1.0, 0.0
        if square:
            a = rows[max(i - 1, 0)][0]
            b = rows[min(i + 1, len(rows) - 1)][0]
            ty, tz = b[1] - a[1], b[2] - a[2]
            ln = math.hypot(ty, tz)
            uy, uz = tz / ln, -ty / ln
        rings.append([g(c[0] + x, c[1] + z * uy, c[2] + z * uz) for x, z in kit.superellipse(hw, up, dn, n, segs)])
    return kit.skin(name, rings, tag)


def capsule_secs(half_len, rad, steps, n=2.0, wide=1.0, up=1.0):
    """(pos, half width, up, down, n) sections of a capsule `half_len` long each way, its ends
    rounded over `rad`."""
    out = []
    for i in range(steps + 1):
        f = -1.0 + 2.0 * i / steps
        p = f * half_len
        over = max(abs(p) - (half_len - rad), 0.0) / rad
        s = math.sqrt(max(1.0 - min(over, 0.97) ** 2, 0.0))
        out.append((p, rad * wide * s, rad * up * s, rad * up * s, n))
    return out


def tank_bag(lod):
    segs = [24, 12, 6][lod]
    n = [8, 4, 1][lod]
    rows = []
    for i in range(n + 1):
        u = i / n
        w = 0.1 * (0.8 + 0.2 * math.sin(u * math.pi))
        h = 0.1 * (0.7 + 0.3 * math.sin(min(u * 1.4, 1.0) * math.pi * 0.5))
        rows.append(((0.0, h * 0.5, u * 0.26), w, h * 0.5, h * 0.5, 2.6))
    parts = [sections(rows, segs, "fabric", "bag")]
    if lod < 2:
        # Piping round the base and the lid's seam round its top, where the zip runs.
        for k, f in ((0, 0.1), (1, 0.72)):
            line = []
            for i in range(n + 1):
                c, w, up, dn, _ = rows[i]
                line.append((c[2], w * (1.0 if k == 0 else 0.93), c[1] - dn + f * 2.0 * dn))
            for side in (-1.0, 1.0):
                parts.append(kit.sweep("piping", [g(side * x * 1.005, y, z) for z, x, y in line], 0.0035, [6, 4][lod], "paint_2"))
        # The lid's panel, a little proud of the bag on top.
        lid = []
        for i in range(1, n):
            c, w, up, dn, _ = rows[i]
            lid.append(((0.0, c[1] + up * 0.55, c[2]), w * 0.8, up * 0.5, 0.004, 2.6))
        parts.append(sections(lid, segs, "paint_2", "lid"))
    return kit.join(parts, "tank_bag")


def fuel_can(lod):
    segs = [16, 8, 4][lod]
    parts = [box("can", (0.0, 0.0, 0.0), (0.0375, 0.13, 0.1), "paint", segs, 7.0 if lod < 2 else 20.0)]
    if lod < 2:
        # The pressed X on its face.
        for s in (-1.0, 1.0):
            a = g(-0.039, -0.11 * s, -0.08)
            b = g(-0.039, 0.11 * s, 0.08)
            parts.append(kit.tube("x", a, b, 0.005, 4, "paint_2"))
        parts.append(box("handle", (0.0, 0.142, -0.03), (0.012, 0.012, 0.05), "paint", 6, 6.0))
        parts.append(kit.tube("spout", g(0.0, 0.13, 0.07), g(0.0, 0.155, 0.085), 0.015, 10 if lod == 0 else 6, "black_metal"))
    if lod == 0:
        parts.append(box("seam", (0.0, 0.0, 0.0), (0.0385, 0.131, 0.0025), "paint", 8, 7.0))
    return kit.join(parts, "fuel_can")


def fuel_cell(lod):
    segs = [20, 10, 6][lod]
    steps = [16, 8, 2][lod]
    parts = [along("cell", capsule_secs(0.295, 0.055, steps), segs, "paint")]
    if lod < 2:
        for z in (-0.2, 0.2):
            parts.append(along("seam", [(z - 0.003, 0.0565, 0.0565, 0.0565, 2.0), (z + 0.003, 0.0565, 0.0565, 0.0565, 2.0)], segs, "paint"))
        parts.append(upright("cap", [(0.05, 0.018, 0.018, 2.0), (0.068, 0.018, 0.018, 2.0)], 12 if lod == 0 else 6, "black_metal", at=(0.0, 0.0, -0.096)))
    return kit.join(parts, "fuel_cell")


def rear_tank(lod):
    segs = [24, 12, 6][lod]
    n = [8, 4, 1][lod]
    secs = []
    for i in range(n + 1):
        u = i / n
        secs.append((-0.17 + 0.32 * u, 0.13 * (0.85 + 0.15 * math.sin(u * math.pi)), 0.07, 0.09 * (0.7 + 0.3 * u), 2.6))
    parts = [along("tank", secs, segs, "paint")]
    if lod < 2:
        parts.append(upright("cap", [(0.066, 0.022, 0.022, 2.0), (0.09, 0.022, 0.022, 2.0)], 14 if lod == 0 else 6, "black_metal", at=(0.09, 0.0, 0.0)))
        # The moulded rib along its top.
        parts.append(along("rib", [(-0.15, 0.06, 0.008, 0.002, 3.0), (0.13, 0.06, 0.008, 0.002, 3.0)], 8, "paint", at=(0.0, 0.066, 0.0)))
    return kit.join(parts, "rear_tank")


def side_tank(lod):
    segs = [20, 10, 6][lod]
    n = [8, 4, 1][lod]
    rows = []
    for i in range(n + 1):
        u = i / n
        rows.append(((0.0, -0.04 + 0.1 * u, -0.1 + 0.22 * u), 0.05 * (0.7 + 0.3 * math.sin(u * math.pi)), 0.12 - 0.04 * u, 0.06 + 0.06 * u, 2.4))
    parts = [sections(rows, segs, "paint", "tank", True)]
    if lod < 2:
        parts.append(upright("cap", [(0.17, 0.018, 0.018, 2.0), (0.19, 0.018, 0.018, 2.0)], 12 if lod == 0 else 6, "black_metal", at=(0.0, 0.0, 0.04)))
    return kit.join(parts, "side_tank")


def bladder(lod):
    segs = [20, 10, 6][lod]
    steps = [14, 6, 2][lod]
    parts = [across("bladder", capsule_secs(0.18, 0.05, steps, 2.0, 1.6), segs, "paint")]
    if lod < 2:
        # The welded seam round its edge, front to back over the top and under.
        parts.append(across("weld", [(-0.15, 0.081, 0.004, 0.004, 2.0), (0.15, 0.081, 0.004, 0.004, 2.0)], 6, "paint"))
        parts.append(upright("cap", [(0.04, 0.016, 0.016, 2.0), (0.062, 0.016, 0.016, 2.0)], 12 if lod == 0 else 6, "black_metal", at=(0.12, 0.0, 0.0)))
    return kit.join(parts, "bladder")


def tool_roll(lod):
    segs = [18, 10, 6][lod]
    parts = [across("roll", [(-0.11, 0.033, 0.033, 0.033, 2.0), (-0.106, 0.035, 0.035, 0.035, 2.0), (0.106, 0.035, 0.035, 0.035, 2.0), (0.11, 0.033, 0.033, 0.033, 2.0)]
        if lod < 2 else [(-0.11, 0.035, 0.035, 0.035, 2.0), (0.11, 0.035, 0.035, 0.035, 2.0)], segs, "leather")]
    if lod < 2:
        for x in (-0.07, 0.07):
            parts.append(across("strap", [(x - 0.0075, 0.037, 0.037, 0.037, 2.0), (x + 0.0075, 0.037, 0.037, 0.037, 2.0)], segs, "paint_2"))
        # The flap's edge lying along the roll.
        parts.append(box("flap", (0.0, 0.026, -0.024), (0.105, 0.002, 0.008), "leather", 4, 6.0))
    if lod == 0:
        for x in (-0.07, 0.07):
            parts.append(box("buckle", (x, 0.0, -0.037), (0.009, 0.007, 0.002), "chrome", 4, 6.0))
    return kit.join(parts, "tool_roll")


def tool_tube(lod):
    segs = [20, 10, 6][lod]
    parts = [along("tube", [(0.0, 0.045, 0.045, 0.045, 2.0), (0.34, 0.045, 0.045, 0.045, 2.0)], segs, "paint")]
    cap = [(0.338, 0.05, 0.05, 0.05, 2.0), (0.37, 0.05, 0.05, 0.05, 2.0)]
    if lod == 0:
        # Knurled: ridges round the cap.
        parts.append(along("cap", [(0.338, 0.048, 0.048, 0.048, 2.0), (0.366, 0.048, 0.048, 0.048, 2.0), (0.37, 0.044, 0.044, 0.044, 2.0)], segs, "black_metal"))
        for k in range(12):
            a = 2.0 * math.pi * k / 12
            parts.append(kit.tube("knurl", g(math.cos(a) * 0.048, math.sin(a) * 0.048, 0.342), g(math.cos(a) * 0.048, math.sin(a) * 0.048, 0.364), 0.0025, 4, "black_metal"))
    else:
        parts.append(along("cap", cap, segs, "black_metal"))
    if lod < 2:
        parts.append(along("lip", [(0.0, 0.047, 0.047, 0.047, 2.0), (0.006, 0.047, 0.047, 0.047, 2.0)], segs, "paint"))
    return kit.join(parts, "tool_tube")


def toolbox(lod):
    segs = [16, 8, 4][lod]
    parts = [box("box", (0.0, 0.0, 0.0), (0.04, 0.06, 0.11), "paint", segs, 8.0 if lod < 2 else 20.0),
        box("lid", (0.0, 0.066, 0.0), (0.044, 0.006, 0.114), "paint", segs, 8.0 if lod < 2 else 20.0)]
    if lod < 2:
        parts.append(box("latch", (-0.044, 0.036, 0.0), (0.004, 0.015, 0.02), "black_metal", 6, 6.0))
        parts.append(kit.tube("lock", g(-0.044, 0.036, 0.0), g(-0.0515, 0.036, 0.0), 0.007, 10 if lod == 0 else 6, "chrome"))
        for z in (-0.06, 0.06):
            parts.append(box("rib", (-0.042, -0.01, z), (0.002, 0.042, 0.005), "paint", 4, 6.0))
    if lod == 0:
        for z in (-0.09, 0.09):
            parts.append(kit.tube("hinge", g(0.04, 0.062, z - 0.012), g(0.04, 0.062, z + 0.012), 0.004, 6, "chrome"))
    return kit.join(parts, "toolbox")


def bash_box(lod):
    segs = [16, 8, 4][lod]
    parts = [box("box", (0.0, 0.0, 0.0), (0.08, 0.03, 0.14), "paint", segs, 8.0 if lod < 2 else 20.0),
        box("plate", (0.0, -0.033, 0.0), (0.1, 0.003, 0.16), "paint", segs, 10.0 if lod < 2 else 20.0)]
    if lod < 2:
        for s in (-1.0, 1.0):
            parts.append(box("clip", (s * 0.083, 0.0, 0.0), (0.003, 0.01, 0.025), "black_metal", 6, 6.0))
    if lod == 0:
        # Drain holes' bosses and the plate's bent-up nose.
        for x in (-0.05, 0.05):
            parts.append(upright("boss", [(-0.037, 0.008, 0.008, 2.0), (-0.035, 0.008, 0.008, 2.0)], 8, "black_metal", at=(x, 0.0, 0.1)))
        nose = box("nose", (0.0, -0.02, -0.165), (0.1, 0.003, 0.016), "paint", 8, 10.0)
        parts.append(nose)
    return kit.join(parts, "bash_box")


def satnav(lod):
    segs = [16, 8, 4][lod]
    # Its face looks up +Y: a slab 122 by 87 mm and 26 mm thick, made as a box along Z.
    parts = [box("housing", (0.0, 0.0, 0.0), (0.061, 0.013, 0.0435), "paint", segs, 6.0 if lod < 2 else 20.0)]
    if lod < 2:
        # The bezel round the screen, standing just proud of the face.
        cs = [4, 2][lod]
        ring = [g(x, 0.0128, z) for x, z in kit.rounded_rect(0.054, 0.037, 0.006, cs)]
        parts.append(kit.sweep("bezel", ring + ring[:2], 0.0022, [6, 4][lod], "black_metal"))
        for k in range(3 if lod == 0 else 1):
            parts.append(box("button", (0.0625, 0.004, -0.02 + 0.02 * k), (0.002, 0.004, 0.006), "black_metal", 4, 6.0))
    if lod == 0:
        # The mount's ball socket on the back.
        parts.append(upright("socket", [(-0.022, 0.012, 0.012, 2.0), (-0.012, 0.016, 0.016, 2.0)], 10, "black_metal"))
    return kit.join(parts, "satnav")


def phone(lod):
    cs = [5, 2, 1][lod]
    body = kit.prism("phone", kit.rounded_rect(0.068, 0.0435, 0.009, cs), -0.0045, 0.0045, "black_metal")
    body.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
    parts = [body]
    if lod < 2:
        bump = kit.prism("camera", kit.rounded_rect(0.011, 0.011, 0.004, cs), -0.0075, -0.0045, "black_metal", at=(0.0374, 0.0196, 0.0))
        bump.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
        parts.append(bump)
    if lod == 0:
        for x in (0.032, 0.043):
            lens = kit.prism("lens", kit.rounded_rect(0.0035, 0.0035, 0.0034, 3), -0.0081, -0.0074, "glass", at=(x, 0.0236, 0.0))
            lens.rotation_euler = (math.pi * 0.5, 0.0, 0.0)
            parts.append(lens)
    return kit.join(parts, "phone")


def parts():
    return [{"kind": "kit", "path": "kit/%s.glb" % name, "build": build, "mounts": {}}
        for name, build in (("tank_bag", tank_bag), ("fuel_can", fuel_can), ("fuel_cell", fuel_cell), ("rear_tank", rear_tank),
            ("side_tank", side_tank), ("bladder", bladder), ("tool_roll", tool_roll), ("tool_tube", tool_tube),
            ("toolbox", toolbox), ("bash_box", bash_box), ("satnav", satnav), ("phone", phone))]
