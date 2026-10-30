"""The exhaust's pipe sections and the header flange.

A section is a short length of pipe at radius 1, running 0.1 m back along -Y from its origin with
its ends left open: the game lays copies of it end to end along the route BikeModel bends each
header round (BlenderParts.lay_along), at that header's radius, so the pipe follows every bike's
own ports and frame. "plain" is smooth pipe; "wrap" is pipe in heat wrap, its bands raised (tagged fabric).

The flange is the plate bolted over each exhaust port, its origin on the port and +Z out of it."""

import kit

LENGTH = 0.1             # m: one section, along the route

# (The game sweeps a section's rings onto the header's curve, and a four-into-one runs to some 60
# sections, so a section is kept to 16 sides and 2 rings close up: about 64 triangles.)
DETAIL = [
    {"segs": 16, "rings": 2, "bands": 2},
    {"segs": 10, "rings": 1, "bands": 0},
    {"segs": 6, "rings": 1, "bands": 0},
]


def plain(lod):
    d = DETAIL[lod]
    secs = [(-LENGTH * i / d["rings"], 1.0, 1.0, 1.0, 2.0) for i in range(d["rings"] + 1)]
    return kit.join([kit.loft("pipe", secs, d["segs"], "chrome", caps=False)], "pipe")


def wrap(lod):
    """Each band of wrap proud where it starts and tucked under the next where it ends (the bands'
    overlap makes the ridges); far off, plain pipe a little fatter."""
    d = DETAIL[lod]
    if not d["bands"]:
        secs = [(-LENGTH * i / d["rings"], 1.04, 1.04, 1.04, 2.0) for i in range(d["rings"] + 1)]
        return kit.join([kit.loft("pipe", secs, d["segs"], "fabric", caps=False)], "pipe")
    secs = []
    for b in range(d["bands"]):
        y0, y1 = -LENGTH * b / d["bands"], -LENGTH * (b + 1) / d["bands"]
        secs += [(y0, 1.07, 1.07, 1.07, 2.0), (y1, 1.0, 1.0, 1.0, 2.0)]
    return kit.join([kit.loft("pipe", secs, d["segs"], "fabric", caps=False)], "pipe")


def flange(lod):
    """A round plate over the port with an ear each side for its two studs and nuts."""
    d = DETAIL[lod]
    parts = [kit.tube("plate", (0.0, 0.0, 0.0), (0.0, 0.0, 0.01), 0.03, max(8, d["segs"] * 2), "raw_steel", 0.0015 if lod == 0 else 0.0)]
    if lod < 2:
        outline = kit.rounded_rect(0.05, 0.012, 0.011, 3 if lod == 0 else 1)
        parts.append(kit.prism("ears", outline, 0.0, 0.008, "raw_steel"))
        for x in (-0.04, 0.04):
            parts.append(kit.hex_nut("nut", (x, 0.0, 0.008), (0.0, 0.0, 1.0), 0.0065, 0.007))
    return kit.join(parts, "flange")


def parts():
    out = []
    for name, build in (("plain", plain), ("wrap", wrap)):
        out.append({"kind": "exhaust", "path": "exhaust/pipe/%s.glb" % name, "build": build, "mounts": {}})
    out.append({"kind": "exhaust", "path": "exhaust/fitting/flange.glb", "build": flange,
        "mounts": {"exhaust_port": ((0.0, 0.0, 0.0), (0.0, 0.0, 1.0))}})
    return out
