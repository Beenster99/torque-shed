"""The exhaust's silencers, one glb for each can shape BikeModel draws (_can): round, oval,
megaphone, hex, short, peashooter, slash, open, fishtail, turnout, baloney, trumpet, reverse, tri
and stubby. Each is drawn at a reference 0.5 m long with a biggest radius of 0.05 m, its origin on
the inlet (mount_inlet) and running back along -Y to the end of the can, with mount_outlet where the
gas comes out. The game stretches it between BikeModel's two can points and scales it by the can's
radius, as BikeModel draws its own (a can on the left is mirrored, so a turnout turns out).

The body is chrome, which the game re-tags by the part's look (black, brushed, titanium, carbon,
or paint on a slip-on's coloured can); the tail pipe is black metal, the clamp and end cap
brushed steel."""

import math

import kit

L = 0.5                   # m: the reference can's length, inlet to end
R = 0.05                  # m: its biggest radius

DETAIL = [
    {"segs": 32, "rivets": True, "clamp": True, "tip": True},
    {"segs": 14, "rivets": False, "clamp": True, "tip": True},
    {"segs": 8, "rivets": False, "clamp": False, "tip": False},
]

# Each shape as BikeModel draws it: its profile down the can as (how far along, radius over R),
# how many sides (0 for round), its across squash (an oval), the tail pipe's radius over R and how
# far along it sits, whether it has the clamp and riveted end cap, and how far along the gas leaves.
SHAPES = {
    "round": {"profile": [(0.0, 0.55), (0.1, 1.0), (0.9, 1.0), (1.0, 0.85)], "tip": (0.45, 1.0), "details": True},
    "oval": {"profile": [(0.0, 0.55), (0.12, 1.0), (0.88, 1.0), (1.0, 0.8)], "squash": 0.78, "tip": (0.5, 1.0), "details": True},
    "hex": {"profile": [(0.0, 0.55), (0.12, 0.95), (0.85, 1.0), (1.0, 0.9)], "sides": 6, "tip": (0.6, 1.0), "details": True},
    "tri": {"profile": [(0.0, 0.55), (0.12, 1.05), (0.88, 1.05), (1.0, 0.9)], "sides": 3, "tip": (0.45, 1.0)},
    "megaphone": {"profile": [(0.0, 0.5), (0.3, 0.65), (0.75, 0.95), (1.0, 1.1), (1.04, 1.0)], "cone": (1.01, 1.11, 0.98, 0.5),
        "tip": (0.35, 1.11), "out": 1.12},
    "reverse": {"profile": [(0.0, 0.5), (0.15, 0.8), (1.0, 1.1)], "cap": (1.0, 1.06, 1.1, 0.6), "tip": (0.35, 1.06), "out": 1.08},
    "trumpet": {"profile": [(0.0, 0.45), (0.6, 0.45), (0.85, 0.6), (0.95, 0.95), (1.0, 1.15)], "tip": (0.7, 1.0)},
    "baloney": {"profile": [(0.0, 0.4), (0.06, 0.7), (0.5, 0.75), (0.94, 0.7), (1.0, 0.35)]},
    "stubby": {"profile": [(0.0, 0.7), (0.08, 1.15), (0.4, 1.1)], "tip": (0.55, 0.4), "out": 0.42},
    "short": {"profile": [(0.0, 0.6), (0.09, 1.0), (0.6, 0.95)], "tip": (0.5, 0.6), "out": 0.62},
    "peashooter": {"profile": [(0.0, 0.6), (0.15, 0.8), (0.9, 0.8), (1.0, 0.7)], "tip": (0.4, 1.0)},
    # (BikeModel draws these two at a fixed radius, 0.032 and 0.028 m: here that's over a 0.05 can.)
    "slash": {"profile": [(0.0, 0.64), (1.0, 0.64)], "lip": True, "slash": 0.6, "out": 1.02},
    "open": {"profile": [(0.0, 0.56), (1.0, 0.56)], "open": True, "out": 1.02},
    "fishtail": {"profile": [(0.0, 0.5), (0.1, 0.85), (0.78, 0.85)], "fish": True},
    "turnout": {"profile": [(0.0, 0.55), (0.12, 0.9), (0.85, 0.85)], "turnout": True},
}


def _sections(shape, lod):
    """The body's rings for kit.loft: (y, half width, up, down, squareness), eased between the
    profile's points (more rings close up, so the swells are round)."""
    sq = shape.get("squash", 1.0)
    steps = [5, 2, 1][lod]
    prof = shape["profile"]
    out = [(-prof[0][0] * L, prof[0][1] * R * sq, prof[0][1] * R, prof[0][1] * R, 2.0)]
    for (t0, f0), (t1, f1) in zip(prof, prof[1:]):
        n = steps if abs(f1 - f0) > 0.02 else 1
        for i in range(1, n + 1):
            u = i / n
            u = u * u * (3.0 - 2.0 * u)
            f = f0 + (f1 - f0) * u
            out.append((-(t0 + (t1 - t0) * i / n) * L, f * R * sq, f * R, f * R, 2.0))
    if shape.get("fish"):
        # Flattening and flaring out into the fishtail.
        for t, w, h, n in ((0.86, 1.05, 0.62, 2.4), (0.94, 1.32, 0.45, 2.8), (1.0, 1.5, 0.35, 3.0)):
            out.append((-t * L, w * R, h * R, h * R, n))
    return out


