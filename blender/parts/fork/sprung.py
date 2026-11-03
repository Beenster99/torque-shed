"""The old-school front ends, two glbs for each in the catalogue, as BikeModel's _draw_fork lays them
out at the fork's own length (agreement 6b, like forks.py): fork/<id>_upper.glb, what turns with the
bars and stays put as the wheel rises (the legs, the yokes and links, the springs and dampers), its
origin on the head; and fork/<id>_lower.glb, what moves with the wheel (a springer's rockers, a
leading-link or Earles fork's swinging links, the axle and its nuts), its origin on the axle at
mount_axle. Both run along the steering axis, up +Z here (but for a leading-link fork's lower one,
which is level, as BikeModel lays its links out on the hub).

- Girder: each side a riveted truss of a front and a rear blade with zig-zag webs between them,
  on short links top and bottom that pivot on the head's brackets, the main spring in the middle
  between the links, and the friction damper's star knob.
- Springer: fixed rear legs from the crown to the rockers at the axle, slim front legs riding on
  the rockers, and the springs out in the open up top on their perches, each side.
- Leading link (and Earles): fixed legs bent down past the wheel to the pivot behind the axle,
  a coil-over spring and damper each side, a brace across the pivots, and the links to the axle
  (an Earles fork's long arms reaching from a pivot behind the tyre).

Tags: the legs `paint` (the part's colour), springs `chrome`, yokes and links `black_metal`,
bushes and dampers' bodies `cast_alloy`, bolts and nuts `raw_steel`."""

import json
import math
import os

import kit

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOGUE = os.path.join(HERE, "..", "..", "..", "data", "parts.json")
STYLES = ("girder", "springer", "leading_link")

DETAIL = [{"round": 14, "small": 8, "coil": 10, "per_turn": 12},
    {"round": 8, "small": 6, "coil": 6, "per_turn": 8},
    {"round": 4, "small": 3, "coil": 4, "per_turn": 5}]


def catalogue():
    with open(CATALOGUE) as f:
        return {k: p for k, p in json.load(f)["fork"].items() if p.get("style") in STYLES}


def g(x, s, z):
    """A point x across, s up the steering axis and z back, as Blender's."""
    return (x, -z, s)


def rod(name, a, b, r, segs, tag, r_end=None):
    """A tube between two (x, s, z) points."""
    return kit.tube(name, g(*a), g(*b), r, segs, tag, r_end=r_end)


def helix(name, x, z, s0, s1, coil_r, wire, turns, d, tag="chrome"):
    """A coil spring up the axis at (x, z), from s0 to s1 (far off, a plain tube its size)."""
    if d["per_turn"] < 6:
        return rod(name, (x, s0, z), (x, s1, z), coil_r + wire, d["round"], tag)
    n = max(int(turns * d["per_turn"]), 6)
    pts = []
    for i in range(n + 1):
        t = i / n
        a = 2.0 * math.pi * turns * t
        pts.append(g(x + math.cos(a) * coil_r, s0 + (s1 - s0) * t, z + math.sin(a) * coil_r))
    return kit.sweep(name, pts, wire, d["coil"], tag)


def boss(name, x0, x1, s, z, r, segs, tag):
    """A short round boss across the bike (a pivot or a bush) at (s, z)."""
    return rod(name, (x0, s, z), (x1, s, z), r, segs, tag)


def plate(name, x, pts, thick, tag):
    """A flat plate (a link, a rocker) in the plane across at x, through the outline `pts` of (s, z)
    points, `thick` across."""
    outline = [(-z, s) for s, z in pts]
    return kit.prism(name, outline, x - thick * 0.5, x + thick * 0.5, tag, plane="YZ")


def link_outline(a, b, r, segs=6):
    """The outline of a dog-bone link between (s, z) points a and b, round ends of radius r."""
    (sa, za), (sb, zb) = a, b
    ang = math.atan2(zb - za, sb - sa)
    pts = []
    for k in range(segs + 1):
        t = ang + math.pi * 0.5 + math.pi * k / segs
        pts.append((sa + math.cos(t) * r, za + math.sin(t) * r))
    for k in range(segs + 1):
        t = ang - math.pi * 0.5 + math.pi * k / segs
        pts.append((sb + math.cos(t) * r, zb + math.sin(t) * r))
    return pts


def yokes(parts, d, lod, width=0.24, deep=0.04):
    """The top and bottom yokes, round the steering stem (BikeModel's at 0 and -0.16)."""
    outline = kit.rounded_rect(width * 0.5, deep, 0.02, 2 if lod < 2 else 1)
    for s in (0.0, -0.16):
        parts.append(kit.prism("yoke", outline, s - 0.02, s + 0.02, "black_metal", 0.002 if lod == 0 else 0.0, 1))


