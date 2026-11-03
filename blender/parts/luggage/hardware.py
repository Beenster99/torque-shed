"""The small hardware on the luggage's straps, each drawn in a unit box (-0.5 to 0.5 on every
axis) with its face up (+Y) and along Z: BikeModel._hardware stretches it to the box the code
drew there and turns its face out of that box's thinnest side.

- "luggage/buckle.glb": a side-release buckle, the female socket at the back with its two
  release tabs and the male tongue pushed in from the front, the strap's slot through it.
- "luggage/brass_buckle.glb": a trunk strap's brass buckle: its frame, the bar and the prong.
- "luggage/brass_corner.glb": a trunk's brass corner cap, its edges rolled and its rivets.
- "luggage/strap_hook.glb": a cargo strap's hook round the rack rail.

Axes are the game's (x out, y up, z back) as Blender's (x, -z, y). Tags: buckles `plastic`, the
trunk's fittings `polished_alloy`, the hook `raw_steel`."""

import kit

DETAIL = [{"corner": 3, "round": 10}, {"corner": 1, "round": 6}, {"corner": 1, "round": 4}]


def g(x, y, z):
    return (x, -z, y)


def box(name, c, half, tag, r=0.05, segs=2, bevel=0.0):
    """A box round point `c`, rounded seen from above (along Y)."""
    x, y, z = c
    hx, hy, hz = half
    return kit.prism(name, kit.rounded_rect(hx, hz, r, segs), y - hy, y + hy, tag, bevel, at=(x, -z, 0.0))


def buckle(lod):
    d = DETAIL[lod]
    parts = [box("socket", (0.0, 0.0, 0.18), (0.5, 0.5, 0.32), "plastic", 0.18, d["corner"]),
        box("tongue", (0.0, 0.0, -0.3), (0.42, 0.32, 0.2), "plastic", 0.12, d["corner"])]
    if lod < 2:
        # The release tabs either side of the socket, and the strap bar across the tongue's front.
        for s in (-1.0, 1.0):
            parts.append(box("tab", (s * 0.46, 0.0, -0.02), (0.06, 0.4, 0.1), "plastic", 0.03, 1))
        parts.append(box("bar", (0.0, 0.0, -0.46), (0.36, 0.2, 0.04), "plastic", 0.02, 1))
    if lod == 0:
        parts.append(box("ridge", (0.0, 0.47, 0.18), (0.3, 0.03, 0.2), "plastic", 0.08, 1))
    return kit.join(parts, "buckle")


def brass_buckle(lod):
    d = DETAIL[lod]
    parts = []
    for s in (-1.0, 1.0):
        parts.append(box("side", (s * 0.42, 0.0, 0.0), (0.08, 0.5, 0.5), "polished_alloy", 0.04, d["corner"]))
        parts.append(box("end", (0.0, 0.0, s * 0.42), (0.5, 0.5, 0.08), "polished_alloy", 0.04, d["corner"]))
    parts.append(box("bar", (0.0, 0.0, 0.0), (0.42, 0.35, 0.05), "polished_alloy", 0.02, 1))
    if lod < 2:
        parts.append(box("prong", (0.0, 0.1, -0.2), (0.05, 0.3, 0.22), "polished_alloy", 0.02, 1))
    return kit.join(parts, "brass_buckle")


def brass_corner(lod):
    d = DETAIL[lod]
    parts = [box("cap", (0.0, 0.0, 0.0), (0.5, 0.5, 0.5), "polished_alloy", 0.2, d["corner"], 0.06 if lod == 0 else 0.0)]
    if lod < 2:
        for x, z in ((0.25, 0.51), (-0.25, 0.51), (0.51, 0.25), (0.51, -0.25)):
            parts.append(kit.sphere("rivet", g(x, 0.1, z), 0.08, (1.0, 1.0, 1.0), d["round"], "polished_alloy"))
    return kit.join(parts, "brass_corner")


def strap_hook(lod):
    d = DETAIL[lod]
    pts = [g(0.0, 0.5, 0.0), g(0.0, -0.2, 0.0), g(0.0, -0.45, 0.25), g(0.0, -0.3, 0.45), g(0.0, -0.05, 0.4)]
    parts = [kit.sweep("hook", pts, 0.12, d["round"], "raw_steel"),
        box("eye", (0.0, 0.42, 0.0), (0.45, 0.08, 0.2), "raw_steel", 0.08, 1)]
    return kit.join(parts, "strap_hook")


def parts():
    return [{"kind": "luggage", "path": "luggage/%s.glb" % name, "build": build, "mounts": {}}
        for name, build in (("buckle", buckle), ("brass_buckle", brass_buckle), ("brass_corner", brass_corner), ("strap_hook", strap_hook))]
