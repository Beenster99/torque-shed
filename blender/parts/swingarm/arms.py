"""The plain swingarm a frame comes with (BikeModel's "box" arm), for the new look: each arm a
rectangular steel box section with its edges rounded, deeper at the pivot and tapering to the
axle, ending in the slotted block the axle sits in with the chain adjuster's bolt and lock nut out
of the back of it; and the box-section bridge welded across between the two arms by the pivot.

"swingarm/box_arm.glb" runs back from the pivot along the game's +Z (Blender -Y) to the axle at
REACH (the game stretches it to the bike's own arm), centred on its own line (the game sets one
each side). "swingarm/bridge.glb" runs across X from -0.5 to 0.5 (the game stretches it between
the arms). The arm and bridge are `paint`, in the frame's finish."""

import kit

REACH = 0.55
DETAIL = [{"segs": 20, "rings": 6}, {"segs": 8, "rings": 2}, {"segs": 4, "rings": 1}]


def box_arm(lod):
    d = DETAIL[lod]
    secs = []
    for i in range(d["rings"] + 1):
        f = i / d["rings"]
        h = 0.035 - 0.006 * f
        secs.append((-REACH * f * 0.96, 0.0175, h, h, 6.0))
    parts = [kit.loft("arm", secs, d["segs"], "paint")]
    # The axle block, a little proud of the arm all round, with the axle's slot through it.
    block = kit.rounded_rect(0.045, 0.03, 0.008, 2 if lod == 0 else 1)
    parts.append(kit.prism("block", block, -0.022, 0.022, "cast_alloy", 0.002 if lod == 0 else 0.0, plane="YZ", at=(0.0, -REACH, 0.0)))
    if lod < 2:
        # The adjuster bolt out of the back, its lock nut and its head.
        parts.append(kit.tube("bolt", (0.0, -REACH - 0.045, 0.0), (0.0, -REACH - 0.075, 0.0), 0.005, 8, "raw_steel"))
        parts.append(kit.tube("nut", (0.0, -REACH - 0.048, 0.0), (0.0, -REACH - 0.056, 0.0), 0.0085, 6, "raw_steel"))
        parts.append(kit.tube("head", (0.0, -REACH - 0.07, 0.0), (0.0, -REACH - 0.078, 0.0), 0.008, 6, "raw_steel"))
    if lod == 0:
        # The axle's end showing through the slot.
        parts.append(kit.tube("axle", (-0.024, -REACH, 0.0), (0.024, -REACH, 0.0), 0.009, 12, "raw_steel"))
    return kit.join(parts, "box_arm")


def bridge(lod):
    segs = DETAIL[lod]["segs"]
    secs = [(-0.5, 0.025, 0.035, 0.035, 6.0), (0.5, 0.025, 0.035, 0.035, 6.0)]
    ob = kit.loft("bridge", secs, segs, "paint")
    ob.rotation_euler = (0.0, 0.0, -1.5707963267948966)
    return kit.join([ob], "bridge")


def parts():
    return [
        {"kind": "swingarm", "path": "swingarm/box_arm.glb", "build": box_arm, "mounts": {}},
        {"kind": "swingarm", "path": "swingarm/bridge.glb", "build": bridge, "mounts": {}},
    ]
