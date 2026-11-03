"""A drum brake's moving parts, which BikeModel._draw_drum draws in the caliper and pad slots
(the drum and its backplate are discs.py's):

- "caliper/drum_arm.glb": the brake arm on its cam, its origin on the cam's axis and the arm up
  +Y from it, 0.076 m to the clevis pin the cable or rod hooks on: the splined boss pinched by
  its bolt, the forged arm tapering out to its eye, and the pin across it. The game turns +Y to
  the arm's tip and +X out from the hub.
- "pads/drum_shoe.glb": one brake shoe, drawn for a drum 0.1 m round (the game scales it to the
  drum's own size): the steel web's arc round the top of the hub, its lining bonded on the outside
  and the rivets through it, its origin on the hub's axis. The game turns it upside down for the
  lower shoe.

Axes are the game's (x out, y up, z back) as Blender's (x, -z, y). Tags: the arm `paint`, the
pin and bolts `raw_steel`; the shoe's lining `paint`, its web `raw_steel`."""

import math

import kit

DETAIL = [{"round": 14, "arc": 12}, {"round": 8, "arc": 6}, {"round": 6, "arc": 3}]
ARM = 0.076
SHOE_R = 0.1


def g(x, y, z):
    return (x, -z, y)


def yz_plate(name, pts, x0, x1, tag):
    """A plate through the outline `pts` of game (y, z) points, from x0 to x1 across."""
    return kit.prism(name, [(-z, y) for y, z in pts], x0, x1, tag, plane="YZ")


def arm(lod):
    d = DETAIL[lod]
    parts = [kit.tube("boss", g(-0.008, 0.0, 0.0), g(0.008, 0.0, 0.0), 0.012, d["round"], "paint")]
    # The blade: wide at the boss, narrowing to its eye, a little thinner than the boss.
    blade = [(0.0, -0.009), (ARM, -0.0055), (ARM, 0.0055), (0.0, 0.009)]
    parts.append(yz_plate("blade", blade, -0.004, 0.004, "paint"))
    parts.append(kit.tube("eye", g(-0.004, ARM, 0.0), g(0.004, ARM, 0.0), 0.0075, d["round"], "paint"))
    parts.append(kit.tube("pin", g(-0.008, ARM, 0.0), g(0.008, ARM, 0.0), 0.003, max(6, d["round"] // 2), "raw_steel"))
    if lod < 2:
        # The pinch bolt across the split boss, and the cam's end and its splines.
        parts.append(kit.tube("pinch", g(0.0, 0.013, -0.012), g(0.0, 0.013, 0.012), 0.003, 6, "raw_steel"))
        parts.append(kit.tube("cam", g(0.008, 0.0, 0.0), g(0.011, 0.0, 0.0), 0.0075, d["round"], "raw_steel"))
    if lod == 0:
        parts.append(kit.hex_nut("nut", g(0.0, 0.013, 0.012), (0.0, -1.0, 0.0), 0.0045, 0.003))
        for k in range(8):
            a = 2.0 * math.pi * k / 8
            parts.append(kit.tube("spline", g(0.008, math.cos(a) * 0.0075, math.sin(a) * 0.0075), g(0.011, math.cos(a) * 0.0075, math.sin(a) * 0.0075), 0.0012, 4, "raw_steel"))
    return kit.join(parts, "drum_arm")


def arc(r0, r1, half, n):
    """An arc band round the top of the hub, from r0 out to r1, `half` radians either side."""
    outer = [(math.cos(-half + 2.0 * half * k / n) * r1, math.sin(-half + 2.0 * half * k / n) * r1) for k in range(n + 1)]
    inner = [(math.cos(-half + 2.0 * half * k / n) * r0, math.sin(-half + 2.0 * half * k / n) * r0) for k in range(n + 1)]
    return outer + inner[::-1]


def shoe(lod):
    d = DETAIL[lod]
    half = math.radians(42.0)
    parts = [yz_plate("web", arc(0.05, 0.058, half, d["arc"]), -0.01, 0.01, "raw_steel"),
        yz_plate("lining", arc(0.058, 0.068, half * 0.95, d["arc"]), -0.0125, 0.0125, "paint")]
    if lod < 2:
        # The web's rib down the middle, inside the arc, and its pivot and cam ends.
        parts.append(yz_plate("rib", arc(0.043, 0.05, half * 0.9, d["arc"]), -0.002, 0.002, "raw_steel"))
        for s in (-1.0, 1.0):
            a = half * 0.95 * s
            parts.append(kit.tube("end", g(-0.01, math.cos(a) * 0.05, math.sin(a) * 0.05), g(0.01, math.cos(a) * 0.05, math.sin(a) * 0.05), 0.006, d["round"], "raw_steel"))
    if lod == 0:
        for k in range(5):
            a = -half * 0.75 + half * 1.5 * k / 4
            for x in (-0.007, 0.007):
                parts.append(kit.tube("rivet", g(x, math.cos(a) * 0.0675, math.sin(a) * 0.0675), g(x, math.cos(a) * 0.0685, math.sin(a) * 0.0685), 0.0018, 5, "raw_steel"))
    return kit.join(parts, "drum_shoe")


def parts():
    return [
        {"kind": "caliper", "path": "caliper/drum_arm.glb", "build": arm, "mounts": {}},
        {"kind": "pads", "path": "pads/drum_shoe.glb", "build": shoe, "mounts": {}},
    ]
