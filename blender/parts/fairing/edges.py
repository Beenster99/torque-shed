"""The fairings' edges and thickness. A fairing is laid out by the game round the bike it's on (its
nose round the headlight, its flanks round the engine, its lower edge cut round the front wheel), so
it can't be one fixed mesh: the game keeps that layout and gives the shell a real thickness, with the
edge section here run round every open edge of it (BlenderParts.shell), the way a moulded panel's
edge rolls round from its outer face to its inner one rather than stopping as a paper-thin cut.

A section runs 1 unit back along -Y (the game maps that onto one stretch of the edge), out from
the edge along X in metres and down Z in metres from the outer face (the game turns that along the
shell's normal), from the outer face's edge (0, 0) round the bead to the inner face's (0, -thick):
"moulded", a road fairing's ABS or glass fibre; "carbon", thinner and crisper; "screen", a thicker
acrylic screen with a polished round edge. The game takes the shell's thickness from the section."""

import math

import kit

KINDS = {
    # thickness (m), how far the edge stands out past the cut (m), squareness, tag
    "moulded": (0.003, 0.0018, 2.0, "paint"),
    "carbon": (0.002, 0.0009, 3.0, "carbon"),
    "screen": (0.004, 0.0021, 2.0, "glass"),
}
POINTS = [9, 5, 3]


def g(x, y, z):
    """A point in the section's Godot space (x out, y up the normal, z along) as Blender's."""
    return (x, -z, y)


def profile(kind, lod):
    """Round the edge from the outer face to the inner one, then (closing the ring) straight back up
    the cut, which lies inside the shell."""
    thick, out, n, _ = KINDS[kind]
    e = 2.0 / n
    pts = []
    count = POINTS[lod]
    for i in range(count):
        a = math.pi * 0.5 - math.pi * i / (count - 1)
        ca, sa = math.cos(a), math.sin(a)
        x = abs(ca) ** e * out
        y = -thick * 0.5 + math.copysign(abs(sa) ** e, sa) * thick * 0.5
        pts.append((x, y))
    return pts


def section(kind):
    def make(lod):
        prof = profile(kind, lod)
        ob = kit.skin("edge", [[g(x, y, z) for x, y in prof] for z in (0.0, 1.0)], KINDS[kind][3], caps=False)
        return kit.join([ob], "edge")
    return make


def parts():
    return [{"kind": "fairing_edge", "path": "fairing/edge/%s.glb" % kind, "build": section(kind), "mounts": {}} for kind in KINDS]
