"""The top ends of the classic upright parallel twins (the "twin" engines: a Bonneville's or an
A10's): the barrels as one finned casting and, on them, the head each head part makes: a one-valve
flathead, the two-valve pushrod head with its two rocker boxes, and overhead-cam heads under one
cam cover in four finishes.

Drawn for the reference 700 cc twin (agreement 4): the cylinders HALF_SPACING either side of the
middle, the origin on the left barrel's base (cyl_1) and Z up the bores. The game scales a top end
by the engine's size across and forward and by its barrels' height up (BikeModel's _eng_s and
_head_k), so the barrels, plugs, ports and inlets land where BikeModel lays them out. Heights are
the code-built engine's (bike_model.gd's _draw_engine and _draw_head): the barrels from -0.1 to 0.09
up the bore, the head from 0.09 to 0.215, the plugs standing on it at 0.2. Widths stay inside the
room BikeModel keeps round them for every twin (_engine_corners), so the frame and tank still clear."""

import kit

HALF_SPACING = 0.06      # m: the reference twin's bores either side of the middle (BikeModel: 0.12 * _eng_s apart)
FIN = 0.065              # m: how far the barrels' fins reach out round each bore (BikeModel allows 1.55 x the bore
                         # radius: a little less, as a small twin's bores sit further apart in a cruiser's frame)
HEAD_X = 0.062           # m: how far the head reaches out past each bore (BikeModel keeps 0.08, at a 1200's size too)
HEAD_Y = 0.062           # m: the head's half depth, front to back (BikeModel keeps 0.075)

# How finely each LOD is drawn.
DETAIL = [
    {"corner": 8, "fins": 10, "round": 24, "head_fins": 3, "bevel": True},
    {"corner": 3, "fins": 6, "round": 10, "head_fins": 2, "bevel": False},
    {"corner": 1, "fins": 2, "round": 6, "head_fins": 0, "bevel": False},
]
CYL_X = (-HALF_SPACING, HALF_SPACING)


def _bevel(d, w):
    return w if d["bevel"] else 0.0