def axle(parts, d, lod, half):
    """The axle across between the legs, and its nuts outside them."""
    parts.append(boss("axle", -half - 0.012, half + 0.012, 0.0, 0.0, 0.009, d["small"], "raw_steel"))
    if lod < 2:
        for side in (-1.0, 1.0):
            parts.append(kit.hex_nut("axle_nut", g(side * (half + 0.012), 0.0, 0.0), (side, 0.0, 0.0), 0.014, 0.01))


# ------------------------------------------------------------------------------------- girder

def girder_upper(p, lod):
    d = DETAIL[lod]
    fl = float(p["length"])
    parts = []
    x0 = 0.09
    for side in (-1.0, 1.0):
        x = x0 * side
        # The two blades, closer together towards the axle, and the webs between them.
        front = [(0.02, -0.05), (-fl, -0.022)]
        back = [(0.02, 0.012), (-fl + 0.03, 0.0)]
        parts.append(rod("blade", (x, *front[0]), (x, *front[1]), 0.011, d["round"], "paint", r_end=0.009))
        parts.append(rod("blade", (x, *back[0]), (x, *back[1]), 0.011, d["round"], "paint", r_end=0.009))
        webs = 6 if lod == 0 else (4 if lod == 1 else 0)
        for i in range(webs):
            t0, t1 = i / webs, (i + 1) / webs
            fa = (front[0][0] + (front[1][0] - front[0][0]) * t0, front[0][1] + (front[1][1] - front[0][1]) * t0)
            bb = (back[0][0] + (back[1][0] - back[0][0]) * t1, back[0][1] + (back[1][1] - back[0][1]) * t1)
            if i % 2:
                fa = (front[0][0] + (front[1][0] - front[0][0]) * t1, front[0][1] + (front[1][1] - front[0][1]) * t1)
                bb = (back[0][0] + (back[1][0] - back[0][0]) * t0, back[0][1] + (back[1][1] - back[0][1]) * t0)
            parts.append(rod("web", (x, *fa), (x, *bb), 0.006, d["small"], "paint"))
        # The middle bracket (where BikeModel draws its box) and the fork end round the axle.
        parts.append(plate("bracket", x, link_outline((-fl * 0.5 + 0.05, -0.04), (-fl * 0.5 - 0.05, -0.03), 0.02, 3 if lod < 2 else 1), 0.022, "paint"))
        parts.append(plate("end", x, link_outline((-fl + 0.03, -0.018), (-fl - 0.012, -0.02), 0.022, 4 if lod < 2 else 2), 0.012, "paint"))
        # The links' pivots at the top of each blade.
        if lod < 2:
            for s, z in ((0.0, -0.05), (-0.16, -0.045)):
                parts.append(boss("pivot", x - 0.014, x + 0.014, s, z, 0.012, d["small"], "cast_alloy"))
    # The links across the top and bottom, from the head's brackets out to the blades, in place of yokes.
    for s in (0.0, -0.16):
        outline = kit.rounded_rect(0.12, 0.035, 0.016, 2 if lod < 2 else 1)
        parts.append(kit.prism("link", outline, s - 0.012, s + 0.012, "black_metal", 0.002 if lod == 0 else 0.0, 1, at=(0.0, 0.015, 0.0)))
    # The main spring in the middle, between the links, and the damper's star knob on the left.
    parts.append(helix("spring", 0.0, -0.065, -0.01, -0.17, 0.022, 0.0045, 6, d))
    if lod < 2:
        for s in (-0.01, -0.17):
            parts.append(rod("perch", (0.0, s - 0.004, -0.065), (0.0, s + 0.004, -0.065), 0.027, d["round"], "cast_alloy"))
        star = [(math.cos(2.0 * math.pi * k / 10) * (0.03 if k % 2 == 0 else 0.018), math.sin(2.0 * math.pi * k / 10) * (0.03 if k % 2 == 0 else 0.018)) for k in range(10)]
        parts.append(plate("damper_knob", -x0 - 0.03, [(-0.16 + v, -0.045 + u) for u, v in star], 0.01, "black_metal"))
        parts.append(boss("damper_disc", -x0 - 0.025, -x0 - 0.012, -0.16, -0.045, 0.034, d["round"], "cast_alloy"))
    return kit.join(parts, "fork_upper")


def girder_lower(p, lod):
    d = DETAIL[lod]
    parts = []
    axle(parts, d, lod, 0.09)
    return kit.join(parts, "fork_lower")


# ----------------------------------------------------------------------------------- springer

