"""The gearboxes BikeModel._draw_gearbox puts behind the crankcase, one set for each gearbox in the
catalogue, in the game's axes round the point each piece is put on (a point (x, y, z) in the game's
axes is Blender's (x, -z, y)):

- "gearbox/<id>/case.glb": the gearbox's case, round the middle of the box BikeModel draws behind
  the crankcase (_engine_c + (0, -0.06, 0.22)). It is drawn for the narrowest case (0.16 m across,
  a single's) and the game stretches it across (X only) to the engine's width, so the detail on its
  flanks keeps its shape. A unit gearbox's case is a plain casting with ribs on its flanks; the
  vintage four-speed's is a separate rounded box; the cruiser's a big ribbed transmission case with
  its top cover; a cassette box has the cassette's end plate bolted on its right.
- "gearbox/<id>/clutch.glb": the clutch's side of it, on the right of the crankcase, its origin
  where the cover meets the case (_engine_c + (_block_w / 2, -0.02, 0.1)) and +X out of the bike: a
  plain round cover, the vintage box's kidney-shaped outer cover reaching back over the gearbox,
  the enduro's with its oil window and guard ribs, the MX box's magnesium cover and anodised cap,
  the cassette's flat modern cover, the cruiser's chrome derby cover, or the race box's open dry
  clutch (the basket, plates and springs) behind a vented guard ring.
- "gearbox/selector.glb": the gear change shaft out of the left of the case, its origin at the end
  of the shaft where its arm clamps on, the arm (and the rod end's ball joint on it) pointing down
  and forward; the game turns it round the shaft to point at the gear lever and draws the linkage
  rod from there.
- "gearbox/quickshifter.glb": the race box's strain sensor, which the game puts in the rod.
- "gearbox/kickstart.glb": the kickstart folded up behind the right footrest, its origin on the
  shaft (_engine_c + (_block_w / 2 + 0.035, -0.04, 0.2)).

Tags: paint (the gearbox's own colour: covers, the clutch's pressure plate), cast_alloy (cases, in
the gearbox's colour too), polished_alloy, chrome, black_metal, anodised, raw_steel, glass, rubber."""

import math

import kit

# Each gearbox's case and clutch side.
GEARBOXES = {
    "four_vintage": {"case": "vintage", "clutch": "vintage"},
    "five_wide": {"case": "unit", "clutch": "plain"},
    "six_wide_enduro": {"case": "unit", "clutch": "enduro"},
    "five_close_mx": {"case": "compact", "clutch": "mx"},
    "six_close": {"case": "cassette", "clutch": "cassette"},
    "six_cruiser_od": {"case": "cruiser", "clutch": "derby"},
    "six_race_quickshift": {"case": "cassette", "clutch": "dry"},
}

# The case's half width as drawn (the game stretches it to _block_w * 0.4).
HW = 0.08
# Which way the selector's arm points, game axes (BikeModel.GEARBOX_ARM: the game turns it round
# the shaft to point at the gear lever).
ROD = (0.0, -0.06, -0.08)

DETAIL = [
    {"ring": 18, "round": 12, "small": 6},
    {"ring": 12, "round": 8, "small": 5},
    {"ring": 8, "round": 6, "small": 4},
]


def g(x, y, z):
    return (x, -z, y)


def norm(v):
    n = math.sqrt(sum(c * c for c in v))
    return tuple(c / n for c in v)


def disc(name, r, x0, x1, segs, tag, y=0.0, z=0.0, bevel=0.0):
    """A disc round the game's X axis (Blender's X) from x0 to x1, centred at game (y, z)."""
    return kit.prism(name, [(r * math.cos(2.0 * math.pi * k / segs), r * math.sin(2.0 * math.pi * k / segs)) for k in range(segs)],
        x0, x1, tag, bevel, 1, plane="YZ", at=(0.0, -z, y))


def turned(name, profile, segs, tag, y=0.0, z=0.0):
    """A piece turned round the game's X axis (a cover's dome): `profile` as (x, radius), centred at game (y, z)."""
    ob = kit.revolve(name, profile, segs, tag)
    ob.location = (0.0, -z, y)
    return ob


