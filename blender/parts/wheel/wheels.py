"""The wheels (rims, spokes and hubs), one glb for each wheel in the catalogue, drawn at its own
diameter and rim width as BikeModel's _draw_rim draws it, so the game never scales one. The origin
is on the axle (mount_axle), the axle along X.

Laced wheels ("spoked", "wire") have a drop-centre rim, a hub with a spoke flange each side and
their spokes laced tangentially, crossing on the way out; cast ones ("cast", "y", "carbon") a cast
rim with its spokes swept from a boss on the hub, split in pairs or forked in a Y where the part
says. A wheel's look is baked in, since every glb is one part: a polished or chrome lip, the
spokes' and the hub's finish, a drum hub, moon discs, a rim stripe (paint_2, the stripe's
colour). The rear wheel's cush drive is a piece of its own (wheel/fitting/cush_drive.glb), as only
the rear has one."""

import json
import math
import os

import kit

HERE = os.path.dirname(os.path.abspath(__file__))
CATALOGUE = os.path.join(HERE, "..", "..", "..", "data", "parts.json")

DETAIL = [
    {"segs": 96, "spoke_sides": 6, "hub_segs": 32, "full": True},
    {"segs": 40, "spoke_sides": 3, "hub_segs": 14, "full": False},
    {"segs": 12, "spoke_sides": 0, "hub_segs": 6, "full": False},
]

# A look's finish as a surface tag (BikeModel's _look_finish).
FINISH = {"chrome": "chrome", "polished": "polished_alloy", "black": "black_metal", "gold": "anodised", "brushed": "brushed_steel"}


def catalogue():
    with open(CATALOGUE) as f:
        return json.load(f)["wheel"]


def rim_profile(rim_r, hw, full):
    """The rim's section as (x, radius), closed: the flanges the tyre's beads sit inside, the bead
    seats, the drop centre, and the spoke bed underneath."""
    top = [(-hw - 0.0035, rim_r + 0.003), (-hw - 0.0015, rim_r + 0.009), (-hw + 0.0015, rim_r + 0.009), (-hw + 0.003, rim_r + 0.002)]
    if full:
        top += [(-hw + 0.008, rim_r - 0.002), (-hw * 0.32, rim_r - 0.004), (-hw * 0.2, rim_r - 0.012)]
    else:
        top += [(-hw * 0.25, rim_r - 0.006)]
    right = [(-x, r) for x, r in reversed(top)]
    under = [(hw + 0.0035, rim_r - 0.006), (hw - 0.002, rim_r - 0.013)]
    if full:
        under += [(hw * 0.3, rim_r - 0.018), (hw * 0.12, rim_r - 0.024)]
    under += [(-x, r) for x, r in reversed(under)]
    return top + right + under


def hub(p, lod, parts, laced):
    """The hub: a drum, a laced hub's barrel with its spoke flanges, or a cast wheel's boss and
    the axle spacers. Returns where the spokes start (x either side, radius)."""
    d = DETAIL[lod]
    lk = p.get("look", {})
    tag = FINISH.get(str(lk.get("hub_finish", "")), "chrome")
    if lk.get("hub") == "drum":
        # A big finned drum, and the brake plate on the left with its torque arm stub.
        prof = [(-0.06, 0.02), (-0.06, 0.085), (0.06, 0.085), (0.06, 0.02)]
        parts.append(kit.revolve("drum", prof, d["hub_segs"] * (2 if lod < 2 else 1), tag))
        if lod == 0:
            for k in range(4):
                fin = kit.ring("fin", 0.0, 0.088, 0.006, d["hub_segs"] * 2, tag, 6 if lod == 0 else 4)
                fin.rotation_euler = (0.0, 0.0, math.pi * 0.5)
                fin.location = (-0.045 + k * 0.03, 0.0, 0.0)
                parts.append(fin)
        if lod < 2:
            parts.append(kit.revolve("plate", [(-0.08, 0.015), (-0.08, 0.085), (-0.06, 0.085), (-0.06, 0.015)], d["hub_segs"] * 2, "raw_steel"))
            parts.append(kit.tube("torque_arm", (-0.075, 0.0, -0.07), (-0.075, -0.06, -0.1), 0.008, 8, "raw_steel"))
        return 0.05, 0.08
    if laced:
        prof = [(-0.07, 0.016), (-0.07, 0.024), (-0.04, 0.024), (-0.039, 0.05), (-0.033, 0.05), (-0.03, 0.03),
            (0.03, 0.03), (0.033, 0.05), (0.039, 0.05), (0.04, 0.024), (0.07, 0.024), (0.07, 0.016)]
        if not d["full"]:
            prof = [(-0.07, 0.016), (-0.07, 0.05), (0.07, 0.05), (0.07, 0.016)]
        parts.append(kit.revolve("hub", prof, d["hub_segs"], tag))
        return 0.036, 0.044
    parts.append(kit.revolve("spacer", [(-0.07, 0.012), (-0.07, 0.022), (0.07, 0.022), (0.07, 0.012)], d["hub_segs"], tag))
    return 0.0, 0.045