def springer_upper(p, lod):
    d = DETAIL[lod]
    fl = float(p["length"])
    parts = []
    for side in (-1.0, 1.0):
        x = 0.085 * side
        # The rear leg, fixed, tapering to the rocker's pivot behind the axle, and the front leg
        # riding on the rocker's front, its top under the spring.
        parts.append(kit.sweep("rear_leg", [g(x, 0.01, 0.02), g(x, -fl * 0.5, 0.026), g(x, -fl * 0.97, 0.02)], [0.015, 0.0135, 0.011], d["round"], "paint"))
        parts.append(kit.sweep("front_leg", [g(x, -0.2, -0.06), g(x, -fl * 0.55, -0.064), g(x, -fl * 0.92, -0.062)], [0.0125, 0.0115, 0.01], d["round"], "paint"))
        if lod < 2:
            # The leg's eyes where it meets the rockers.
            parts.append(boss("eye", x - 0.012, x + 0.012, -fl * 0.97, 0.02, 0.014, d["small"], "paint"))
            parts.append(boss("eye", x - 0.011, x + 0.011, -fl * 0.92, -0.062, 0.012, d["small"], "paint"))
        # The spring up top, between its perch on the crown and the front leg's top.
        parts.append(helix("spring", x, -0.06, -0.035, -0.2, 0.018, 0.0042, 7, d))
        if lod < 2:
            parts.append(rod("guide", (x, -0.03, -0.06), (x, -0.205, -0.06), 0.006, d["small"], "raw_steel"))
            for s in (-0.035, -0.2):
                parts.append(rod("perch", (x, s - 0.004, -0.06), (x, s + 0.004, -0.06), 0.022, d["round"], "chrome"))
    # The crown across the top: the yokes with the spring's bar out front.
    yokes(parts, d, lod, deep=0.026)
    parts.append(kit.prism("spring_bar", kit.rounded_rect(0.105, 0.016, 0.008, 2 if lod < 2 else 1), -0.035, -0.025, "black_metal", at=(0.0, 0.06, 0.0)))
    return kit.join(parts, "fork_upper")


def springer_lower(p, lod):
    d = DETAIL[lod]
    fl = float(p["length"])
    parts = []
    for side in (-1.0, 1.0):
        x = 0.085 * side
        # The rocker: from the rear leg's eye behind the axle, round the axle, to the front leg's.
        rear = (fl * 0.03, 0.02)
        front = (fl * 0.08, -0.062)
        parts.append(plate("rocker", x + side * 0.013, link_outline(rear, (0.0, -0.01), 0.017, 4 if lod < 2 else 2), 0.008, "black_metal"))
        parts.append(plate("rocker", x + side * 0.013, link_outline((0.0, -0.01), front, 0.015, 4 if lod < 2 else 2), 0.008, "black_metal"))
        # Its nose, forward of the axle (BikeModel's rocker reaches 7 cm ahead of it, level).
        parts.append(plate("rocker", x + side * 0.013, link_outline((0.0, -0.01), level(0.0, -0.045), 0.015, 4 if lod < 2 else 2), 0.008, "black_metal"))
        if lod < 2:
            for at in (rear, front):
                parts.append(kit.hex_nut("pivot", g(x + side * 0.017, at[0], at[1]), (side, 0.0, 0.0), 0.008, 0.005))
    axle(parts, d, lod, 0.098)
    return kit.join(parts, "fork_lower")


# ------------------------------------------------------------------------------- leading link

# BikeModel lays a leading-link fork's pivot, knee and spring units out level (y up, z back) round
# the steering axis, which leans back by the head angle: these are drawn for a 26 degree head.
HEAD = math.radians(26.0)


def level(vy, vz):
    """A level offset (up, back) as one along the steering axis and square back from it."""
    return (vy * math.cos(HEAD) + vz * math.sin(HEAD), -vy * math.sin(HEAD) + vz * math.cos(HEAD))


def ll_points(p):
    fl = float(p["length"])
    earles = bool(p.get("look", {}).get("earles", False))
    pivot_off = level(0.07, 0.3) if earles else level(0.035, 0.1)
    pivot = (-fl + pivot_off[0], pivot_off[1])
    kb = level(0.0, 0.1 if earles else 0.03)
    knee = (-fl * 0.55 + kb[0], kb[1])
    return fl, earles, pivot_off, pivot, knee


