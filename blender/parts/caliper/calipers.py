"""The brake calipers and their pads, one glb for each in the catalogue, as BikeModel's _draw_brake
lays them out (agreement 6b): the caliper body a rounded block the size of BikeModel's box (its
pistons making it bigger), a piston cap for each pair of pistons on its outer face, the bleed
nipple on top and the two mounting bolts; a pad is its friction block on a steel backing plate.
Both have their origin at their middle, in the axes BikeModel turns its boxes by (Godot's x across,
y up the caliper, z along it), and stay still with the hub: they don't turn with the wheel."""

import json
import os

import kit

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOGUE = os.path.join(HERE, "..", "..", "..", "data", "parts.json")

DETAIL = [{"round": 16, "corner": 3, "bevel": 0.002}, {"round": 8, "corner": 1, "bevel": 0.0}, {"round": 6, "corner": 0, "bevel": 0.0}]

# The calipers drawn in an anodised finish rather than painted.
ANODISED = ("four_piston_radial", "six_piston_race")


def catalogue(kind):
    with open(CATALOGUE) as f:
        return json.load(f)[kind]


def g(x, y, z):
    """A point in Godot's axes (x across, y up, z back) as Blender's."""
    return (x, -z, y)


def caliper(part_id, lod):
    p = catalogue("caliper")[part_id]
    d = DETAIL[lod]
    pistons = int(p.get("pistons", 2))
    sx, sy, sz = 0.045, 0.06 + 0.008 * pistons, 0.07 + 0.01 * pistons
    tag = "anodised" if part_id in ANODISED else "paint"
    # The body: a block rounded at its corners, seen side on, its edges softened.
    outline = kit.rounded_rect(sz * 0.5, sy * 0.5, 0.012, max(1, d["corner"]))
    parts = [kit.prism("body", outline, -sx * 0.5, sx * 0.5, tag, d["bevel"], 1, plane="YZ")]
    if lod < 2:
        # A piston cap on the outer face for each pair of pistons, spread along it.
        caps = max(1, pistons // 2)
        for k in range(caps):
            z = (k - (caps - 1) * 0.5) * sz / (caps + 0.4)
            parts.append(kit.tube("piston", g(sx * 0.5 - 0.002, 0.0, z), g(sx * 0.5 + 0.004, 0.0, z), min(0.016, sz / (caps * 2.6)), d["round"], tag))
        # The bleed nipple on top and the two mounting bolts on the outside.
        parts.append(kit.hex_nut("bleed", g(0.012, sy * 0.5, 0.0), (0.0, 0.0, 1.0), 0.005, 0.012))
        for k in (-1.0, 1.0):
            parts.append(kit.hex_nut("bolt", g(sx * 0.5, 0.0, sz * 0.35 * k), (1.0, 0.0, 0.0), 0.008, 0.012))
    return kit.join(parts, "caliper")


def pads(part_id, lod):
    d = DETAIL[lod]
    outline = kit.rounded_rect(0.0175, 0.025, 0.006, max(1, d["corner"]))
    parts = [kit.prism("friction", outline, -0.012, 0.004, "paint")]
    if lod < 2:
        parts.append(kit.prism("backing", outline, 0.004, 0.012, "raw_steel"))
    return kit.join(parts, "pads")


def parts():
    out = []
    for part_id in catalogue("caliper"):
        out.append({"kind": "caliper", "path": "caliper/%s.glb" % part_id, "build": lambda lod, i=part_id: caliper(i, lod), "mounts": {}})
    for part_id in catalogue("pads"):
        out.append({"kind": "pads", "path": "pads/%s.glb" % part_id, "build": lambda lod, i=part_id: pads(i, lod), "mounts": {}})
    return out