def wheel(part_id, lod):
    p = catalogue()[part_id]
    lk = p.get("look", {})
    d = DETAIL[lod]
    style = str(p.get("style", "cast"))
    rim_r = float(p["diameter"]) * 0.0127
    rim_w = float(p.get("rim_width", 3.5)) * 0.0254
    hw = rim_w * 0.5
    rim_tag = "carbon" if style == "carbon" else "polished_alloy"
    laced = style in ("spoked", "wire")
    parts = [kit.revolve("rim", rim_profile(rim_r, hw, d["full"]) if lod < 2 else
        [(-hw - 0.003, rim_r + 0.009), (hw + 0.003, rim_r + 0.009), (hw + 0.003, rim_r - 0.013), (-hw - 0.003, rim_r - 0.013)], d["segs"], rim_tag)]
    lip = FINISH.get(str(lk.get("lip", "")))
    if lip and lod < 2:
        # A polished or chrome lip: a band round each flange's top.
        for side in (-1.0, 1.0):
            band = kit.ring("lip", 0.0, rim_r + 0.007, 0.002, d["segs"], lip, 4)
            band.rotation_euler = (0.0, 0.0, math.pi * 0.5)
            band.location = (side * hw, 0.0, 0.0)
            parts.append(band)
    if lk.get("stripe") and lod < 2:
        for side in (-1.0, 1.0):
            tape = kit.ring("stripe", 0.0, rim_r - 0.016, 0.003, d["segs"], "paint_2", 4)
            tape.rotation_euler = (0.0, 0.0, math.pi * 0.5)
            tape.location = (side * (hw + 0.002), 0.0, 0.0)
            parts.append(tape)
    # (Far off, the hub's hidden behind the spokes but for a big drum.)
    hub_x, hub_r = hub(p, lod, parts, laced) if lod < 2 or lk.get("hub") == "drum" else (0.0, 0.0)
    if lk.get("disc"):
        # Moon discs: smooth domed covers over both sides.
        tag = FINISH.get(str(lk.get("disc_finish", "")), rim_tag)
        for side in (-1.0, 1.0):
            x0 = side * hw * 0.42
            prof = [(x0, 0.0), (x0, rim_r - 0.012), (x0 + side * 0.006, rim_r * 0.78), (x0 + side * 0.012, rim_r * 0.4), (x0 + side * 0.013, 0.0)]
            if lod == 2:
                prof = [(x0, 0.0), (x0, rim_r - 0.012), (x0 + side * 0.013, 0.0)]
            parts.append(kit.revolve("moon", prof, d["segs"], tag))
    elif laced and d["spoke_sides"]:
        count = int(lk.get("spokes", p.get("spokes", 36 if style == "wire" else 18)))
        thick = 0.0022 if style == "wire" else 0.003
        tag = FINISH.get(str(lk.get("spoke_finish", "")), "chrome")
        for i in range(count):
            a = 2.0 * math.pi * i / count
            side = 1.0 if i % 2 == 0 else -1.0
            # Laced tangentially: each spoke leaves the hub well round from where it meets the rim,
            # half of each side's leading and half trailing, so they cross on the way out.
            lead = 1.0 if (i // 2) % 2 == 0 else -1.0
            b = a + lead * 0.42
            at_hub = (side * hub_x, math.cos(b) * hub_r, math.sin(b) * hub_r)
            at_rim = (side * 0.006, math.cos(a) * (rim_r - 0.02), math.sin(a) * (rim_r - 0.02))
            parts.append(kit.tube("spoke", at_hub, at_rim, thick, d["spoke_sides"], tag))
            if lod == 0:
                parts.append(kit.tube("nipple", at_rim, (side * 0.005, math.cos(a) * (rim_r - 0.012), math.sin(a) * (rim_r - 0.012)), 0.0032, 6, tag))
    elif not laced:
        cast_spokes(p, lod, parts, rim_r, rim_w, rim_tag)
    if lod < 2:
        # The tyre valve poking in through the rim, at the top.
        parts.append(kit.tube("valve", (0.0, 0.0, rim_r - 0.012), (0.0, 0.0, rim_r - 0.05), 0.004, 8, "rubber"))
    return kit.join(parts, "wheel")


def cast_spokes(p, lod, parts, rim_r, rim_w, tag):
    """A cast wheel's spokes, from the boss round the hub to the rim: swept and tapering, split in
    pairs, or forked in a Y near the rim."""
    lk = p.get("look", {})
    d = DETAIL[lod]
    style = str(p.get("style", "cast"))
    spokes = int(p.get("spokes", 3 if style == "carbon" else 5))
    thick = min(max(0.12 / spokes, 0.016), 0.04)
    depth = min(max(rim_w * 0.45, 0.03), 0.05)
    sides = [10, 6, 3][lod]
    # The boss the spokes grow from.
    if lod < 2:
        parts.append(kit.revolve("boss", [(-depth * 0.5, 0.02), (-depth * 0.55, 0.05), (depth * 0.55, 0.05), (depth * 0.5, 0.02)], d["hub_segs"], tag))

    def at(a, r):
        return (0.0, math.cos(a) * r, math.sin(a) * r)

    for i in range(spokes):
        a = 2.0 * math.pi * i / spokes
        if lk.get("split"):
            for split in (-0.09, 0.09):
                b = a + split
                pts = [at(b * 0.6 + a * 0.4, 0.04), at(b, rim_r * 0.55), at(b, rim_r - 0.008)]
                parts.append(kit.sweep("spoke", pts if lod < 2 else [pts[0], pts[2]], thick * 0.25, sides, tag,
                    squash=depth * 0.4 / (thick * 0.25), side=(1.0, 0.0, 0.0)))
        elif style == "y":
            ends = [at(a, 0.04), at(a, rim_r * 0.3), at(a, rim_r * 0.57)] if lod < 2 else [at(a, 0.04), at(a, rim_r - 0.008)]
            parts.append(kit.sweep("spoke", ends, 0.011, sides, tag,
                squash=depth * 0.32 / 0.011, side=(1.0, 0.0, 0.0)))
            for split in ((-0.2, 0.2) if lod < 2 else ()):
                parts.append(kit.sweep("arm", [at(a, rim_r * 0.55), at(a + split * 0.6, rim_r * 0.75), at(a + split, rim_r - 0.008)], 0.008, sides, tag,
                    squash=depth * 0.25 / 0.008, side=(1.0, 0.0, 0.0)))
        else:
            # Thick at the hub, tapering and sweeping a touch as it reaches the rim.
            pts = []
            for f in ((0.0, 0.3, 0.65, 1.0) if lod < 2 else (0.0, 1.0)):
                b = a + 0.07 * math.sin(f * math.pi)
                pts.append(at(b, 0.045 + (rim_r - 0.01 - 0.045) * f))
            radii = [thick * 0.85, thick * 0.6, thick * 0.5, thick * 0.62] if lod < 2 else [thick * 0.7, thick * 0.6]
            parts.append(kit.sweep("spoke", pts, [r * 0.5 for r in radii], sides, tag, squash=depth * 0.7 / (thick * 0.5), side=(1.0, 0.0, 0.0)))


def cush_drive(lod):
    """The rear wheel's cush drive carrying the sprocket: rubber blocks in a cast carrier, bolted on."""
    d = DETAIL[lod]
    parts = [kit.revolve("carrier", [(-0.107, 0.02), (-0.107, 0.07), (-0.077, 0.07), (-0.077, 0.02)], d["hub_segs"] * 2, "cast_alloy")]
    if lod < 2:
        for i in range(6):
            t = 2.0 * math.pi * i / 6
            parts.append(kit.hex_nut("bolt", (-0.107, math.cos(t) * 0.052, math.sin(t) * 0.052), (-1.0, 0.0, 0.0), 0.006, 0.005))
    return kit.join(parts, "cush_drive")


def parts():
    out = []
    axle = {"axle": ((0.0, 0.0, 0.0), (1.0, 0.0, 0.0))}
    for part_id in catalogue():
        def build(lod, part_id=part_id):
            return wheel(part_id, lod)
        out.append({"kind": "wheel", "path": "wheel/%s.glb" % part_id, "build": build, "mounts": axle})
    out.append({"kind": "wheel", "path": "wheel/fitting/cush_drive.glb", "build": cush_drive, "mounts": axle})
    return out