def bolt_ring(parts, x, r, count, size, segs, y=0.0, z=0.0, side=1.0, a0=0.3, tag="raw_steel"):
    """Hex bolt heads round a circle on a face at game x, facing out along X (side)."""
    for k in range(count):
        a = a0 + 2.0 * math.pi * k / count
        at = g(x, y + math.cos(a) * r, z + math.sin(a) * r)
        if segs:
            parts.append(kit.hex_nut("bolt", at, (side, 0.0, 0.0), size, size * 0.75, tag))


def outline_of(points, segs):
    """The convex outline round circles [(y, z, r), ...] in the YZ plane (game axes), as Blender (u, v)
    for kit.prism's YZ plane: (u, v) = (-z, y)."""
    pts = []
    for y, z, r in points:
        for k in range(segs):
            a = 2.0 * math.pi * k / segs
            pts.append((-(z + math.sin(a) * r), y + math.cos(a) * r))
    # (Gift wrap: the hull, anticlockwise.)
    pts = sorted(set((round(u, 6), round(v, 6)) for u, v in pts))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


# ---------------------------------------------------------------------------------------- cases

def case(kind, lod):
    d = DETAIL[lod]
    parts = []
    # Down the case from its nose (tucked into the back of the crankcase) to its rounded tail, as
    # (game z, how full); the height above and below the middle, and how square its section is.
    up, down, n, z0, z1 = 0.09, 0.09, 3.4, -0.12, 0.08
    if kind == "vintage":
        up, down, n, z0, z1 = 0.088, 0.085, 2.5, -0.1, 0.095
    elif kind == "compact":
        up, down, n, z0, z1 = 0.08, 0.08, 3.2, -0.12, 0.06
    elif kind == "cruiser":
        up, down, n, z0, z1 = 0.1, 0.085, 4.2, -0.12, 0.1
    ln = z1 - z0
    tail = [(0.0, 1.0), (0.55, 1.0), (0.75, 0.97), (0.88, 0.9), (0.96, 0.76), (1.0, 0.55)]
    if kind == "vintage":
        tail = [(0.0, 0.9), (0.3, 1.0), (0.55, 1.0), (0.75, 0.96), (0.88, 0.86), (0.96, 0.68), (1.0, 0.42)]
    if lod == 2:
        tail = [tail[0], tail[2], tail[-1]]
    secs = [(-(z0 + ln * f), HW * (0.94 + 0.06 * k), up * k, down * k, n) for f, k in tail]
    parts.append(kit.loft("case", secs, d["ring"], "cast_alloy"))
    if lod < 2:
        # Stiffening ribs down the flanks, each side, and a drain plug underneath.
        ribs = {"unit": 3, "cassette": 2, "compact": 2, "cruiser": 4, "vintage": 0}[kind] if lod == 0 else 0
        for side in (-1.0, 1.0):
            for i in range(ribs):
                z = z1 - 0.035 - i * 0.03
                if kind == "cassette" and side > 0:
                    continue   # (the cassette plate's on the right)
                x0, x1 = sorted((side * HW * 0.99, side * (HW * 0.99 + 0.006)))
                parts.append(kit.prism("rib", kit.rounded_rect(0.003, up * 0.62, 0.002, 1), x0, x1, "cast_alloy", plane="YZ", at=(0.0, -z, -0.01)))
        parts.append(kit.hex_nut("drain", g(0.0, -down * 0.98, z1 - 0.06), (0.0, 0.0, -1.0), 0.009, 0.008))
        # The breather on top, a short pipe bent back.
        if lod == 0:
            parts.append(kit.tube("breather", g(0.02, up * 0.95, z1 - 0.07), g(0.02, up + 0.025, z1 - 0.07), 0.005, d["small"], "rubber"))
    if kind == "cassette" and lod < 2:
        # The cassette's end plate on the right, held by a row of bolts round it.
        parts.append(kit.prism("cassette", kit.rounded_rect(0.045, 0.062, 0.016, 4), HW * 0.985, HW + 0.007, "cast_alloy", 0.002 if lod == 0 else 0.0,
            plane="YZ", at=(0.0, -(z1 - 0.055), -0.005)))
        if lod == 0:
            for u, v in ((-0.035, 0.052), (0.0, 0.056), (0.035, 0.052), (-0.035, -0.052), (0.0, -0.056), (0.035, -0.052), (0.04, 0.0)):
                parts.append(kit.hex_nut("bolt", g(HW + 0.007, -0.005 + v, z1 - 0.055 + u), (1.0, 0.0, 0.0), 0.0045, 0.003))
    if kind == "cruiser":
        # The transmission's top cover: a ribbed lid on its own gasket line, with its bolts.
        parts.append(kit.prism("lid", kit.rounded_rect(HW * 0.8, 0.075, 0.02, 4 if lod < 2 else 1), up * 0.92, up + 0.012, "polished_alloy",
            0.003 if lod == 0 else 0.0, at=(0.0, -(z1 - 0.085), 0.0)))
        if lod == 0:
            for i in range(5):
                parts.append(kit.prism("fin", kit.rounded_rect(HW * 0.66, 0.003, 0.001, 1), up + 0.012, up + 0.02, "polished_alloy",
                    at=(0.0, -(z1 - 0.085) + (i - 2) * 0.026, 0.0)))
        if lod == 0:
            for x in (-HW * 0.72, HW * 0.72):
                for zz in (-0.06, 0.0, 0.06):
                    parts.append(kit.hex_nut("bolt", g(x, up + 0.012, z1 - 0.085 + zz), (0.0, 0.0, 1.0), 0.004, 0.003))
        # The side door on the right: a chrome plate over the gear cluster's end.
        parts.append(kit.prism("door", kit.rounded_rect(0.05, 0.05, 0.022, 4 if lod < 2 else 1), HW * 0.98, HW + 0.008, "chrome",
            0.003 if lod == 0 else 0.0, plane="YZ", at=(0.0, -(z1 - 0.06), -0.01)))
        if lod == 0:
            bolt_ring(parts, HW + 0.008, 0.044, 6, 0.004, 1, y=-0.01, z=z1 - 0.06, a0=0.52)
    if kind == "vintage" and lod < 2:
        # The separate box's mounting plates, either side, and its adjuster drawbolt at the back.
        for side in (-1.0, 1.0):
            parts.append(kit.prism("plate", kit.rounded_rect(0.05, 0.06, 0.015, 3), side * (HW + 0.002) - 0.002, side * (HW + 0.002) + 0.002, "black_metal",
                plane="YZ", at=(0.0, -(z1 - 0.02), 0.02)))
        parts.append(kit.tube("drawbolt", g(HW + 0.004, 0.05, z1 - 0.02), g(HW + 0.004, 0.05, z1 + 0.04), 0.004, d["small"], "raw_steel"))
        parts.append(kit.hex_nut("adjuster", g(HW + 0.004, 0.05, z1 + 0.04), (0.0, 0.0, 1.0), 0.006, 0.006))
    return kit.join(parts, "case")


