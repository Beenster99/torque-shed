"""The telescopic forks (conventional and upside-down), two glbs for each in the catalogue, as
BikeModel's _draw_fork draws them at the fork's own length (agreement 6b): fork/<id>_upper.glb, what
turns with the bars and stays put as the fork works (the stanchions, or a USD's fat outer tubes, the
two yokes, the top caps and any shrouds), its origin on the head; and fork/<id>_lower.glb, what
moves with the wheel (the sliders, or a USD's thin inner tubes, the axle clamps and their bolts,
the axle nuts, any gaiters and fork brace), its origin on the axle at mount_axle. Both run along the
steering axis, up +Z here. Girder, springer and leading-link forks are left to BikeModel for now.

Tags: the stanchions `paint` (the part's colour), the sliders and clamps `cast_alloy` (the game
gives them the look's lowers finish), the shrouds `chrome` (the shrouds' finish), the yokes
`black_metal`, gaiters `rubber`, bolts and nuts `raw_steel`."""

import json
import os

import kit

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOGUE = os.path.join(HERE, "..", "..", "..", "data", "parts.json")

DETAIL = [{"round": 18, "corner": 3}, {"round": 10, "corner": 1}, {"round": 6, "corner": 0}]


def catalogue():
    with open(CATALOGUE) as f:
        return {k: p for k, p in json.load(f)["fork"].items() if p.get("style", "conventional") in ("conventional", "usd")}


def g(x, s, z):
    """A point x across, s up the steering axis and z back (Godot's axes turned to the axis) as Blender's."""
    return (x, -z, s)


def _shape(p):
    lk = p.get("look", {})
    return float(lk.get("wide", 1.0)) * 0.09, float(lk.get("leg", 1.0)), p.get("style") == "usd", lk


def upper(part_id, lod):
    p = catalogue()[part_id]
    d = DETAIL[lod]
    lx, lr, usd, lk = _shape(p)
    fl = float(p.get("length", 0.75))
    parts = []
    for side in (-1.0, 1.0):
        x = lx * side
        r = (0.034 if usd else 0.024) * lr
        parts.append(kit.tube("stanchion", g(x, 0.02, 0.0), g(x, -fl * 0.55, 0.0), r, d["round"], "paint"))
        if lod < 2:
            parts.append(kit.tube("cap", g(x, 0.02, 0.0), g(x, 0.034, 0.0), r * 0.8, 6, "raw_steel"))
        if lk.get("shrouds"):
            parts.append(kit.tube("shroud", g(x, 0.0, 0.0), g(x, -0.2, 0.0), 0.038 * lr, d["round"], "chrome"))
    # The top and bottom yokes clamping the tubes, the steering stem between them.
    outline = kit.rounded_rect(0.12, 0.04, 0.02, max(1, d["corner"]))
    for s in (0.0, -0.16):
        parts.append(kit.prism("yoke", outline, s - 0.02, s + 0.02, "black_metal", 0.002 if lod == 0 else 0.0, 1))
    return kit.join(parts, "fork_upper")


def lower(part_id, lod):
    p = catalogue()[part_id]
    d = DETAIL[lod]
    lx, lr, usd, lk = _shape(p)
    fl = float(p.get("length", 0.75))
    parts = []
    for side in (-1.0, 1.0):
        x = lx * side
        parts.append(kit.tube("slider", g(x, 0.0, 0.0), g(x, fl * 0.5, 0.0), (0.022 if usd else 0.032) * lr, d["round"], "cast_alloy"))
        # The axle clamp at the foot, pinched by two bolts, and the axle nut outside it.
        foot = kit.rounded_rect(0.025 * lr, 0.0375, 0.01, max(1, d["corner"]))
        parts.append(kit.prism("foot", foot, -0.03, 0.03, "cast_alloy", 0.002 if lod == 0 else 0.0, 1, at=(x, 0.0, 0.0)))
        if lod < 2:
            for s in (-0.014, 0.014):
                parts.append(kit.hex_nut("clamp_bolt", g(x, s, 0.035), (0.0, -1.0, 0.0), 0.006, 0.014))
            parts.append(kit.hex_nut("axle_nut", g(x + side * 0.025 * lr, 0.0, 0.0), (side, 0.0, 0.0), 0.014, 0.012))
        if lk.get("gaiters") and lod < 2:
            for k in range(6):
                parts.append(kit.ring("gaiter", 0.0, 0.03 * lr, 0.009, d["round"], "rubber", 6 if lod == 0 else 4))
                ob = parts[-1]
                ob.rotation_euler = (1.5707963267948966, 0.0, 0.0)
                ob.location = g(x, fl * 0.5 + 0.02 + k * 0.022, 0.0)
    if lk.get("brace"):
        outline = kit.rounded_rect(lx, 0.025, 0.01, max(1, d["corner"]))
        parts.append(kit.prism("brace", outline, fl * 0.25 - 0.015, fl * 0.25 + 0.015, "paint", 0.0, 1))
    return kit.join(parts, "fork_lower")


def parts():
    out = []
    for part_id in catalogue():
        out.append({"kind": "fork", "path": "fork/%s_upper.glb" % part_id, "build": lambda lod, i=part_id: upper(i, lod), "mounts": {}})
        out.append({"kind": "fork", "path": "fork/%s_lower.glb" % part_id, "build": lambda lod, i=part_id: lower(i, lod),
            "mounts": {"axle": ((0.0, 0.0, 0.0), (1.0, 0.0, 0.0))}})
    return out
