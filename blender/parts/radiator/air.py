"""The cooling BikeModel._draw_cooling bolts on that isn't a front radiator (radiators.py):

- "radiator/fins.glb": the extra cooling fins on an air-cooled barrel, five fins 0.14 m across
  and 0.15 m along stacked up the barrel 35 mm apart, round the cylinder's base (the game turns
  +Y up the cylinder): each fin rounded at its corners and thinning to its edge, with the cast
  ribs that tie them together front and back.
- "radiator/side.glb": the right-hand one of a pair of side radiators (an MX bike's), its origin
  in the middle of its core: the core, its top and bottom tanks, the filler cap and hose stubs,
  and the louvred shroud on its outside. The game turns it out to the front and mirrors it for
  the left.

Axes are the game's (x out, y up, z back) as Blender's (x, -z, y). Tags: `paint` (the part's
finish), the core `black_metal` (the game puts its fin texture on it), hoses `rubber`."""

import kit

DETAIL = [{"round": 12, "corner": 3}, {"round": 8, "corner": 1}, {"round": 6, "corner": 0}]


def g(x, y, z):
    return (x, -z, y)


def box(name, c, half, tag, r=0.004, segs=2, bevel=0.0):
    """A box round game point `c`, rounded seen from above."""
    x, y, z = c
    hx, hy, hz = half
    outline = [(-hx, -hz), (hx, -hz), (hx, hz), (-hx, hz)] if segs == 0 else kit.rounded_rect(hx, hz, r, segs)
    return kit.prism(name, outline, y - hy, y + hy, tag, bevel, at=(x, -z, 0.0))


def box_x(name, c, half, tag, r=0.004, segs=2):
    """A box round game point `c`, rounded seen from the side."""
    x, y, z = c
    hx, hy, hz = half
    outline = [(-hy, -hz), (hy, -hz), (hy, hz), (-hy, hz)] if segs == 0 else kit.rounded_rect(hy, hz, r, segs)
    return kit.prism(name, [(-(b + z), a + y) for a, b in outline], x - hx, x + hx, tag, plane="YZ")


def fins(lod):
    d = DETAIL[lod]
    parts = []
    for i in range(5):
        y = -0.07 + i * 0.035
        parts.append(box("fin", (0.0, y, 0.0), (0.07, 0.005, 0.075), "paint", 0.018, d["corner"], 0.002 if lod == 0 else 0.0))
    if lod < 2:
        # Cast ribs up the front and back, tying the fins together.
        for z in (-0.068, 0.068):
            parts.append(box("rib", (0.0, 0.0, z), (0.004, 0.075, 0.004), "paint", 0.0015, 1))
    return kit.join(parts, "fins")


def side(lod):
    d = DETAIL[lod]
    parts = [box_x("core", (0.0, 0.0, 0.0), (0.025, 0.14, 0.11), "black_metal", 0.004, 1)]
    for s in (-1.0, 1.0):
        parts.append(box_x("tank", (0.0, s * 0.145, 0.0), (0.027, 0.012, 0.115), "paint", 0.008, d["corner"]))
    # The shroud on the outside, its louvres slotted across it.
    parts.append(box_x("shroud", (0.03, 0.0, 0.0), (0.005, 0.15, 0.12), "paint", 0.03, d["corner"]))
    if lod < 2:
        for k in range(6):
            y = -0.1 + 0.04 * k
            parts.append(box_x("louvre", (0.036, y, 0.01), (0.002, 0.006, 0.08), "black_metal", 0.003, 1))
        parts.append(kit.tube("cap", g(0.0, 0.157, -0.07), g(0.0, 0.168, -0.07), 0.013, d["round"], "paint"))
        parts.append(kit.tube("hose", g(-0.01, -0.15, 0.06), g(-0.04, -0.15, 0.08), 0.012, d["round"], "rubber"))
        parts.append(kit.tube("hose", g(-0.01, 0.15, 0.06), g(-0.04, 0.15, 0.08), 0.011, d["round"], "rubber"))
    if lod == 0:
        for y in (-0.12, 0.12):
            parts.append(kit.hex_nut("bolt", g(0.035, y, -0.1), (1.0, 0.0, 0.0), 0.004, 0.003))
            parts.append(kit.hex_nut("bolt", g(0.035, y, 0.1), (1.0, 0.0, 0.0), 0.004, 0.003))
    return kit.join(parts, "side")


def parts():
    return [
        {"kind": "radiator", "path": "radiator/fins.glb", "build": fins, "mounts": {}},
        {"kind": "radiator", "path": "radiator/side.glb", "build": side, "mounts": {}},
    ]