def can(name, lod):
    shape = SHAPES[name]
    d = DETAIL[lod]
    sides = shape.get("sides", 0) or d["segs"]
    parts = []
    body = kit.loft("body", _sections(shape, lod), sides, "chrome", caps=True)
    if shape.get("sides") == 3:
        # (A tri can points a corner inboard, as BikeModel's three-sided sweep does.)
        body.rotation_euler = (0.0, math.pi, 0.0)
    parts.append(body)
    if shape.get("slash"):
        # The end cut back at a slant, the top running out to the end and the bottom cut short
        # (BikeModel's slash can ends at its end point too), with a rolled lip round the cut.
        rr = shape["profile"][-1][1] * R
        slope = shape["slash"]
        for v in body.data.vertices:
            if v.co.y < -L * 0.999:
                v.co.y += (rr - v.co.z) * slope
        if lod < 2:
            lip = kit.ring("lip", 0.0, rr - 0.001, 0.0028, d["segs"], "chrome", 4 if lod else 6)
            lip.scale = (1.0, 1.0, math.hypot(1.0, slope))
            lip.rotation_euler = (math.atan(slope), 0.0, 0.0)
            lip.location = (0.0, -L + rr * slope + 0.001, 0.0)
            parts.append(lip)
    end = L * shape["profile"][-1][0]
    tip = shape.get("tip")
    if tip and d["tip"]:
        r, at = tip
        parts.append(kit.tube("tailpipe", (0.0, -at * L + 0.01, 0.0), (0.0, -at * L - 0.01, 0.0), r * R, max(sides, 8), "black_metal"))
    for key in ("cone", "cap"):
        if shape.get(key):
            t0, t1, r0, r1 = shape[key]
            parts.append(kit.tube(key, (0.0, -t0 * L, 0.0), (0.0, -t1 * L, 0.0), r0 * R, d["segs"], "chrome", 0.0, r1 * R))
    if shape.get("open") and d["tip"]:
        # The dark inside of the open pipe's end.
        parts.append(kit.tube("bore", (0.0, -end + 0.003, 0.0), (0.0, -end - 0.0005, 0.0), shape["profile"][-1][1] * R * 0.8, d["segs"], "black_metal"))
    if shape.get("details"):
        rend = shape["profile"][-1][1] * R * shape.get("squash", 1.0)
        if d["clamp"]:
            neck = shape["profile"][0][1] * R
            parts.append(kit.ring("clamp", -0.02, neck + 0.004, 0.005, d["segs"], "brushed_steel", 6 if lod == 0 else 4))
            parts.append(kit.ring("endcap", -end + 0.004, rend * 0.97, 0.005, d["segs"], "brushed_steel", 6 if lod == 0 else 4))
        if d["rivets"]:
            for i in range(6):
                a = 2.0 * math.pi * i / 6
                at = (math.cos(a) * rend * 0.7 * shape.get("squash", 1.0), -end, math.sin(a) * rend * 0.7)
                parts.append(kit.sphere("rivet", at, 0.003, (1.0, 0.6, 1.0), 8, "brushed_steel"))
    if shape.get("turnout"):
        # The end pipe turning out to the side.
        bb = (0.0, -0.85 * L, 0.0)
        bend = (0.0, -0.85 * L - 0.03, 0.0)
        out = can_outlet(name)
        segs = max(8, d["segs"] // 2)
        parts.append(kit.tube("outpipe", bb, bend, 0.016, segs, "chrome"))
        parts.append(kit.sphere("elbow", bend, 0.016, (1.0, 1.0, 1.0), segs, "chrome"))
        parts.append(kit.tube("outpipe", bend, out, 0.016, segs, "chrome"))
    return kit.join(parts, "can")


def parts():
    out = []
    for name in SHAPES:
        def build(lod, name=name):
            return can(name, lod)
        outlet = can_outlet(name)
        out.append({"kind": "exhaust", "path": "exhaust/can/%s.glb" % name, "build": build,
            "mounts": {"inlet": ((0.0, 0.0, 0.0), (0.0, -1.0, 0.0)), "outlet": (outlet, (0.0, -1.0, 0.0) if name != "turnout" else (0.8, -0.6, -0.16))}})
    return out


def can_outlet(name):
    """Where the gas leaves a can (BikeModel's _can return), without building it."""
    shape = SHAPES[name]
    if shape.get("turnout"):
        return (0.05, -0.85 * L - 0.04, -0.01)
    return (0.0, -shape.get("out", 1.02) * L, 0.0)
