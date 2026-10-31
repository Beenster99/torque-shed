"""The frame's tube section, the welds where its tubes meet, the head stock's bearing cups, the
battery box and the frame's own footpegs.

The game lays every frame out round the bike it's on (its head stock, engine, pivot and seat), so
its tubes are the section here swept along the routes BikeModel bends them round (like the exhaust's
pipes: BlenderParts.sweep_section), at each tube's own radius: "frame/tube/round.glb", a short
length of round steel tube at radius 1, running 0.1 m back along -Y with its ends left open.

"frame/weld.glb" is the bead round a tube where it's welded to another, a TIG weld's ripples all
round it: a ring at radius 1 round the tube's axis (Blender +Z, the game's +Y), which the game
scales to the tube and sets where the tube meets the one it's welded to. It and the tube are
`paint`, in the frame's finish.

"frame/bearing_cup.glb": the steering head bearing's cup pressed into each end of the head stock
(its origin on the end, the game's +Y out of it). "frame/battery_box.glb": the battery in its tray
under the seat, a unit box the game scales to the room it has. "frame/footpeg.glb": a footpeg on
its hinge, running out along +X from the hinge at x -0.05 to its tip at 0.05 (the game mirrors it
for the left)."""

import math

import bmesh
from mathutils import Vector

import kit

LENGTH = 0.1

TUBE = [
    {"segs": 16, "rings": 2},
    {"segs": 10, "rings": 1},
    {"segs": 6, "rings": 1},
]


def tube(lod):
    d = TUBE[lod]
    secs = [(-LENGTH * i / d["rings"], 1.0, 1.0, 1.0, 2.0) for i in range(d["rings"] + 1)]
    return kit.join([kit.loft("tube", secs, d["segs"], "paint", caps=False)], "tube")


WELD = [
    {"segs": 48, "minor": 6, "ripples": 24},
    {"segs": 16, "minor": 4, "ripples": 0},
    {"segs": 8, "minor": 3, "ripples": 0},
]


def weld(lod):
    """A bead half sunk into the tube, its ripples laid down one after another round it."""
    d = WELD[lod]
    bm = bmesh.new()
    rows = []
    for i in range(d["segs"]):
        t = 2.0 * math.pi * i / d["segs"]
        rip = 1.0 + (0.14 * math.cos(t * d["ripples"]) if d["ripples"] else 0.0)
        thick = 0.17 * rip
        row = []
        for j in range(d["minor"]):
            # Only the half outside the tube: from the tube's face out over the bead and back.
            u = -0.5 * math.pi + math.pi * j / (d["minor"] - 1)
            r = 1.0 + thick * math.cos(u) * 0.9
            row.append(bm.verts.new((r * math.cos(t), r * math.sin(t), thick * math.sin(u))))
        rows.append(row)
    for i in range(d["segs"]):
        a, b = rows[i], rows[(i + 1) % d["segs"]]
        for j in range(d["minor"] - 1):
            bm.faces.new((a[j], a[j + 1], b[j + 1], b[j]))
    for f in bm.faces:
        c = f.calc_center_median()
        if f.normal.dot(c - Vector((0.0, 0.0, c.z))) < 0.0:
            f.normal_flip()
    return kit.join([kit._new_object("weld", bm, "paint")], "weld")


def bearing_cup(lod):
    segs = [24, 12, 6][lod]
    prof = [(0.0, 0.0), (0.0, 0.0405), (0.0045, 0.043), (0.009, 0.0425), (0.011, 0.04), (0.011, 0.0)] if lod == 0 else \
        [(0.0, 0.0), (0.0, 0.043), (0.011, 0.04), (0.011, 0.0)]
    ob = kit.revolve("cup", prof, segs, "raw_steel")
    ob.rotation_euler = (0.0, -math.pi * 0.5, 0.0)
    return kit.join([ob], "cup")


def battery_box(lod):
    parts = []
    bevel = 0.02 if lod == 0 else 0.0
    # The tray: an open-topped box most of the battery's height.
    parts.append(kit.prism("tray", kit.rounded_rect(0.5, 0.5, 0.06, 2 if lod == 0 else 1), -0.5, 0.3, "black_metal", bevel))
    # The battery standing up out of it, a little narrower.
    parts.append(kit.prism("battery", kit.rounded_rect(0.46, 0.44, 0.03, 1 if lod == 0 else 1), 0.3, 0.46, "plastic"))
    if lod < 2:
        # Its two terminals, and the rubber strap over the top holding it in.
        for y in (-0.3, 0.3):
            parts.append(kit.tube("terminal", (0.25, y, 0.46), (0.25, y, 0.5), 0.05, 8, "raw_steel"))
        parts.append(kit.prism("strap", kit.rounded_rect(0.52, 0.08, 0.02, 1), 0.44, 0.48, "rubber"))
    ob = kit.join(parts, "battery_box")
    return ob


def footpeg(lod):
    segs = [16, 10, 6][lod]
    parts = []
    # The hinge's clevis on the inner end, then the rubber-covered peg with grooves round it, and
    # an alloy end cap.
    parts.append(kit.prism("clevis", kit.rounded_rect(0.012, 0.016, 0.005, 2 if lod == 0 else 1), -0.012, 0.012, "cast_alloy",
        plane="YZ", at=(-0.038, 0.0, 0.0)))
    secs = []
    grooves = 6 if lod == 0 else 0
    if grooves:
        for k in range(grooves * 2 + 1):
            y = -0.026 + 0.068 * k / (grooves * 2)
            r = 0.0115 if k % 2 == 0 else 0.0098
            secs.append((y, r, r, r, 2.0))
    else:
        secs = [(-0.026, 0.011, 0.011, 0.011, 2.0), (0.042, 0.011, 0.011, 0.011, 2.0)]
    peg = kit.loft("peg", secs, segs, "rubber")
    peg.rotation_euler = (0.0, 0.0, -math.pi * 0.5)
    parts.append(peg)
    parts.append(kit.tube("cap", (0.042, 0.0, 0.0), (0.05, 0.0, 0.0), 0.0105, segs, "cast_alloy", 0.002 if lod == 0 else 0.0))
    if lod < 2:
        parts.append(kit.tube("pin", (-0.038, 0.0, -0.016), (-0.038, 0.0, 0.016), 0.004, 8, "raw_steel"))
    return kit.join(parts, "footpeg")


def parts():
    return [
        {"kind": "frame", "path": "frame/tube/round.glb", "build": tube, "mounts": {}},
        {"kind": "weld", "path": "frame/weld.glb", "build": weld, "mounts": {}},
        {"kind": "frame_fitting", "path": "frame/bearing_cup.glb", "build": bearing_cup, "mounts": {}},
        {"kind": "frame_fitting", "path": "frame/battery_box.glb", "build": battery_box, "mounts": {}},
        {"kind": "frame_fitting", "path": "frame/footpeg.glb", "build": footpeg, "mounts": {}},
    ]