# --------------------------------------------------------------------------------- clutch side

def clutch(kind, lod):
    d = DETAIL[lod]
    parts = []
    rs = d["ring"]
    if kind == "vintage":
        # The outer cover: a polished kidney from the clutch back over the gearbox's end, the
        # kickstart's boss at its back and an inspection cap in its middle.
        out = outline_of([(0.0, 0.0, 0.098), (0.02, 0.12, 0.072)], max(rs // 2, 6))
        parts.append(kit.prism("cover", out, 0.0, 0.03, "polished_alloy", 0.008 if lod == 0 else (0.004 if lod == 1 else 0.0), 3 if lod == 0 else 1, plane="YZ"))
        parts.append(kit.prism("face", outline_of([(0.0, 0.0, 0.08), (0.02, 0.12, 0.055)], max(rs // 2, 6)), 0.03, 0.038, "polished_alloy",
            0.003 if lod == 0 else 0.0, plane="YZ"))
        parts.append(turned("cap", [(0.038, 0.032), (0.046, 0.032), (0.05, 0.026), (0.052, 0.0)], rs, "chrome", y=0.01, z=0.02))
        if lod < 2:
            parts.append(disc("boss", 0.022, 0.03, 0.048, d["round"], "polished_alloy", y=-0.02, z=0.1))
            if lod == 0:
                for k in range(6):
                    a = 2.0 * math.pi * k / 6
                    parts.append(kit.prism("knurl", kit.rounded_rect(0.002, 0.004, 0.001, 1), 0.046, 0.054, "chrome", plane="YZ",
                        at=(0.0, -(0.02 + math.sin(a) * 0.029), 0.01 + math.cos(a) * 0.029)))
                for y, z in ((0.085, -0.03), (0.07, 0.07), (-0.085, -0.03), (-0.07, 0.09), (0.0, -0.093), (0.06, 0.16), (-0.04, 0.17)):
                    parts.append(kit.hex_nut("screw", g(0.038, y, z), (1.0, 0.0, 0.0), 0.004, 0.003))
        return kit.join(parts, "clutch")
    if kind == "dry":
        # An open dry clutch: the basket's slotted drum, the plates' edges, the pressure plate
        # and its springs, behind a vented guard ring.
        parts.append(disc("back", 0.1, 0.0, 0.008, rs, "black_metal"))
        drum_segs = 24 if lod == 0 else (12 if lod == 1 else 8)
        parts.append(turned("drum", [(0.008, 0.0), (0.008, 0.08), (0.038, 0.08), (0.038, 0.074), (0.012, 0.074), (0.012, 0.0)], rs, "cast_alloy"))
        if lod == 0:
            # The basket's slots: dark gaps round the drum.
            for k in range(drum_segs // 2):
                a = 2.0 * math.pi * k / (drum_segs // 2)
                parts.append(kit.tube("slot", g(0.014, math.cos(a) * 0.0805, math.sin(a) * 0.0805), g(0.034, math.cos(a) * 0.0805, math.sin(a) * 0.0805), 0.0042, 4, "black_metal"))
            # The plates, friction and steel by turns, seen at their edges inside the basket.
            for i in range(4):
                x = 0.014 + i * 0.0066
                parts.append(disc("plate", 0.072, x, x + 0.0022, rs, "black_metal" if i % 2 == 0 else "raw_steel"))
        # The pressure plate, in the gearbox's colour (anodised), its springs and the centre nut.
        parts.append(turned("pressure", [(0.036, 0.0), (0.036, 0.066), (0.042, 0.064), (0.046, 0.05), (0.046, 0.0)], rs, "anodised"))
        if lod == 0:
            for k in range(6):
                a = 0.3 + 2.0 * math.pi * k / 6
                y, z = math.cos(a) * 0.036, math.sin(a) * 0.036
                parts.append(kit.tube("spring", g(0.046, y, z), g(0.056, y, z), 0.0075, d["small"], "chrome"))
                parts.append(kit.hex_nut("bolt", g(0.056, y, z), (1.0, 0.0, 0.0), 0.0045, 0.003))
            parts.append(disc("hub", 0.016, 0.046, 0.052, d["round"], "raw_steel"))
            parts.append(kit.hex_nut("nut", g(0.052, 0.0, 0.0), (1.0, 0.0, 0.0), 0.009, 0.006))
        # The guard: a carbon-black ring standing off the cover, on six posts.
        ring_out = turned("guard", [(0.05, 0.088), (0.05, 0.104), (0.058, 0.104), (0.058, 0.088)], rs, "black_metal")
        parts.append(ring_out)
        if lod == 0:
            for k in range(6):
                a = 2.0 * math.pi * k / 6
                y, z = math.cos(a) * 0.096, math.sin(a) * 0.096
                parts.append(kit.tube("post", g(0.006, y, z), g(0.05, y, z), 0.005, d["small"], "black_metal"))
        return kit.join(parts, "clutch")
    # A closed round cover: its flange, its dome, and what's on its face.
    r = {"plain": 0.1, "enduro": 0.098, "mx": 0.09, "cassette": 0.1, "derby": 0.108}[kind]
    depth = {"plain": 0.04, "enduro": 0.038, "mx": 0.034, "cassette": 0.032, "derby": 0.046}[kind]
    tag = {"plain": "paint", "enduro": "paint", "mx": "black_metal", "cassette": "paint", "derby": "chrome"}[kind]
    if lod == 2:
        prof = [(0.0, 0.0), (0.0, r), (depth * 0.6, r * 0.98), (depth, r * 0.8), (depth, 0.0)]
    elif kind == "derby":
        prof = [(0.0, 0.0), (0.0, r), (0.008, r), (0.012, r * 0.96), (0.03, r * 0.92), (0.04, r * 0.84), (depth, r * 0.7), (depth, 0.0)]
    else:
        prof = [(0.0, 0.0), (0.0, r), (0.01, r), (0.012, r * 0.95), (depth * 0.7, r * 0.93), (depth * 0.9, r * 0.88), (depth, r * 0.8), (depth, 0.0)]
    parts.append(turned("cover", prof, rs, tag))
    if lod == 0:
        bolt_ring(parts, 0.012, r * 0.975, {"plain": 8, "enduro": 9, "mx": 7, "cassette": 9, "derby": 8}[kind], 0.0045, 1)
    face = depth
    if kind == "plain":
        # A raised polished boss over the clutch's centre and the oil filler on top.
        parts.append(turned("boss", [(face, 0.0), (face, 0.042), (face + 0.006, 0.04), (face + 0.008, 0.032), (face + 0.008, 0.0)], rs, "polished_alloy"))
    elif kind == "cassette":
        parts.append(turned("cap", [(face, 0.0), (face, 0.056), (face + 0.005, 0.055), (face + 0.007, 0.05), (face + 0.007, 0.0)], rs, "polished_alloy"))
        if lod == 0:
            bolt_ring(parts, face + 0.007, 0.046, 5, 0.004, 1)
    elif kind == "mx":
        # The magnesium cover's bolt-on outer cap, anodised, and its window.
        parts.append(turned("cap", [(face, 0.0), (face, 0.05), (face + 0.008, 0.049), (face + 0.01, 0.043), (face + 0.01, 0.0)], rs, "anodised"))
        if lod == 0:
            bolt_ring(parts, face + 0.01, 0.044, 6, 0.0035, 1, a0=0.0)
    elif kind == "derby":
        # The derby cover: a raised chrome dome on its own ring of bolts.
        parts.append(turned("derby", [(face, 0.0), (face, 0.06), (face + 0.004, 0.06), (face + 0.012, 0.052), (face + 0.018, 0.035), (face + 0.02, 0.0)], rs, "chrome"))
        if lod == 0:
            bolt_ring(parts, face + 0.004, 0.065, 5, 0.0045, 1, tag="chrome")
    elif kind == "enduro":
        parts.append(turned("boss", [(face, 0.0), (face, 0.04), (face + 0.006, 0.036), (face + 0.006, 0.0)], rs, "cast_alloy"))
        if lod == 0:
            # Guard ribs across the bottom of the cover, where a boot or a rock hits it.
            for i in range(3):
                parts.append(kit.prism("rib", kit.rounded_rect(0.003, 0.03, 0.002, 1), face * 0.75, face + 0.004, "cast_alloy", plane="YZ",
                    at=(0.0, -(-0.03 + i * 0.03), -0.062)))
    if kind in ("enduro", "mx") and lod == 0:
        # The oil level window, low at the front.
        y, z = -0.05, -0.055
        parts.append(disc("window_rim", 0.016, face * 0.7, face * 0.7 + 0.008, d["round"], "chrome", y=y, z=z))
        parts.append(disc("window", 0.011, face * 0.7 + 0.008, face * 0.7 + 0.0085, d["round"], "glass", y=y, z=z))
    if kind != "derby" and lod == 0:
        # The oil filler on top: a ribbed cap.
        y, z = r * 0.5, r * 0.3
        parts.append(disc("filler", 0.014, face * 0.8, face + 0.009, d["round"], "anodised" if kind in ("mx", "enduro") else "black_metal", y=y, z=z,
            bevel=0.002 if lod == 0 else 0.0))
        if lod == 0:
            parts.append(kit.prism("slot", kit.rounded_rect(0.0018, 0.009, 0.001, 1), face + 0.008, face + 0.0095, "raw_steel", plane="YZ", at=(0.0, -z, y)))
    return kit.join(parts, "clutch")


# --------------------------------------------------------------------------------------- left side

def selector(lod):
    d = DETAIL[lod]
    parts = []
    # The splined shaft into the case, the pinch-bolt arm clamped on its end, pointing down the rod.
    parts.append(kit.tube("shaft", g(0.0, 0.0, 0.0), g(0.12, 0.0, 0.0), 0.0085, d["round"], "raw_steel"))
    rod = norm(ROD)
    arm_end = tuple(c * 0.032 for c in rod)
    parts.append(kit.sweep("arm", [g(-0.004, 0.0, 0.0), g(arm_end[0] - 0.002, arm_end[1], arm_end[2])], [0.013, 0.0075], d["round"], "cast_alloy", squash=0.45) if lod < 2
        else kit.tube("arm", g(-0.004, 0.0, 0.0), g(*arm_end), 0.009, d["round"], "cast_alloy"))
    parts.append(disc("clamp", 0.014, -0.012, 0.004, d["round"], "cast_alloy"))
    if lod == 0:
        parts.append(kit.hex_nut("pinch", g(-0.012, -0.014, 0.0), (-1.0, 0.0, 0.0), 0.0045, 0.004))
        # The rod end's ball joint where the linkage starts.
        parts.append(kit.sphere("joint", g(*arm_end), 0.0085, (1.0, 1.0, 1.0), d["round"], "chrome"))
    return kit.join(parts, "selector")


def quickshifter(lod):
    """The quickshifter's strain sensor that takes the linkage rod's place for a stretch: a black
    barrel along +Y (the game's up, which the game turns down the rod) round its middle, with a
    coloured band and its lead off to the loom."""
    d = DETAIL[lod]
    parts = [kit.tube("sensor", g(0.0, -0.02, 0.0), g(0.0, 0.02, 0.0), 0.009, d["round"], "black_metal")]
    for y in (-0.024, 0.024):
        parts.append(kit.hex_nut("locknut", g(0.0, y - 0.003, 0.0), (0.0, 0.0, 1.0), 0.0065, 0.006))
    if lod < 2:
        parts.append(kit.tube("band", g(0.0, 0.006, 0.0), g(0.0, 0.01, 0.0), 0.0095, d["round"], "anodised"))
        parts.append(kit.sweep("lead", [g(0.0, 0.0, 0.008), g(0.006, 0.01, 0.03), g(0.02, 0.04, 0.06)], 0.0025, d["small"], "rubber"))
    return kit.join(parts, "quickshifter")


def kickstart(lod):
    d = DETAIL[lod]
    parts = []
    pedal = (0.02, 0.1, 0.13)
    # The shaft out of the case, the lever's splined boss, the arm swept up and back, the pivot it
    # folds on and the rubber foot.
    parts.append(kit.tube("shaft", g(-0.03, 0.0, 0.0), g(0.012, 0.0, 0.0), 0.012, d["round"], "raw_steel"))
    parts.append(disc("boss", 0.017, 0.006, 0.028, d["round"], "chrome"))
    if lod == 0:
        parts.append(kit.hex_nut("pinch", g(0.028, -0.012, 0.0), (1.0, 0.0, 0.0), 0.0045, 0.004))
    knee = (0.022, 0.035, 0.07)
    parts.append(kit.sweep("arm", [g(0.017, 0.0, 0.0), g(*knee), g(pedal[0], pedal[1] - 0.012, pedal[2] - 0.008)], [0.011, 0.009, 0.008], d["round"], "chrome", squash=0.6))
    parts.append(disc("pivot", 0.012, pedal[0] - 0.006, pedal[0] + 0.012, d["round"], "chrome", y=pedal[1] - 0.008, z=pedal[2] - 0.006))
    parts.append(kit.tube("foot", g(pedal[0] + 0.004, pedal[1], pedal[2]), g(pedal[0] + 0.058, pedal[1], pedal[2]), 0.011, d["round"], "rubber"))
    if lod == 0:
        for k in range(4):
            x = pedal[0] + 0.012 + k * (0.04 / (3 if lod == 0 else 1))
            parts.append(kit.tube("grip", g(x, pedal[1], pedal[2]), g(x + 0.004, pedal[1], pedal[2]), 0.0123, d["round"], "rubber"))
    return kit.join(parts, "kickstart")


def parts():
    out = []
    for gid, spec in sorted(GEARBOXES.items()):
        out.append({"kind": "gearbox", "path": "gearbox/%s/case.glb" % gid, "build": (lambda lod, k=spec["case"]: case(k, lod)), "mounts": {}})
        out.append({"kind": "gearbox", "path": "gearbox/%s/clutch.glb" % gid, "build": (lambda lod, k=spec["clutch"]: clutch(k, lod)), "mounts": {}})
    out.append({"kind": "gearbox", "path": "gearbox/selector.glb", "build": selector, "mounts": {}})
    out.append({"kind": "gearbox", "path": "gearbox/quickshifter.glb", "build": quickshifter, "mounts": {}})
    out.append({"kind": "gearbox", "path": "gearbox/kickstart.glb", "build": kickstart, "mounts": {}})
    return out
