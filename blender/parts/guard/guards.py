"""The mudguards' cross-sections, which the game bends round each guard it lays out (front and rear,
the plates round the wheel, the flat blades of a high MX guard and their rounded tips: see
BlenderParts.section_along), so the guard keeps its own layout, clearances and number plate checks
while it's drawn as a real pressed guard rather than flat plates.

A section runs 1 unit back along -Y (the game maps that onto the stretch of guard it draws), across
X from -0.5 to 0.5 (the game scales that to the guard's width) and up Z in metres from the guard's
middle line: "steel", a crowned steel guard with its edges rolled under; "valanced", a classic's,
its sides carried down deep over the tyre; "plastic", an MX guard's, flatter and thicker with a
stiffening rib down the middle. Each comes as `<name>.glb`, three rings along for a plate's short
stretch of arc, and `<name>_tip.glb`, more of them for a rounded end the game narrows to a point.
All `paint`: the game gives them the guard's own finish."""

import math

import kit

THICK = 0.003             # m: the steel
DETAIL = {"plain": 3, "tip": 6}


def g(x, y, z):
    """A point in the section's Godot space (x across, y up, z along) as Blender's."""
    return (x, -z, y)


def profile(kind):
    """The section's outline round its skin (x across, y up), anticlockwise from the left edge's
    rolled lip: over the top, round the right lip and back under."""
    n = 10
    if kind == "plastic":
        crown, drop, t = 0.008, 0.012, 0.005
    elif kind == "valanced":
        crown, drop, t = 0.012, 0.06, THICK
    else:
        crown, drop, t = 0.012, 0.022, THICK
    top = []
    for i in range(n + 1):
        x = -0.5 + i / n
        u = abs(2.0 * x)
        # Crowned over the tyre, falling away faster towards the edges (a valance hangs straight down).
        y = crown * (1.0 - u * u) - drop * (u ** (6.0 if kind == "valanced" else 3.0))
        if kind == "plastic" and abs(x) < 0.06:
            y += 0.006 * (1.0 - abs(x) / 0.06)
        top.append((x, y))
    under = [(x, y - t) for x, y in reversed(top)]
    # The rolled lips: a small bead under each edge.
    lip = 0.004 if kind != "plastic" else 0.0
    right = [(0.5 + lip * 0.4, top[-1][1] - t * 0.5 - lip * 0.6)] if lip else []
    left = [(-0.5 - lip * 0.4, top[0][1] - t * 0.5 - lip * 0.6)] if lip else []
    return top + right + under + left


def section(kind, rings):
    def make(lod):
        prof = profile(kind)
        ob = kit.skin("guard", [[g(x, y, i / (rings - 1)) for x, y in prof] for i in range(rings)], "paint")
        return kit.join([ob], "guard")
    return make


def parts():
    out = []
    for kind in ("steel", "valanced", "plastic"):
        for suffix, rings in (("", DETAIL["plain"]), ("_tip", DETAIL["tip"])):
            out.append({"kind": "guard", "path": "guard/%s%s.glb" % (kind, suffix), "build": section(kind, rings), "mounts": {}})
    return out