def leading_link_upper(p, lod):
    d = DETAIL[lod]
    fl, earles, pivot_off, pivot, knee = ll_points(p)
    parts = []
    for side in (-1.0, 1.0):
        x = 0.085 * side
        # The fixed leg, bent down past the wheel to the pivot behind the axle.
        mid = (knee[0] + (pivot[0] - knee[0]) * 0.5 + 0.02, knee[1] + (pivot[1] - knee[1]) * 0.5)
        parts.append(kit.sweep("leg", [g(x, 0.02, 0.0), g(x, (0.02 + knee[0]) * 0.5, knee[1] * 0.4), g(x, *knee), g(x, *mid), g(x, *pivot)],
            [0.018, 0.018, 0.017, 0.016, 0.015], d["round"], "paint"))
        parts.append(boss("pivot", x - 0.016, x + 0.016, pivot[0], pivot[1], 0.021, d["round"], "cast_alloy"))
        # The coil-over unit: from its top on the leg down to its eye over the link.
        up, fwd = level(0.0, -0.06), level(0.03, -0.01)
        top = (knee[0] + (pivot[0] - knee[0]) * 0.2 + up[0], knee[1] + (pivot[1] - knee[1]) * 0.2 + up[1])
        low = (-fl + pivot_off[0] * 0.45 + fwd[0], pivot_off[1] * 0.45 + fwd[1])
        xs = x + side * 0.028
        parts.append(rod("damper", (xs, *top), (xs, *low), 0.013, d["round"], "cast_alloy", r_end=0.011))
        if lod < 2:
            ds, dz = low[0] - top[0], low[1] - top[1]
            n = math.hypot(ds, dz)
            pts = []
            turns = 6
            k = max(int(turns * d["per_turn"]), 6)
            for i in range(k + 1):
                t = 0.12 + 0.76 * i / k
                a = 2.0 * math.pi * turns * i / k
                cs, cz = top[0] + ds * t, top[1] + dz * t
                # (Round the unit's line: across, and square to it in the leg's plane.)
                pts.append(g(xs + math.cos(a) * 0.024, cs + math.sin(a) * 0.024 * (-dz / n), cz + math.sin(a) * 0.024 * (ds / n)))
            parts.append(kit.sweep("spring", pts, 0.004, d["coil"], "chrome"))
            for end in (top, low):
                parts.append(boss("eye", xs - 0.01, xs + 0.01, end[0], end[1], 0.011, d["small"], "raw_steel"))
    # The brace across the pivots (where BikeModel draws its box) and the yokes.
    parts.append(rod("brace", (-0.085, pivot[0], pivot[1]), (0.085, pivot[0], pivot[1]), 0.013, d["round"], "paint"))
    yokes(parts, d, lod)
    return kit.join(parts, "fork_upper")


def leading_link_lower(p, lod):
    """Drawn level round the axle (s up, z back, as BikeModel lays the links out on the hub),
    not along the steering axis: BikeModel puts it on the hub without turning it."""
    d = DETAIL[lod]
    earles = bool(p.get("look", {}).get("earles", False))
    pivot_off = (0.07, 0.3) if earles else (0.035, 0.1)
    parts = []
    for side in (-1.0, 1.0):
        x = 0.085 * side
        # The link from the pivot forward to the axle: a pressed-steel arm, deeper at the pivot.
        a = (pivot_off[0], pivot_off[1])
        b = (0.0, 0.0)
        ang = math.atan2(b[1] - a[1], b[0] - a[0])
        outline = []
        segs = 5 if lod < 2 else 2
        for k in range(segs + 1):
            t = ang + math.pi * 0.5 + math.pi * k / segs
            outline.append((a[0] + math.cos(t) * 0.024, a[1] + math.sin(t) * 0.024))
        for k in range(segs + 1):
            t = ang - math.pi * 0.5 + math.pi * k / segs
            outline.append((b[0] + math.cos(t) * 0.017, b[1] + math.sin(t) * 0.017))
        xl = x + side * 0.004
        parts.append(plate("link", xl, outline, 0.016, "black_metal"))
        if lod < 2:
            # The spring unit's lower mount on the link.
            m = (pivot_off[0] * 0.45 + 0.03, pivot_off[1] * 0.45 - 0.01)
            parts.append(boss("mount", xl + side * 0.008, xl + side * 0.03, m[0], m[1], 0.009, d["small"], "raw_steel"))
    if earles:
        # The Earles arms are one swinging loop: joined behind the tyre at the pivot.
        parts.append(rod("loop", (-0.089, pivot_off[0], pivot_off[1]), (0.089, pivot_off[0], pivot_off[1]), 0.012, d["round"], "black_metal"))
    axle(parts, d, lod, 0.095)
    return kit.join(parts, "fork_lower")


BUILDERS = {"girder": (girder_upper, girder_lower), "springer": (springer_upper, springer_lower),
    "leading_link": (leading_link_upper, leading_link_lower)}


def parts():
    out = []
    for part_id, p in sorted(catalogue().items()):
        up, low = BUILDERS[p["style"]]
        out.append({"kind": "fork", "path": "fork/%s_upper.glb" % part_id, "build": lambda lod, f=up, q=p: f(q, lod), "mounts": {}})
        out.append({"kind": "fork", "path": "fork/%s_lower.glb" % part_id, "build": lambda lod, f=low, q=p: f(q, lod),
            "mounts": {"axle": ((0.0, 0.0, 0.0), (1.0, 0.0, 0.0))}})
    return out
