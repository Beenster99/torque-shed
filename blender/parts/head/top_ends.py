"""Engine top ends (the barrels and the head on them, the head kind), one glb for each head part
on each engine layout.

The row layouts (BikeModel's "single", "twin", "parallel", "triple" and "inline") are one glb for
the whole row: the origin on the first barrel's base (cyl_1), Z up the bores, the bores SPACING
apart. The game scales a row by its own bores' spacing across, by the engine's size front to back
(BikeModel's _eng_s) and by the barrels' height up (_head_k), so barrels, plugs and ports land
where BikeModel lays them out. A two-stroke's top ends are drawn one cylinder at a time: one glb
put on each cylinder (they come with one or two). So are a V-twin's and a boxer's, whose
cylinders point different ways, with a glb of each cylinder's own (`<head part>_<n>.glb`), its
origin on that cylinder's base and Z up its bore.

Heights are the code-built engine's (bike_model.gd's _draw_engine and _draw_head): the barrels
from -0.1 to 0.09 up the bore, a four-stroke's head from 0.09 to 0.215 with the plugs standing on
it at 0.2, a two-stroke's from 0.09 to 0.145. Each layout's widths stay inside the room BikeModel
keeps round its barrels and heads for every engine of that layout (_engine_corners), which is
what keeps the frame and the tank clear: `fin` (how far the barrels reach out round a bore),
`head_x` (how far the head reaches past the end bores) and `head_y` (its half depth) are each the
smallest that room comes to over the layout's engines, at the reference size."""

import kit

# The barrels are the engine part's colour, not the head's (agreement v5's "__<slot>" tags).
BARREL = "cast_alloy__engine"
SPACING = 0.12           # m: a 700 cc's bores apart, as BikeModel lays a row out (0.12 x _eng_s)

# How finely each LOD is drawn.
DETAIL = [
    {"corner": 8, "fins": 10, "round": 24, "head_fins": 3, "bevel": True},
    {"corner": 3, "fins": 6, "round": 10, "head_fins": 2, "bevel": False},
    {"corner": 1, "fins": 2, "round": 6, "head_fins": 0, "bevel": False},
]

# The layouts: how many bores in a row, how the barrels are made ("finned" casting, or a
# water-cooled "block"), and the room each gets (see above). A two-stroke is "per_cylinder".
LAYOUTS = {
    "single": {"cyls": 1, "barrels": "finned", "fin": 0.088, "head_x": 0.064, "head_y": 0.08},
    "twin": {"cyls": 2, "barrels": "finned", "fin": 0.065, "head_x": 0.062, "head_y": 0.062, "pushrods": True},
    "parallel": {"cyls": 2, "barrels": "block", "fin": 0.07, "head_x": 0.064, "head_y": 0.06},
    "triple": {"cyls": 3, "barrels": "block", "fin": 0.061, "head_x": 0.064, "head_y": 0.06},
    "inline": {"cyls": 4, "barrels": "block", "fin": 0.057, "head_x": 0.064, "head_y": 0.059},
    "2stroke": {"cyls": 1, "barrels": "finned", "fin": 0.066, "head_r": 0.077, "two_stroke": True},
}

# The layouts drawn a cylinder at a time, a glb for each (`<head part>_<n>.glb`, n in BikeModel's
# _cyls order): a V-twin's front and rear cylinders, a boxer's left and right. Each is a row of one,
# drawn for a 0.05 m bore (scripts/blender_parts.gd PER_CYLINDER_BORE: 0.045 m for a two-stroke),
# with the room BikeModel keeps round a cylinder of that bore at the biggest bore of the layout.
CYLINDERS = {
    "vtwin": [
        {"cyls": 1, "barrels": "finned", "fin": 0.074, "head_x": 0.058, "head_y": 0.066},
        {"cyls": 1, "barrels": "finned", "fin": 0.074, "head_x": 0.058, "head_y": 0.066, "exhaust": "right", "intake": "front"},
    ],
    "boxer": [
        {"cyls": 1, "barrels": "finned", "fin": 0.074, "head_x": 0.062, "head_y": 0.066},
        {"cyls": 1, "barrels": "finned", "fin": 0.074, "head_x": 0.062, "head_y": 0.066},
    ],
}


def _bevel(d, w):
    return w if d["bevel"] else 0.0