def barrels(lod, parts):
    """The barrels: one casting with deep square fins round both bores, rounded at the corners
    and tapering a touch towards the head, pushrod tubes front and back between the bores, and the
    base flange on the cases."""
    d = DETAIL[lod]
    hs = HALF_SPACING
    core = FIN * 0.68
    parts.append(kit.prism("core", kit.rounded_rect(hs + core, core, core, d["corner"] * 2), -0.098, 0.088, "cast_alloy"))
    parts.append(kit.prism("flange", kit.rounded_rect(hs + FIN * 0.9, FIN * 0.9, 0.022, d["corner"]), -0.1, -0.091, "cast_alloy", _bevel(d, 0.0015)))
    n = d["fins"]
    for k in range(n):
        z = -0.08 + k * (0.162 / max(n - 1, 1))
        g = 1.0 - 0.06 * k / max(n - 1, 1)
        t = [0.0042, 0.006, 0.03][lod]
        parts.append(kit.prism("fin", kit.rounded_rect(hs + FIN * g - 0.001, FIN * g - 0.001, 0.024 * g, d["corner"]), z - t * 0.5, z + t * 0.5,
            "cast_alloy", _bevel(d, 0.0012)))
    if lod < 2:
        for y in (-1.0, 1.0):
            parts.append(kit.tube("pushrod", (0.0, y * FIN * 0.8, -0.092), (0.0, y * FIN * 0.8, 0.088), 0.008, d["round"] // 2 + 2, "chrome"))


def head_casting(lod, parts, port_r=1.0):
    """The head's casting under its covers: a deck on the barrels, fins, the exhaust ports out of
    the front and the inlets out of the back (bigger on a ported head), and a boss for each plug."""
    d = DETAIL[lod]
    hs = HALF_SPACING
    parts.append(kit.prism("deck", kit.rounded_rect(hs + HEAD_X, HEAD_Y, 0.026, d["corner"]), 0.09, 0.104, "cast_alloy", _bevel(d, 0.0015)))
    parts.append(kit.prism("block", kit.rounded_rect(hs + HEAD_X - 0.012, HEAD_Y - 0.01, 0.028, d["corner"]), 0.1, 0.152, "cast_alloy", _bevel(d, 0.003)))
    for k in range(d["head_fins"]):
        z = 0.112 + k * 0.013
        parts.append(kit.prism("hfin", kit.rounded_rect(hs + HEAD_X - 0.001, HEAD_Y - 0.001, 0.024, d["corner"]), z - 0.0024, z + 0.0024,
            "cast_alloy", _bevel(d, 0.001)))
    for x in CYL_X:
        if lod < 2:
            parts.append(kit.tube("export", (x, 0.04, 0.11), (x, HEAD_Y, 0.11), 0.021 * port_r, d["round"], "cast_alloy", _bevel(d, 0.002)))
            parts.append(kit.tube("inport", (x, -0.04, 0.12), (x, -HEAD_Y, 0.12), 0.017 * port_r, d["round"], "cast_alloy", _bevel(d, 0.002)))
        parts.append(kit.tube("plugboss", (x, -0.02, 0.14), (x, -0.02, 0.2), 0.014, d["round"], "cast_alloy", _bevel(d, 0.0015)))


def pushrod_head(lod, parts):
    """The two-valve head: two polished rocker boxes across it, the exhaust rockers' in front and
    the inlets' behind, a round inspection cap over each pair of valves and the rocker spindles'
    ends showing on the boxes' sides."""
    d = DETAIL[lod]
    hs = HALF_SPACING
    head_casting(lod, parts)
    for y0, y1 in ((0.004, HEAD_Y), (-HEAD_Y, -0.037)):
        mid = (y0 + y1) * 0.5
        half = (y1 - y0) * 0.5
        parts.append(kit.prism("rockerbox", kit.rounded_rect(half, 0.026, min(half, 0.026) * 0.9, d["corner"]), -(hs + 0.052), hs + 0.052,
            "polished_alloy", _bevel(d, 0.004), 2, "YZ", (0.0, mid, 0.174)))
        if lod < 2:
            for x in CYL_X:
                parts.append(kit.tube("cap", (x, mid, 0.199), (x, mid, 0.207), min(0.015, half * 0.85), d["round"], "chrome", _bevel(d, 0.0015)))
                if lod == 0:
                    parts.append(kit.hex_nut("capnut", (x, mid, 0.207), (0.0, 0.0, 1.0), 0.0065, 0.004))
            for side in (-1.0, 1.0):
                parts.append(kit.tube("spindle", (side * (hs + 0.052), mid, 0.176), (side * (hs + 0.058), mid, 0.176), 0.0075, d["round"] // 2 + 2, "chrome"))


def cam_head(cover, tall=1.0, ribs=2, bolts="raw_steel", port_r=1.0):
    """An overhead-cam head under one cam cover across both bores (finished `cover`; `tall`er and
    with more `ribs` on a hot cam's), held down by cap bolts each side, the cam ends' round caps at
    either end."""
    def build(lod, parts):
        d = DETAIL[lod]
        hs = HALF_SPACING
        head_casting(lod, parts, port_r)
        top = 0.15 + 0.044 * tall
        parts.append(kit.prism("camcover", kit.rounded_rect(hs + HEAD_X - 0.012, HEAD_Y - 0.012, 0.028, d["corner"]), 0.15, top, cover, _bevel(d, 0.008), 3))
        if lod == 2:
            return
        for k in range(ribs):
            y = 0.024 + k * 0.012
            parts.append(kit.prism("rib", kit.rounded_rect(hs + 0.028, 0.0035, 0.003, 1), top - 0.004, top + 0.004, cover, at=(0.0, y, 0.0)))
        for x in (-hs - 0.04, -hs * 0.5, hs * 0.5, hs + 0.04):
            for y in (-0.042, 0.042):
                if lod == 0 or abs(x) > hs:
                    parts.append(kit.hex_nut("capbolt", (x, y, top - 0.001), (0.0, 0.0, 1.0), 0.0052, 0.006, bolts))
        for side in (-1.0, 1.0):
            parts.append(kit.tube("camcap", (side * (hs + HEAD_X - 0.012), 0.0, 0.172), (side * (hs + HEAD_X - 0.003), 0.0, 0.172), 0.024, d["round"],
                cover, _bevel(d, 0.003)))
    return build


def flathead(lod, parts):
    """The one-valve flathead: no cam up top, a deep-finned lid over the combustion chambers held
    down by a grid of studs, the plugs standing up on their bosses."""
    d = DETAIL[lod]
    hs = HALF_SPACING
    parts.append(kit.prism("deck", kit.rounded_rect(hs + HEAD_X, HEAD_Y, 0.026, d["corner"]), 0.09, 0.1, "cast_alloy", _bevel(d, 0.0015)))
    parts.append(kit.prism("block", kit.rounded_rect(hs + HEAD_X - 0.014, HEAD_Y - 0.008, 0.028, d["corner"]), 0.1, 0.168, "cast_alloy", _bevel(d, 0.003)))
    n = [5, 3, 1][lod]
    for k in range(n):
        z = 0.108 + k * (0.05 / max(n - 1, 1))
        t = 0.0045 if lod < 2 else 0.04
        parts.append(kit.prism("lidfin", kit.rounded_rect(hs + HEAD_X - 0.001, HEAD_Y - 0.001, 0.024, d["corner"]), z - t * 0.5, z + t * 0.5,
            "cast_alloy", _bevel(d, 0.001)))
    parts.append(kit.prism("lid", kit.rounded_rect(hs + HEAD_X - 0.02, HEAD_Y - 0.012, 0.028, d["corner"]), 0.168, 0.178, "cast_alloy", _bevel(d, 0.003)))
    if lod < 2:
        for x in (-hs - 0.032, -hs * 0.45, hs * 0.45, hs + 0.032):
            for y in (-0.04, 0.04):
                parts.append(kit.hex_nut("stud", (x, y, 0.178), (0.0, 0.0, 1.0), 0.0058, 0.007))
        for x in CYL_X:
            parts.append(kit.tube("export", (x, 0.04, 0.11), (x, HEAD_Y, 0.11), 0.02, d["round"], "cast_alloy", _bevel(d, 0.002)))
            parts.append(kit.tube("inport", (x, -0.04, 0.12), (x, -HEAD_Y, 0.12), 0.017, d["round"], "cast_alloy", _bevel(d, 0.002)))
    for x in CYL_X:
        parts.append(kit.tube("plugboss", (x, -0.02, 0.17), (x, -0.02, 0.2), 0.014, d["round"], "cast_alloy", _bevel(d, 0.0015)))


def mounts():
    """Every mount, moved with the origin to cyl_1: (where, which way +Z points)."""
    m = {}
    for i, x in enumerate(CYL_X):
        n = i + 1
        x += HALF_SPACING
        m["cyl_%d" % n] = ((x, 0.0, 0.0), (0.0, 0.0, 1.0))
        m["plug_%d" % n] = ((x, -0.02, 0.2), (0.0, 0.0, 1.0))
        m["exhaust_port_%d" % n] = ((x, HEAD_Y, 0.11), (0.0, 1.0, 0.0))
        m["intake_%d" % n] = ((x, -HEAD_Y, 0.12), (0.0, -1.0, 0.0))
    return m


# The head parts this family draws a twin's top end for (data/parts.json "head"), each with its
# head's shape and the name on the contact sheet.
LAYOUT = "twin"
HEADS = {
    "one_valve_flathead": (flathead, "Flathead"),
    "two_valve_stock": (pushrod_head, "Two-valve pushrod"),
    "four_valve": (cam_head("black_metal"), "Four-valve"),
    "big_valve_ported": (cam_head("polished_alloy", port_r=1.18), "Big-valve ported"),
    "hot_cam": (cam_head("paint", tall=1.12, ribs=4), "Hot cam"),
    "race_high_comp": (cam_head("black_metal", ribs=3, bolts="anodised", port_r=1.12), "Race high-comp"),
}


def parts():
    """The glbs this family writes: (path under assets/bike_parts, name, a function drawing LOD n)."""
    out = []
    for part_id, (head, name) in HEADS.items():
        def build(lod, head=head):
            pieces = []
            barrels(lod, pieces)
            head(lod, pieces)
            return kit.join(pieces, "lod%d" % lod, (HALF_SPACING, 0.0, 0.0))
        out.append({"kind": "head", "path": "head/%s/%s.glb" % (LAYOUT, part_id), "name": name, "build": build, "mounts": mounts()})
    return out