def _xs(spec):
    """The bores' x, the row centred on 0 (shifted onto cyl_1 at export)."""
    n = spec["cyls"]
    return [(i - (n - 1) * 0.5) * SPACING for i in range(n)]


def _half_row(spec):
    return (spec["cyls"] - 1) * 0.5 * SPACING


def finned_barrels(spec, lod, parts):
    """Air-cooled barrels: one casting with deep square fins round every bore, rounded at the
    corners and tapering a touch towards the head, and the base flange on the cases (a twin's
    pushrod tubes front and back between its bores)."""
    d = DETAIL[lod]
    hw = _half_row(spec)
    fin = spec["fin"]
    core = fin * 0.68
    parts.append(kit.prism("core", kit.rounded_rect(hw + core, core, core, d["corner"] * 2), -0.098, 0.088, BARREL))
    parts.append(kit.prism("flange", kit.rounded_rect(hw + fin * 0.9, fin * 0.9, 0.022, d["corner"]), -0.1, -0.091, BARREL, _bevel(d, 0.0015)))
    n = d["fins"]
    for k in range(n):
        z = -0.08 + k * (0.162 / max(n - 1, 1))
        g = 1.0 - 0.06 * k / max(n - 1, 1)
        t = [0.0042, 0.006, 0.03][lod]
        parts.append(kit.prism("fin", kit.rounded_rect(hw + fin * g - 0.001, fin * g - 0.001, 0.024 * g * fin / 0.065, d["corner"]),
            z - t * 0.5, z + t * 0.5, BARREL, _bevel(d, 0.0012)))
    if spec.get("pushrods") and lod < 2:
        for y in (-1.0, 1.0):
            parts.append(kit.tube("pushrod", (0.0, y * fin * 0.8, -0.092), (0.0, y * fin * 0.8, 0.088), 0.008, d["round"] // 2 + 2, "chrome"))


def block_barrels(spec, lod, parts):
    """A water-cooled block: one smooth casting round the row of bores, a raised band round its
    top and bottom, the cam chain tunnel up the front of it and the coolant outlet stubs at the
    back."""
    d = DETAIL[lod]
    hw = _half_row(spec)
    r = spec["fin"]
    parts.append(kit.prism("block", kit.rounded_rect(hw + r - 0.006, r - 0.006, 0.03, d["corner"] * 2), -0.1, 0.09, BARREL, _bevel(d, 0.004), 2))
    if lod < 2:
        for z0, z1 in ((-0.1, -0.084), (0.07, 0.09)):
            parts.append(kit.prism("band", kit.rounded_rect(hw + r - 0.001, r - 0.001, 0.032, d["corner"] * 2), z0, z1, BARREL, _bevel(d, 0.002)))
        # The cam chain tunnel bulging out of the front, in the middle (between a triple's second and third bores).
        x = 0.0 if spec["cyls"] % 2 == 0 else SPACING * 0.5
        parts.append(kit.prism("tunnel", kit.rounded_rect(0.022, 0.012, 0.01, d["corner"]), -0.09, 0.088, BARREL, _bevel(d, 0.002),
            at=(x, r - 0.008, 0.0)))
        for x in _xs(spec):
            parts.append(kit.tube("coolant", (x, -r + 0.004, 0.06), (x, -r - 0.002, 0.06), 0.009, d["round"] // 2 + 2, BARREL))


# Which way a head's exhaust and inlet ports face, as a Blender direction (a V-twin's rear head
# breathes out of its right-hand side, and both breathe in from the vee between them).
FACING = {"front": (0.0, 1.0), "back": (0.0, -1.0), "right": (1.0, 0.0)}


def port(spec, x, which):
    """Where a bore's exhaust ("exhaust") or inlet ("intake") port opens on the head's edge, which
    way it faces, and how high up the bore it is."""
    face = spec.get(which, "front" if which == "exhaust" else "back")
    fx, fy = FACING[face]
    reach = spec["head_x"] if fx else spec["head_y"]
    z = 0.11 if which == "exhaust" else 0.12
    return (x + fx * reach, fy * reach, z), (fx, fy, 0.0)


def port_stubs(spec, x, lod, parts, r_ex, r_in):
    d = DETAIL[lod]
    for which, r, name in (("exhaust", r_ex, "export"), ("intake", r_in, "inport")):
        (px, py, pz), (fx, fy, _) = port(spec, x, which)
        parts.append(kit.tube(name, (px - fx * 0.022, py - fy * 0.022, pz), (px, py, pz), r, d["round"], "cast_alloy", _bevel(d, 0.002)))


def head_casting(spec, lod, parts, port_r=1.0):
    """A four-stroke head's casting under its covers: a deck on the barrels, fins on an air-cooled
    head, the exhaust ports out of the front and the inlets out of the back (bigger on a ported
    head), and a boss for each plug."""
    d = DETAIL[lod]
    hw = _half_row(spec)
    hx, hy = spec["head_x"], spec["head_y"]
    parts.append(kit.prism("deck", kit.rounded_rect(hw + hx, hy, 0.026, d["corner"]), 0.09, 0.104, "cast_alloy", _bevel(d, 0.0015)))
    parts.append(kit.prism("block", kit.rounded_rect(hw + hx - 0.012, hy - 0.01, 0.028, d["corner"]), 0.1, 0.152, "cast_alloy", _bevel(d, 0.003)))
    if spec["barrels"] == "finned":
        for k in range(d["head_fins"]):
            z = 0.112 + k * 0.013
            parts.append(kit.prism("hfin", kit.rounded_rect(hw + hx - 0.001, hy - 0.001, 0.024, d["corner"]), z - 0.0024, z + 0.0024,
                "cast_alloy", _bevel(d, 0.001)))
    for x in _xs(spec):
        if lod < 2:
            port_stubs(spec, x, lod, parts, 0.021 * port_r, 0.017 * port_r)
        parts.append(kit.tube("plugboss", (x, -0.02, 0.14), (x, -0.02, 0.2), 0.014, d["round"], "cast_alloy", _bevel(d, 0.0015)))


def pushrod_head(spec, lod, parts):
    """The two-valve head: two polished rocker boxes across it, the exhaust rockers' in front and
    the inlets' behind, a round inspection cap over each pair of valves and the rocker spindles'
    ends showing on the boxes' sides."""
    d = DETAIL[lod]
    hw = _half_row(spec)
    hx, hy = spec["head_x"], spec["head_y"]
    head_casting(spec, lod, parts)
    for y0, y1 in ((0.004, hy), (-hy, -0.037)):
        mid = (y0 + y1) * 0.5
        half = (y1 - y0) * 0.5
        parts.append(kit.prism("rockerbox", kit.rounded_rect(half, 0.026, min(half, 0.026) * 0.9, d["corner"]), -(hw + hx - 0.01), hw + hx - 0.01,
            "polished_alloy", _bevel(d, 0.004), 2, "YZ", (0.0, mid, 0.174)))
        if lod < 2:
            for x in _xs(spec):
                parts.append(kit.tube("cap", (x, mid, 0.199), (x, mid, 0.207), min(0.015, half * 0.85), d["round"], "chrome", _bevel(d, 0.0015)))
                if lod == 0:
                    parts.append(kit.hex_nut("capnut", (x, mid, 0.207), (0.0, 0.0, 1.0), 0.0065, 0.004))
            for side in (-1.0, 1.0):
                parts.append(kit.tube("spindle", (side * (hw + hx - 0.01), mid, 0.176), (side * (hw + hx - 0.004), mid, 0.176), 0.0075,
                    d["round"] // 2 + 2, "chrome"))


def cam_head(cover, tall=1.0, ribs=2, bolts="raw_steel", port_r=1.0):
    """An overhead-cam head under one cam cover across the row (finished `cover`; `tall`er and
    with more `ribs` on a hot cam's), held down by cap bolts along each side, the cam ends' round
    caps at either end."""
    def build(spec, lod, parts):
        d = DETAIL[lod]
        hw = _half_row(spec)
        hx, hy = spec["head_x"], spec["head_y"]
        head_casting(spec, lod, parts, port_r)
        top = 0.15 + 0.044 * tall
        parts.append(kit.prism("camcover", kit.rounded_rect(hw + hx - 0.012, hy - 0.012, 0.028, d["corner"]), 0.15, top, cover, _bevel(d, 0.008), 3))
        if lod == 2:
            return
        for k in range(ribs):
            y = 0.024 + k * 0.012
            parts.append(kit.prism("rib", kit.rounded_rect(hw + 0.028, 0.0035, 0.003, 1), top - 0.004, top + 0.004, cover, at=(0.0, y, 0.0)))
        xs = _xs(spec)
        bolt_x = [xs[0] - 0.04] + [(a + b) * 0.5 for a, b in zip(xs, xs[1:])] + [xs[-1] + 0.04]
        if lod == 0:
            bolt_x += [x + o for x in xs for o in (-0.03, 0.03)]
        for x in bolt_x:
            for y in (-(hy - 0.02), hy - 0.02):
                parts.append(kit.hex_nut("capbolt", (x, y, top - 0.001), (0.0, 0.0, 1.0), 0.0052, 0.006, bolts))
        for side in (-1.0, 1.0):
            parts.append(kit.tube("camcap", (side * (hw + hx - 0.012), 0.0, 0.172), (side * (hw + hx - 0.003), 0.0, 0.172), 0.024, d["round"],
                cover, _bevel(d, 0.003)))
    return build


def flathead(spec, lod, parts):
    """The one-valve flathead: no cam up top, a deep-finned lid over the combustion chambers held
    down by a grid of studs, the plugs standing up on their bosses."""
    d = DETAIL[lod]
    hw = _half_row(spec)
    hx, hy = spec["head_x"], spec["head_y"]
    xs = _xs(spec)
    parts.append(kit.prism("deck", kit.rounded_rect(hw + hx, hy, 0.026, d["corner"]), 0.09, 0.1, "cast_alloy", _bevel(d, 0.0015)))
    parts.append(kit.prism("block", kit.rounded_rect(hw + hx - 0.014, hy - 0.008, 0.028, d["corner"]), 0.1, 0.168, "cast_alloy", _bevel(d, 0.003)))
    n = [5, 3, 1][lod]
    for k in range(n):
        z = 0.108 + k * (0.05 / max(n - 1, 1))
        t = 0.0045 if lod < 2 else 0.04
        parts.append(kit.prism("lidfin", kit.rounded_rect(hw + hx - 0.001, hy - 0.001, 0.024, d["corner"]), z - t * 0.5, z + t * 0.5,
            "cast_alloy", _bevel(d, 0.001)))
    parts.append(kit.prism("lid", kit.rounded_rect(hw + hx - 0.02, hy - 0.012, 0.028, d["corner"]), 0.168, 0.178, "cast_alloy", _bevel(d, 0.003)))
    if lod < 2:
        for x in [xs[0] - 0.032] + [x + o for x in xs for o in (-0.027, 0.027)] + [xs[-1] + 0.032]:
            for y in (-(hy - 0.022), hy - 0.022):
                parts.append(kit.hex_nut("stud", (x, y, 0.178), (0.0, 0.0, 1.0), 0.0058, 0.007))
        for x in xs:
            port_stubs(spec, x, lod, parts, 0.02, 0.017)
    for x in xs:
        parts.append(kit.tube("plugboss", (x, -0.02, 0.17), (x, -0.02, 0.2), 0.014, d["round"], "cast_alloy", _bevel(d, 0.0015)))


def two_stroke(spec, lod, parts):
    """A two-stroke's top end, one cylinder: a finned barrel with the exhaust port's stub out of
    its front and the transfer ports bulging its sides, and a round head of deep fins round the
    plug, no valves at all."""
    d = DETAIL[lod]
    fin = spec["fin"]
    core = fin * 0.68
    parts.append(kit.prism("core", kit.rounded_rect(core, core, core, d["corner"] * 2), -0.098, 0.088, BARREL))
    parts.append(kit.prism("flange", kit.rounded_rect(fin * 0.9, fin * 0.9, 0.022, d["corner"]), -0.1, -0.091, BARREL, _bevel(d, 0.0015)))
    n = d["fins"]
    for k in range(n):
        z = -0.08 + k * (0.162 / max(n - 1, 1))
        t = [0.0038, 0.006, 0.03][lod]
        # Wider fins round the top of the barrel, where it runs hottest.
        g = 0.9 + 0.1 * k / max(n - 1, 1)
        parts.append(kit.prism("fin", kit.rounded_rect(fin * g - 0.001, fin * g - 0.001, 0.018, d["corner"]), z - t * 0.5, z + t * 0.5,
            BARREL, _bevel(d, 0.001)))
    if lod < 2:
        parts.append(kit.tube("export", (0.0, core, -0.02), (0.0, fin + 0.004, -0.02), 0.019, d["round"], BARREL, _bevel(d, 0.002)))
        parts.append(kit.tube("inport", (0.0, -core, -0.05), (0.0, -fin - 0.004, -0.05), 0.016, d["round"], BARREL, _bevel(d, 0.002)))
        for side in (-1.0, 1.0):
            parts.append(kit.prism("transfer", kit.rounded_rect(0.012, 0.03, 0.01, d["corner"]), -0.09, 0.02, BARREL, _bevel(d, 0.002),
                at=(side * core, 0.0, 0.0)))
    r = spec["head_r"]
    parts.append(kit.tube("headcore", (0.0, 0.0, 0.09), (0.0, 0.0, 0.145), core, d["round"] * 2, "cast_alloy", _bevel(d, 0.003)))
    for k in range([5, 3, 1][lod]):
        z = 0.1 + k * 0.009
        g = 1.0 - 0.07 * k
        parts.append(kit.tube("hfin", (0.0, 0.0, z), (0.0, 0.0, z + (0.0035 if lod < 2 else 0.03)), r * g - 0.001, d["round"] * 2, "cast_alloy",
            _bevel(d, 0.001)))
    parts.append(kit.tube("plugboss", (0.0, 0.0, 0.13), (0.0, 0.0, 0.145), 0.014, d["round"], "cast_alloy", _bevel(d, 0.0015)))


def mounts(spec):
    """Every mount, moved with the origin to cyl_1: (where, which way +Z points)."""
    m = {}
    if spec.get("two_stroke"):
        fin = spec["fin"]
        return {"cyl_1": ((0.0, 0.0, 0.0), (0.0, 0.0, 1.0)), "plug_1": ((0.0, 0.0, 0.145), (0.0, 0.0, 1.0)),
            "exhaust_port_1": ((0.0, fin + 0.004, -0.02), (0.0, 1.0, 0.0)), "intake_1": ((0.0, -fin - 0.004, -0.05), (0.0, -1.0, 0.0))}
    hw = _half_row(spec)
    for i, x in enumerate(_xs(spec)):
        n = i + 1
        x += hw
        m["cyl_%d" % n] = ((x, 0.0, 0.0), (0.0, 0.0, 1.0))
        m["plug_%d" % n] = ((x, -0.02, 0.2), (0.0, 0.0, 1.0))
        m["exhaust_port_%d" % n] = port(spec, x, "exhaust")
        m["intake_%d" % n] = port(spec, x, "intake")
    return m


# The head parts (data/parts.json "head"): the shape each draws on a four-stroke. A two-stroke
# has no valves, so every head part gives it the same finned head.
HEADS = {
    "one_valve_flathead": flathead,
    "two_valve_stock": pushrod_head,
    "four_valve": cam_head("black_metal"),
    "big_valve_ported": cam_head("polished_alloy", port_r=1.18),
    "hot_cam": cam_head("paint", tall=1.12, ribs=4),
    "race_high_comp": cam_head("black_metal", ribs=3, bolts="anodised", port_r=1.12),
}


def _build(spec, head):
    def build(lod):
        pieces = []
        if spec.get("two_stroke"):
            two_stroke(spec, lod, pieces)
            return kit.join(pieces, "lod%d" % lod)
        (finned_barrels if spec["barrels"] == "finned" else block_barrels)(spec, lod, pieces)
        head(spec, lod, pieces)
        return kit.join(pieces, "lod%d" % lod, (_half_row(spec), 0.0, 0.0))
    return build


def parts():
    """The glbs this family writes: (path under assets/bike_parts, a function drawing LOD n, mounts).
    A two-stroke's one glb goes on each of its cylinders."""
    out = []
    for part_id, head in HEADS.items():
        for layout, spec in LAYOUTS.items():
            out.append({"kind": "head", "path": "head/%s/%s.glb" % (layout, part_id), "build": _build(spec, head), "mounts": mounts(spec)})
        for layout, specs in CYLINDERS.items():
            for i, spec in enumerate(specs):
                out.append({"kind": "head", "path": "head/%s/%s_%d.glb" % (layout, part_id, i + 1), "build": _build(spec, head), "mounts": mounts(spec)})
    return out
